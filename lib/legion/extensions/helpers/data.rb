# frozen_string_literal: true

require 'legion/extensions/helpers/base'
require 'legion/data/helper'

module Legion
  module Extensions
    module Helpers
      module Data
        include Legion::Extensions::Helpers::Base
        include Legion::Data::Helper
      end
    end
  end
end
