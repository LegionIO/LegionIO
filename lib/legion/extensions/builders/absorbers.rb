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
            class_name = file.split('/').last.sub('.rb', '').split('_').collect(&:capitalize).join
            absorber_class = "#{lex_class}::Absorbers::#{class_name}"

            next unless Kernel.const_defined?(absorber_class)

            klass = Kernel.const_get(absorber_class)
            next unless klass < Legion::Extensions::Absorbers::Base

            @absorbers[class_name.to_sym] = {
              extension:       lex_name,
              extension_class: lex_class,
              absorber_name:   class_name,
              absorber_class:  absorber_class,
              absorber_module: klass,
              patterns:        klass.patterns,
              description:     klass.description
            }

            Legion::Extensions::Absorbers::PatternMatcher.register(klass)
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
