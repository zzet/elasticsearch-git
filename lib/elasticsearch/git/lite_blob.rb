require 'linguist'
require 'elasticsearch/git/encoder_helper'

module Elasticsearch
  module Git
    class LiteBlob
      include Linguist::BlobHelper
      include Elasticsearch::Git::EncoderHelper

      attr_accessor :id, :name, :path, :data, :size, :mode, :commit_id

      def initialize(repo, raw_blob_hash)
        @id   = raw_blob_hash[:oid]

        blob  = repo.lookup(@id)

        @mode = '%06o' % raw_blob_hash[:filemode]
        @size = blob.size
        @path = encode!(raw_blob_hash[:path])
        @name = @path.split('/').last
        @data = encode!(blob.content)
      end
    end
  end
end
