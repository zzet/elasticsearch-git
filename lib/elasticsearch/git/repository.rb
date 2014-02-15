require 'active_support/concern'
require 'active_model'
require 'elasticsearch/model'
require 'rugged'
require 'gitlab_git'

module Elasticsearch
  module Git
    module Repository
      extend ActiveSupport::Concern

      included do
        include Elasticsearch::Git::Model

        #index_name [Rails.application.class.parent_name.downcase, self.name.downcase, 'commits', Rails.env.to_s].join('-')

        mapping do
          indexes :blobs, type: :nested
          indexes :commits, type: :nested
        end

        def as_indexed_json(options = {})
          ij = {}
          ij[:blobs] = index_blobs
          ij[:commits] = index_commits
          #ij[:blobs] = index_tree(repository_for_indexing.lookup(repository_for_indexing.head.target).tree)
          #ij[:commits] = index_commits_by_ref(repository_for_indexing.head)
          ij
        end

        def index_blobs
          result = []

          target_sha = repository_for_indexing.head.target
          repository_for_indexing.index.each do |blob|
            b = EasyBlob.new(repository_for_indexing, blob)
            result.push(
              {
                id: "#{target_sha}_#{b.path}",
                oid: b.id,
                content: b.data,
                commit_sha: target_sha
              }
            ) if b.text?
          end

          result
        end

        def index_commits
          res = []

          repository_for_indexing.each_id do |oid|
            obj = repository_for_indexing.lookup(oid)
            if obj.type == :commit
              res.push(
                {
                  sha: obj.oid,
                  author: obj.author,
                  committer: obj.committer,
                  message: obj.message
                }
              )
            end
          end

          res
        end

        # Deprecated
        def index_tree(tree, path = "/")
          result = []
          tree.each_blob do |blob|
            b = EasyBlob.new(repository_for_indexing, blob)
            result.push(
              {
                id: "#{repository_for_indexing.head.target}_#{path}_#{blob[:name]}",
                oid: b.id,
                content: b.data,
                commit_sha: repository_for_indexing.head.target
              }
            ) if b.text?
          end

          tree.each_tree do |nested_tree|
            result.push(index_tree(repository_for_indexing.lookup(nested_tree[:oid]), "/#{nested_tree[:name]}"))
          end

          result.flatten
        end

        # Deprecated
        def index_commits_by_ref(ref)
          index_commit_info(repository_for_indexing.lookup(ref.target)).flatten
        end

        # Deprecated
        def index_commit_info(commit)
          res = []
          res.push(
            {
              sha: commit.oid,
              author: commit.author,
              committer: commit.committer,
              message: commit.message
            }
          )

          # TODO: create batch indexing
          commit.parents.each do |parent_commit|
            res.push(index_commit_info(parent_commit))
          end

          res
        end

        def repository_for_indexing(repo_path = "")
          @path_to_repo ||= repo_path
          Rugged::Repository.new(@path_to_repo)
        end

      end
    end

    class EasyBlob
      include Linguist::BlobHelper
      include EncodingHelper

      attr_accessor :id, :name, :path, :data, :commit_id

      def initialize(repo, raw_blob_hash)
        @id = raw_blob_hash[:oid]
        @path = raw_blob_hash[:path]
        @name = @path.split("/").last
        @data = encode!(repo.lookup(@id).content)
      end
    end
  end
end
