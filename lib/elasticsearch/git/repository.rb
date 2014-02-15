require 'active_support/concern'
require 'active_model'
require 'elasticsearch'
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
          indexes :blobs do
            indexes :id,          type: :string, index_options: 'offsets', search_analyzer: :human_analyzer,  index_analyzer: :human_analyzer
            indexes :oid,         type: :string, index_options: 'offsets', search_analyzer: :sha_analyzer,    index_analyzer: :sha_analyzer
            indexes :commit_sha,  type: :string, index_options: 'offsets', search_analyzer: :sha_analyzer,    index_analyzer: :sha_analyzer
            indexes :content,     type: :string, index_options: 'offsets', search_analyzer: :code_analyzer,   index_analyzer: :human_analyzer
          end
          indexes :commits do
            indexes :id,          type: :string, index_options: 'offsets', search_analyzer: :human_analyzer,  index_analyzer: :human_analyzer
            indexes :sha,         type: :string, index_options: 'offsets', search_analyzer: :sha_analyzer,    index_analyzer: :sha_analyzer
            indexes :author do
              indexes :name,      type: :string, index_options: 'offsets', search_analyzer: :code_analyzer,    index_analyzer: :human_analyzer
              indexes :email,     type: :string, index_options: 'offsets', search_analyzer: :code_analyzer,    index_analyzer: :human_analyzer
              indexes :time,      type: :date
            end
            indexes :commiter do
              indexes :name,      type: :string, index_options: 'offsets', search_analyzer: :code_analyzer,    index_analyzer: :human_analyzer
              indexes :email,     type: :string, index_options: 'offsets', search_analyzer: :code_analyzer,    index_analyzer: :human_analyzer
              indexes :time,      type: :date
            end
            indexes :message,    type: :string, index_options: 'offsets', search_analyzer: :code_analyzer,     index_analyzer: :human_analyzer
          end
        end

        def create_indexes
          client_for_indexing.indices.create \
            index: self.class.index_name,
            body: {
              settings: self.class.settings.to_hash,
              mappings: self.class.mappings.to_hash
            }
        end

        def index_blobs
          target_sha = repository_for_indexing.head.target
          repository_for_indexing.index.each do |blob|
            b = LiteBlob.new(repository_for_indexing, blob)
            if b.text?
              client_for_indexing.index \
                index: "#{self.class.index_name}",
                type: "blob",
                id: "#{target_sha}_#{b.path}",
                body: {
                  blob: {
                    oid: b.id,
                    content: b.data,
                    commit_sha: target_sha
                  }
                }
            end
          end
        end

        def index_commits
          repository_for_indexing.each_id do |oid|
            obj = repository_for_indexing.lookup(oid)
            if obj.type == :commit
              client_for_indexing.index \
                index: "#{self.class.index_name}",
                type: "commit",
                id: obj.oid,
                body: {
                  commit: {
                    sha: obj.oid,
                    author: obj.author,
                    committer: obj.committer,
                    message: obj.message
                  }
                }
            end
          end
        end

        def as_indexed_json(options = {})
          ij = {}
          ij[:blobs] = index_blobs_array
          ij[:commits] = index_commits_array
          #ij[:blobs] = index_tree(repository_for_indexing.lookup(repository_for_indexing.head.target).tree)
          #ij[:commits] = index_commits_by_ref(repository_for_indexing.head)
          ij
        end

        def index_blobs_array
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

        def index_commits_array
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

        def repository_for_indexing(repo_path = "")
          @path_to_repo ||= repo_path
          Rugged::Repository.new(@path_to_repo)
        end

        def client_for_indexing
          @client_for_indexing ||= Elasticsearch::Client.new log: true
        end

      end
    end

    class LiteBlob
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
