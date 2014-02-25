require 'linguist'
require 'elasticsearch/git/encoder_helper'

module Elasticsearch
  module Git
    class LiteBlob
      include Linguist::BlobHelper
      include Elasticsearch::Git::EncoderHelper

      attr_accessor :id, :name, :path, :data, :commit_id

      def initialize(repo, raw_blob_hash)
        @id = raw_blob_hash[:oid]
        @path = encode!(raw_blob_hash[:path])
        @name = @path.split('/').last
        @data = encode!(repo.lookup(@id).content)
      end
    end
  end
end
