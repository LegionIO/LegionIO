# frozen_string_literal: true

require_relative 'base'

module Legion
  module Extensions
    module Builder
      module Absorbers
        include Legion::Extensions::Builder::Base

        def build_absorbers
          @absorbers = {}
          absorber_files = find_files('absorbers')
          return if absorber_files.empty?

          require_files(absorber_files)

          absorber_files.each do |file|
            snake_name  = file.split('/').last.sub('.rb', '')
            class_name  = snake_name.split('_').collect(&:capitalize).join
            absorber_class = "#{lex_class}::Absorbers::#{class_name}"

            next unless Kernel.const_defined?(absorber_class)

            klass = Kernel.const_get(absorber_class)
            next unless klass < Legion::Extensions::Absorbers::Base

            @absorbers[snake_name.to_sym] = {
              extension:       lex_name,
              extension_class: lex_class,
              absorber_name:   snake_name,
              absorber_class:  absorber_class,
              absorber_module: klass,
              patterns:        klass.patterns,
              description:     klass.description
            }

            Legion::Extensions::Absorbers::PatternMatcher.register(klass)

            next unless defined?(Legion::API) && Legion::API.respond_to?(:router)

            absorber_methods = klass.public_instance_methods(false).reject { |m| m.to_s.start_with?('_') }
            absorber_methods = [:absorb] if absorber_methods.empty?
            absorber_methods.each do |method_name|
              Legion::API.router.register_extension_route(
                lex_name:       lex_name,
                amqp_prefix:    respond_to?(:amqp_prefix) ? amqp_prefix : "lex.#{lex_name}",
                component_type: 'absorbers',
                component_name: snake_name,
                method_name:    method_name.to_s,
                runner_class:   klass,
                definition:     klass.respond_to?(:definition_for) ? klass.definition_for(method_name) : nil
              )
            end
          end
        rescue StandardError => e
          Legion::Logging.error("Failed to build absorbers: #{e.message}") if defined?(Legion::Logging)
        end

        def absorbers
          @absorbers || {}
        end
      end
    end
  end
end
