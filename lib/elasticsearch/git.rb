require "elasticsearch/git/version"
require "elasticsearch/git/model"
require "elasticsearch/git/commit"

module Elasticsearch
  module Git
    class Test
      include Elasticsearch::Git::Model
    end
  end
end

