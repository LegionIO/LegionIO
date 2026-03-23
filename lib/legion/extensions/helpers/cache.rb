# frozen_string_literal: true

require 'legion/extensions/helpers/base'
require 'legion/cache/helper'

module Legion
  module Extensions
    module Helpers
      module Cache
        include Legion::Extensions::Helpers::Base
        include Legion::Cache::Helper
      end
    end
  end
end
