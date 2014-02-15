require 'active_support/concern'
require 'active_model'
require 'elasticsearch/model'

module Elasticsearch
  module Git
    module Model
      extend ActiveSupport::Concern
      extend ActiveModel::Naming

      included do
        include ActiveModel::Model
        #include ActiveModel::AttributeMethods
        #include ActiveModel::Serialization
        include Elasticsearch::Model

        settings \
          index: {
          query: {
            default_field: :code
          },
          analysis: {
            analizer: {
              human_anayzer: {
                type: :custom,
                tokenizer: :ngram_tokenizer,
                filter: %w(lowercase asciifolding human_ngrams)
              },
              code_anayzer: {
                type: :custom,
                tokenizer: :standart,
                filter: %w(lowercase asciifolding)
              }
            }
          },
          tokenizer: {
            ngram_tokenizer: {
              type: "NGram",
              min_gram: 1,
              max_gram: 40,
              token_chars: %w(letter digit)
            }
          },
          filter: {
            human_ngrams: {
              type: "NGram",
              min_gram: 1,
              max_gram: 20
            }
          }
        }
      end
    end
  end
end
