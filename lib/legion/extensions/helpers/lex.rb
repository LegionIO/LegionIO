# frozen_string_literal: true

require 'legion/json/helper'
require_relative 'core'
require_relative 'logger'
require_relative 'secret'
require_relative 'cache'
require_relative 'transport'
require_relative 'task'

begin
  require_relative 'data'
rescue LoadError
  nil
end

module Legion
  module Extensions
    module Helpers
      module Lex
        include Legion::Extensions::Helpers::Core
        include Legion::Extensions::Helpers::Logger
        include Legion::JSON::Helper
        include Legion::Extensions::Helpers::Secret
        include Legion::Extensions::Helpers::Cache
        include Legion::Extensions::Helpers::Transport
        include Legion::Extensions::Helpers::Task
        include Legion::Extensions::Helpers::Data if defined?(Legion::Extensions::Helpers::Data)

        def runner_desc(desc)
          settings[:runners] = {} if settings[:runners].nil?
          settings[:runners][actor_name.to_sym] = {} if settings[:runners][actor_name.to_sym].nil?
          settings[:runners][actor_name.to_sym][:desc] = desc
        end

        def self.included(base)
          if base.instance_of?(Class)
            base.send :extend, Legion::Extensions::Helpers::Core
            base.send :extend, Legion::Extensions::Helpers::Logger
            base.send :extend, Legion::Extensions::Helpers::Cache
            base.send :extend, Legion::Extensions::Helpers::Transport
          end
          base.extend base if base.instance_of?(Module)
        end

        def default_settings
          { logger: { level: 'info' }, workers: 1, runners: {}, functions: {} }
        end
      end
    end
  end
end
