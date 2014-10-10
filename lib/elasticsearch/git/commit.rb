module Elasticsearch
  module Git
    class Commit
      attr_reader :attributes

      def initialize(attributes={})
        @attributes = attributes
      end

      def to_hash
        @attributes
      end
    end
  end
end

