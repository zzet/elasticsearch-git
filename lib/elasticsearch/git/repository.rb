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

        # Indexing all text-like blobs in repository
        #
        # All data stored in global index
        # Repository can be selected by 'rid' field
        # If you want - this field can be used for store 'project' id
        #
        # blob {
        #   id - uniq id of blob from all repositories
        #   oid - blob id in repository
        #   content - blob content
        #   commit_sha - last actual commit sha
        # }
        #
        # For search from blobs use type 'blob'
        def index_blobs
          target_sha = repository_for_indexing.head.target
          repository_for_indexing.index.each do |blob|
            b = LiteBlob.new(repository_for_indexing, blob)
            if b.text?
              client_for_indexing.index \
                index: "#{self.class.index_name}",
                type: "blob",
                id: "#{repository_id}_#{b.path}",
                body: {
                  blob: {
                    oid: b.id,
                    rid: repository_id,
                    content: b.data,
                    commit_sha: target_sha
                  }
                }
            end
          end
        end

        # Indexing all commits in repository
        #
        # All data stored in global index
        # Repository can be filtered by 'rid' field
        # If you want - this field can be used git store 'project' id
        #
        # commit {
        #  sha - commit sha
        #  author {
        #    name - commit author name
        #    email - commit author email
        #    time - commit time
        #  }
        #  commiter {
        #    name - committer name
        #    email - committer email
        #    time - commit time
        #  }
        #  message - commit message
        # }
        #
        # For search from commits use type 'commit'
        def index_commits
          repository_for_indexing.each_id do |oid|
            obj = repository_for_indexing.lookup(oid)
            if obj.type == :commit
              client_for_indexing.index \
                index: "#{self.class.index_name}",
                type: "commit",
                id: "#{repository_id}_#{obj.oid}",
                body: {
                  commit: {
                    rid: repository_id,
                    sha: obj.oid,
                    author: obj.author,
                    committer: obj.committer,
                    message: obj.message
                  }
                }
            end
          end
        end

        # Representation of repository as indexed json
        # Attention: It can be very very very huge hash
        def as_indexed_json(options = {})
          ij = {}
          ij[:blobs] = index_blobs_array
          ij[:commits] = index_commits_array
          ij
        end

        # Indexing blob from current index
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

        # Lookup all object ids for commit objects
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

        # Repository id used for identity data from different repositories
        # Update this value if need
        def set_repository_id id
          @repository_id = id || path_to_repo
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
