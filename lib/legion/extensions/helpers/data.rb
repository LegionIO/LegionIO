# frozen_string_literal: true

require 'legion/extensions/helpers/base'

module Legion
  module Extensions
    module Helpers
      module Data
        include Legion::Extensions::Helpers::Base

        def data_path
          @data_path ||= "#{full_path}/data"
        end

        def data_class
          @data_class ||= lex_class::Data
        end

        def models_class
          @models_class ||= data_class::Model
        end
      end
    end
  end
end
