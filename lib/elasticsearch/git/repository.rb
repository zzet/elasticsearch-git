require 'active_support/concern'
require 'active_model'
require 'elasticsearch'
require 'elasticsearch/git/model'
require 'elasticsearch/git/encoder_helper'
require 'elasticsearch/git/lite_blob'
require 'rugged'

module Elasticsearch
  module Git
    module Repository
      extend ActiveSupport::Concern

      included do
        include Elasticsearch::Git::Model
        include Elasticsearch::Git::EncoderHelper

        mapping _timestamp: { enabled: true } do
          indexes :blob do
            indexes :id,          type: :string, index_options: 'offsets', search_analyzer: :human_analyzer,  index_analyzer: :human_analyzer
            indexes :rid,         type: :string, index: :not_analyzed
            indexes :oid,         type: :string, index_options: 'offsets', search_analyzer: :code_analyzer,   index_analyzer: :code_analyzer
            indexes :commit_sha,  type: :string, index_options: 'offsets', search_analyzer: :code_analyzer,   index_analyzer: :code_analyzer
            indexes :path,        type: :string, search_analyzer: :path_analyzer,   index_analyzer: :path_analyzer
            indexes :content,     type: :string, index_options: 'offsets', search_analyzer: :code_analyzer,   index_analyzer: :code_analyzer
            indexes :language,    type: :string, index: :not_analyzed
          end

          indexes :commit do
            indexes :id,          type: :string, index_options: 'offsets', search_analyzer: :human_analyzer,  index_analyzer: :human_analyzer
            indexes :rid,         type: :string, index: :not_analyzed
            indexes :sha,         type: :string, index_options: 'offsets', search_analyzer: :code_analyzer,    index_analyzer: :code_analyzer

            indexes :author do
              indexes :name,      type: :string, index_options: 'offsets', search_analyzer: :code_analyzer,    index_analyzer: :code_analyzer
              indexes :email,     type: :string, index_options: 'offsets', search_analyzer: :code_analyzer,    index_analyzer: :code_analyzer
              indexes :time,      type: :time
            end

            indexes :commiter do
              indexes :name,      type: :string, index_options: 'offsets', search_analyzer: :code_analyzer,    index_analyzer: :code_analyzer
              indexes :email,     type: :string, index_options: 'offsets', search_analyzer: :code_analyzer,    index_analyzer: :code_analyzer
              indexes :time,      type: :time
            end

            indexes :message,     type: :string, index_options: 'offsets', search_analyzer: :code_analyzer,    index_analyzer: :code_analyzer
          end
        end

        def index_blobs(from_rev: nil, to_rev: repository_for_indexing.last_commit.oid)
          from, to = parse_revs(from_rev, to_rev)

          diff = repository_for_indexing.diff(from, to)

          diff.deltas.reverse.each_with_index do |delta, step|
            if delta.status == :deleted
              next if delta.old_file[:mode].to_s(8) == "160000"
              b = LiteBlob.new(repository_for_indexing, delta.old_file)
              delete_from_index_blob(b)
            else
              next if delta.new_file[:mode].to_s(8) == "160000"
              b = LiteBlob.new(repository_for_indexing, delta.new_file)
              index_blob(b, to)
            end
          end
        end

        def index_blob(blob, target_sha)
          if can_index_blob?(blob)
            begin
              client_for_indexing.index \
                index: "#{self.class.index_name}",
                type: "repository",
                id: "#{repository_id}_#{blob.path}",
                body: {
                  blob: {
                    type: "blob",
                    oid: blob.id,
                    rid: repository_id,
                    content: blob.data,
                    commit_sha: target_sha,
                    path: blob.path,
                    language: blob.language ? blob.language.name : "Text"
                  }
                }
            rescue Exception => ex
              logger.warn "Can't index #{repository_id}_#{blob.path}. Reason: #{ex.message}"
            end
          end
        end

        # Index text-like files which size less 1.mb
        def can_index_blob?(blob)
          blob.text? && (blob.size && blob.size.to_i < 1048576)
        end

        def delete_from_index_blob(blob)
          if blob.text?
            begin
              client_for_indexing.delete \
                index: "#{self.class.index_name}",
                type: "repository",
                id: "#{repository_id}_#{blob.path}"
            rescue Elasticsearch::Transport::Transport::Errors::NotFound
              return true
            rescue Exception => ex
              logger.warn "Error with remove file from index #{repository_id}_#{blob.path}. Reason: #{ex.message}"
            end
          end
        end

        def index_commits(from_rev: nil, to_rev: repository_for_indexing.last_commit.oid)
          from, to = parse_revs(from_rev, to_rev)
          range = [from, to].reject(&:nil?).join('..')
          out, err, status = Open3.capture3("git log #{range} --format=\"%H\"", chdir: repository_for_indexing.path)

          if status.success? && err.blank?
            #TODO use rugged walker!!!
            commit_oids = out.split("\n")

            commit_oids.each_with_index do |commit, step|
              index_commit(repository_for_indexing.lookup(commit))
            end
            return commit_oids.count
          end

          0
        end

        def index_commit(commit)
          begin
            client_for_indexing.index \
              index: "#{self.class.index_name}",
              type: "repository",
              id: "#{repository_id}_#{commit.oid}",
              body: {
                commit: {
                  type: "commit",
                  rid: repository_id,
                  sha: commit.oid,
                  author: commit.author,
                  committer: commit.committer,
                  message: encode!(commit.message)
                }
              }
          rescue Exception => ex
            logger.warn "Can't index #{repository_id}_#{commit.oid}. Reason: #{ex.message}"
          end
        end

        def parse_revs(from_rev, to_rev)
          from = if index_new_branch?(from_rev)
                   if to_rev == repository_for_indexing.last_commit.oid
                     nil
                   else
                     merge_base(to_rev)
                   end
                 else
                   from_rev
                 end

          return from, to_rev
        end

        def index_new_branch?(from)
          from == '0000000000000000000000000000000000000000'
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

          target_sha = repository_for_indexing.head.target.oid

          if repository_for_indexing.bare?
            tree = repository_for_indexing.lookup(target_sha).tree
            result.push(recurse_blobs_index_hash(tree))
          else
            repository_for_indexing.index.each do |blob|
              b = LiteBlob.new(repository_for_indexing, blob)
              result.push(
                {
                  type: 'blob',
                  id: "#{target_sha}_#{b.path}",
                  rid: repository_id,
                  oid: b.id,
                  content: b.data,
                  commit_sha: target_sha
                }
              ) if b.text?
            end
          end

          result
        end

        def recurse_blobs_index_hash(tree, path = "")
          result = []

          tree.each_blob do |blob|
            blob[:path] = path + blob[:name]
            b = LiteBlob.new(repository_for_indexing, blob)
            result.push(
              {
                type: 'blob',
                id: "#{repository_for_indexing.head.target.oid}_#{path}#{blob[:name]}",
                rid: repository_id,
                oid: b.id,
                content: b.data,
                commit_sha: repository_for_indexing.head.target.oid
              }
            ) if b.text?
          end

          tree.each_tree do |nested_tree|
            result.push(recurse_blobs_index_hash(repository_for_indexing.lookup(nested_tree[:oid]), "#{nested_tree[:name]}/"))
          end

          result.flatten
        end

        # Lookup all object ids for commit objects
        def index_commits_array
          res = []

          repository_for_indexing.each_id do |oid|
            obj = repository_for_indexing.lookup(oid)
            if obj.type == :commit
              res.push(
                {
                  type: 'commit',
                  sha: obj.oid,
                  author: obj.author,
                  committer: obj.committer,
                  message: encode!(obj.message)
                }
              )
            end
          end

          res
        end

        def search(query, type: :all, page: 1, per: 20, options: {})
          options[:repository_id] = repository_id if options[:repository_id].nil?
          self.class.search(query, type: type, page: page, per: per, options: options)
        end

        # Repository id used for identity data from different repositories
        # Update this value if need
        def set_repository_id id = nil
          @repository_id = id || path_to_repo
        end

        # For Overwrite
        def repository_id
          @repository_id
        end

        # For Overwrite
        def self.repositories_count
          10
        end

        unless defined?(path_to_repo)
          def path_to_repo
            if @path_to_repo.blank?
              raise NotImplementedError, 'Please, define "path_to_repo" method, or set "path_to_repo" via "repository_for_indexing" method'
            else
              @path_to_repo
            end
          end
        end

        def repository_for_indexing(repo_path = "")
          return @rugged_repo_indexer if defined? @rugged_repo_indexer

          @path_to_repo ||= repo_path
          set_repository_id
          @rugged_repo_indexer = Rugged::Repository.new(@path_to_repo)
        end

        def client_for_indexing
          @client_for_indexing ||= Elasticsearch::Client.new log: true
        end

        def self.search(query, type: :all, page: 1, per: 20, options: {})
          results = { blobs: [], commits: []}
          case type.to_sym
          when :all
            results[:blobs] = search_blob(query, page: page, per: per, options: options)
            results[:commits] = search_commit(query, page: page, per: per, options: options)
          when :blob
            results[:blobs] = search_blob(query, page: page, per: per, options: options)
          when :commit
            results[:commits] = search_commit(query, page: page, per: per, options: options)
          end

          results
        end

        def logger
          @logger ||= Logger.new(STDOUT)
        end

        private

        def merge_base(to_rev)
          head_sha = repository_for_indexing.last_commit.oid
          repository_for_indexing.merge_base(to_rev, head_sha)
        end
      end

      module ClassMethods
        def search_commit(query, page: 1, per: 20, options: {})
          page ||= 1

          fields = %w(message^10 sha^5 author.name^2 author.email^2 committer.name committer.email).map {|i| "commit.#{i}"}

          query_hash = {
            query: {
              filtered: {
                query: {
                  multi_match: {
                    fields: fields,
                    query: "#{query}",
                    operator: :or
                  }
                },
              },
            },
            facets: {
              commitRepositoryFaset: {
                terms: {
                  field: "commit.rid",
                  all_terms: true,
                  size: repositories_count
                }
              }
            },
            size: per,
            from: per * (page - 1)
          }

          if query.blank?
            query_hash[:query][:filtered][:query] = { match_all: {}}
            query_hash[:track_scores] = true
          end

          if options[:repository_id]
            query_hash[:query][:filtered][:filter] ||= { and: [] }
            query_hash[:query][:filtered][:filter][:and] << {
              terms: {
                "commit.rid" => [options[:repository_id]].flatten
              }
            }
          end

          if options[:highlight]
            es_fields = fields.map { |field| field.split('^').first }.inject({}) do |memo, field|
              memo[field.to_sym] = {}
              memo
            end

            query_hash[:highlight] = {
                pre_tags: ["gitlabelasticsearch→"],
                post_tags: ["←gitlabelasticsearch"],
                fields: es_fields
            }
          end

          options[:order] = :default if options[:order].blank?
          order = case options[:order].to_sym
                  when :recently_indexed
                    { _timestamp: { order: :desc, mode: :min } }
                  when :last_indexed
                    { _timestamp: { order: :asc,  mode: :min } }
                  else
                    {}
                  end

          query_hash[:sort] = order.blank? ? [:_score] : [order, :_score]

          res = self.__elasticsearch__.search(query_hash)
          {
            results: res.results,
            total_count: res.size,
            repositories: res.response["facets"]["commitRepositoryFaset"]["terms"]
          }
        end

        def search_blob(query, type: :all, page: 1, per: 20, options: {})
          page ||= 1

          query_hash = {
            query: {
              filtered: {
                query: {
                  match: {
                    'blob.content' => {
                      query: "#{query}",
                      operator: :and
                    }
                  }
                }
              }
            },
            facets: {
              languageFacet: {
                terms: {
                  field: :language,
                  all_terms: true,
                  size: 20
                }
              },
              blobRepositoryFaset: {
                terms: {
                  field: :rid,
                  all_terms: true,
                  size: repositories_count
                }
              }
            },
            size: per,
            from: per * (page - 1)
          }

          if options[:repository_id]
            query_hash[:query][:filtered][:filter] ||= { and: [] }
            query_hash[:query][:filtered][:filter][:and] << {
              terms: {
                "blob.rid" => [options[:repository_id]].flatten
              }
            }
          end

          if options[:language]
            query_hash[:query][:filtered][:filter] ||= { and: [] }
            query_hash[:query][:filtered][:filter][:and] << {
              terms: {
                "blob.language" => [options[:language]].flatten
              }
            }
          end

          options[:order] = :default if options[:order].blank?
          order = case options[:order].to_sym
                  when :recently_indexed
                    { _timestamp: { order: :desc, mode: :min } }
                  when :last_indexed
                    { _timestamp: { order: :asc, mode: :min } }
                  else
                    {}
                  end

          query_hash[:sort] = order.blank? ? [:_score] : [order, :_score]

          if options[:highlight]
            query_hash[:highlight] = {
              pre_tags: ["gitlabelasticsearch→"],
              post_tags: ["←gitlabelasticsearch"],
              fields: {
                "blob.content" => {},
                "type" => "fvh",
                "boundary_chars" => "\n"
              }
            }
          end

          res = self.__elasticsearch__.search(query_hash)

          {
            results: res.results,
            total_count: res.size,
            languages: res.response["facets"]["languageFacet"]["terms"],
            repositories: res.response["facets"]["blobRepositoryFaset"]["terms"]
          }
        end

        def search_file_names(query, page: 1, per: 20, options: {})
          query_hash = {
              fields: ['blob.path'],
              query: {
                  fuzzy: {
                      "repository.blob.path" => { value: query }
                  },
              },
              filter: {
                  term: {
                      "repository.blob.rid" => [options[:repository_id]].flatten
                  }
              },
              size: per,
              from: per * (page - 1)
          }

          self.__elasticsearch__.search(query_hash)
        end
      end
    end
  end
end
