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
            indexes :path,        type: :string, index_options: 'offsets', search_analyzer: :human_analyzer,  index_analyzer: :human_analyzer
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
              indexes :time,      type: :date
            end

            indexes :commiter do
              indexes :name,      type: :string, index_options: 'offsets', search_analyzer: :code_analyzer,    index_analyzer: :code_analyzer
              indexes :email,     type: :string, index_options: 'offsets', search_analyzer: :code_analyzer,    index_analyzer: :code_analyzer
              indexes :time,      type: :date
            end

            indexes :message,     type: :string, index_options: 'offsets', search_analyzer: :code_analyzer,    index_analyzer: :code_analyzer
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
        def index_blobs(from_rev: nil, to_rev: nil)

          if to_rev.present?
            begin
              if to_rev != "0000000000000000000000000000000000000000"
                raise unless repository_for_indexing.lookup(to_rev).type == :commit
              end
            rescue
              raise ArgumentError, "'to_rev': '#{to_rev}' is a incorrect commit sha."
            end
          else
            to_rev = repository_for_indexing.head.target
          end

          target_sha = to_rev

          if from_rev.present?
            begin
              if from_rev != "0000000000000000000000000000000000000000"
                raise unless repository_for_indexing.lookup(from_rev).type == :commit
              end
            rescue
              raise ArgumentError, "'from_rev': '#{from_rev}' is a incorrect commit sha."
            end

            diff = repository_for_indexing.diff(from_rev, to_rev)

            diff.deltas.reverse.each_with_index do |delta, step|
              if delta.status == :deleted
                b = LiteBlob.new(repository_for_indexing, delta.old_file)
                delete_from_index_blob(b)
              else
                b = LiteBlob.new(repository_for_indexing, delta.new_file)
                index_blob(b, target_sha)
              end

              # Run GC every 100 blobs
              ObjectSpace.garbage_collect if step % 100 == 0
            end
          else
            if repository_for_indexing.bare?
              recurse_blobs_index(repository_for_indexing.lookup(target_sha).tree, target_sha)
            else
              repository_for_indexing.index.each_with_index do |blob, step|
                b = LiteBlob.new(repository_for_indexing, blob)
                index_blob(b, target_sha)

                # Run GC every 100 blobs
                ObjectSpace.garbage_collect if step % 100 == 0
              end
            end
          end
        end

        # Indexing bare repository via walking through tree
        def recurse_blobs_index(tree, target_sha, path = "")
          tree.each_blob do |blob|
            blob[:path] = path + blob[:name]
            b = LiteBlob.new(repository_for_indexing, blob)
            index_blob(b, target_sha)
          end

          # Run GC every recurse step
          ObjectSpace.garbage_collect

          tree.each_tree do |nested_tree|
            recurse_blobs_index(repository_for_indexing.lookup(nested_tree[:oid]), target_sha, "#{path}#{nested_tree[:name]}/")
          end
        end

        def index_blob(blob, target_sha)
          if can_index_blob?(blob)
            tries = 0
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
              # Retry 10 times send request
              if tries < 10
                tries += 1
                sleep tries * 10 * rand(10)
                retry
              else
                logger.warn "Can't index #{repository_id}_#{blob.path}. Reason: #{ex.message}"
              end
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
        def index_commits(from_rev: nil, to_rev: nil)
          to_rev = repository_for_indexing.head.target unless to_rev.present?

          if to_rev != "0000000000000000000000000000000000000000"
            # If to_rev correct
            begin
              raise unless repository_for_indexing.lookup(to_rev).type == :commit
            rescue
              raise ArgumentError, "'to_rev': '#{to_rev}' is a incorrect commit sha."
            end

            begin
              if from_rev.present? && from_rev != "0000000000000000000000000000000000000000"
                raise unless repository_for_indexing.lookup(from_rev).type == :commit
              end
            rescue
              raise ArgumentError, "'from_rev': '#{from_rev}' is a incorrect commit sha."
            end

            # If pushed new branch no need reindex all repository
            # Find merge_base and reindex diff
            if from_rev == "0000000000000000000000000000000000000000" && to_rev != repository_for_indexing.head.target
              from_rev = repository_for_indexing.merge_base(to_rev, repository_for_indexing.head.target)
            end

            out, err, status = Open3.capture3("git log #{from_rev}...#{to_rev} --format=\"%H\"", chdir: repository_for_indexing.path)

            if status.success? && err.blank?
              commit_oids = out.split("\n")
              #commits = commit_oids.map {|coid| repository_for_indexing.lookup(coid) }

              # walker crashed with seg fault
              #
              #walker = Rugged::Walker.new(repository_for_indexing)
              #walker.push(to_rev)

              #if from_rev.present? && from_rev != "0000000000000000000000000000000000000000"
                #walker.hide(from_rev)
              #end

              #commits = walker.map { |c| c.oid }
              #walker.reset

              commit_oids.each_with_index do |commit, step|
                index_commit(repository_for_indexing.lookup(commit))
                ObjectSpace.garbage_collect if step % 100 == 0
              end
            end
          end
        end

        def index_commit(commit)
          tries = 0
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
            # Retry 10 times send request
            if tries < 10
              tries += 1
              sleep tries * 10 * rand(10)
              retry
            else
              logger.warn "Can't index #{repository_id}_#{commit.oid}. Reason: #{ex.message}"
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
                id: "#{repository_for_indexing.head.target}_#{path}#{blob[:name]}",
                rid: repository_id,
                oid: b.id,
                content: b.data,
                commit_sha: repository_for_indexing.head.target
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
            total_count: res.total_count,
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
              pre_tags: [""],
              post_tags: [""],
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
            total_count: res.total_count,
            languages: res.response["facets"]["languageFacet"]["terms"],
            repositories: res.response["facets"]["blobRepositoryFaset"]["terms"]
          }
        end
      end
    end
  end
end
