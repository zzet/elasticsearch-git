module Elasticsearch
  module Git
    module Commit
      extend ActiveSupport::Concern

      included do
        include Elasticsearch::Git::Model

        #index_name [Rails.application.class.parent_name.downcase, self.name.downcase, 'commits', Rails.env.to_s].join('-')

        #mapping do
          #indexes :author, type: :string, index_options: 'offsets', search_analyzer: :search_analyzer, index_analyzer: :index_analyzer
        #end

        def attributes
          
        end
      end
    end
  end
end
