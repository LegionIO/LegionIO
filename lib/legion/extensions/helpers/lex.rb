# frozen_string_literal: true

module Legion
  module Extensions
    module Helpers
      module Lex
        include Legion::Extensions::Helpers::Core
        include Legion::Extensions::Helpers::Logger

        def function_example(function, example)
          function_set(function, :example, example)
        end

        def function_options(function, options)
          function_set(function, :options, options)
        end

        def function_desc(function, desc)
          function_set(function, :desc, desc)
        end

        def function_set(function, key, value)
          unless respond_to? function
            log.debug "function_#{key} called but function doesn't exist, f: #{function}"
            return nil
          end
          settings[:functions] = {} if settings[:functions].nil?
          settings[:functions][function] = {} if settings[:functions][function].nil?
          settings[:functions][function][key] = value
        end

        def runner_desc(desc)
          settings[:runners] = {} if settings[:runners].nil?
          settings[:runners][actor_name.to_sym] = {} if settings[:runners][actor_name.to_sym].nil?
          settings[:runners][actor_name.to_sym][:desc] = desc
        end

        def self.included(base)
          base.send :extend, Legion::Extensions::Helpers::Core if base.instance_of?(Class)
          base.send :extend, Legion::Extensions::Helpers::Logger if base.instance_of?(Class)
          base.extend base if base.instance_of?(Module)
        end

        def default_settings
          { logger: { level: 'info' }, workers: 1, runners: {}, functions: {} }
        end
      end
    end
  end
end
