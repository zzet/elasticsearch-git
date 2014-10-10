require 'elasticsearch/git/settings'
require 'elasticsearch/persistence'
require 'rugged'
require "elasticsearch/git/encoder_helper"

module Elasticsearch
  module Git
    class CommitRepository
      include Elasticsearch::Persistence::Repository
      include Elasticsearch::Git::EncoderHelper

      def initialize(options={})
        index  options[:index] || 'commit_index_development'
        @repo = Rugged::Repository.new(options[:repo])
        @id = options[:id]
        client Elasticsearch::Client.new url: options[:url], log: options[:log]
      end

      klass Commit

      settings SETTINGS do
        mappings _timestamp: { enabled: true } do
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
      end

      def index_range
        range = ''
        out, err, status = Open3.capture3("git log #{range} --format=\"%H\"", chdir: @repo.path)

        if status.success? && err.empty?
          commit_oids = out.split("\n")
          commit_oids.each_with_index do |oid, step|
            commit = @repo.lookup(oid)

            commit = Commit.new({
              id: "#{@id}_#{commit.oid}",
              rid: @id,
              sha: commit.oid,
              author: commit.author,
              committer: commit.committer,
              message: encode!(commit.message)
            })
            save(commit)
          end
          return commit_oids.count
        end
        0
      end
    end
  end
end

