require 'rugged'

module Elasticsearch
  module Git
    class Repository

      attr_reader :commit

      def initialize(repo, project_id)
        @repo = Rugged::Repository.new(repo)
        @project_id = project_id
      end

    end
  end
end

