require 'active_support/concern'
require 'active_model'
require 'elasticsearch/model'

module Elasticsearch
  module Git
    module Model
      extend ActiveSupport::Concern

      included do
        extend ActiveModel::Naming
        include ActiveModel::Model
        include Elasticsearch::Model

        env = if defined?(::Rails)
                ::Rails.env.to_s
              else
                "undefined"
              end

        index_name [self.name.downcase, 'index', env].join('-')

        settings \
          index: {
          analysis: {
            analyzer: {
              human_analyzer: {
                type: 'custom',
                tokenizer: 'human_tokenizer',
                filter: %w(lowercase asciifolding human_ngrams)
              },
              sha_analyzer: {
                type: 'custom',
                tokenizer: 'sha_tokenizer',
                filter: %w(lowercase asciifolding sha_ngrams)
              },
              code_analyzer: {
                type: 'custom',
                tokenizer: 'standard',
                filter: %w(lowercase asciifolding)
              }
            },
            tokenizer: {
              sha_tokenizer: {
                type: "NGram",
                min_gram: 8,
                max_gram: 40,
                token_chars: %w(letter digit)
              },
              human_tokenizer: {
                type: "NGram",
                min_gram: 1,
                max_gram: 20,
                token_chars: %w(letter digit)
              }
            },
            filter: {
              human_ngrams: {
                type: "NGram",
                min_gram: 1,
                max_gram: 20
              },
              sha_ngrams: {
                type: "NGram",
                min_gram: 8,
                max_gram: 40
              }
            }
          }
        }
      end
    end
  end
end
