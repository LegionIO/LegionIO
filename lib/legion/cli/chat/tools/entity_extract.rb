# frozen_string_literal: true

module Legion
  module CLI
    class Chat
      module Tools
        class EntityExtract < Legion::Tools::Base
          tool_name 'legion.entity_extract'
          description 'Extract named entities (people, services, repos, concepts) from text using Apollo'
          input_schema({
                         type:       'object',
                         properties: {
                           text:           { type: 'string' },
                           entity_types:   { type: 'string' },
                           min_confidence: { type: 'number' }
                         },
                         required:   ['text']
                       })

          def self.call(text:, entity_types: nil, min_confidence: 0.7)
            return 'Apollo entity extractor not available.' unless extractor_available?

            types = parse_types(entity_types)
            result = run_extraction(text, types, min_confidence.to_f)
            format_result(result)
          end

          def self.extractor_available?
            defined?(Legion::Extensions::Apollo::Runners::EntityExtractor)
          end

          def self.parse_types(types_str)
            return nil if types_str.nil? || types_str.strip.empty?

            types_str.split(',').map(&:strip)
          end

          def self.run_extraction(text, types, min_confidence)
            extractor = Object.new.extend(Legion::Extensions::Apollo::Runners::EntityExtractor)
            extractor.extract_entities(
              text:           text,
              entity_types:   types,
              min_confidence: min_confidence
            )
          end

          def self.format_result(result)
            return format('Entity extraction failed: %<err>s', err: result[:error] || 'unknown error') unless result[:success]

            entities = result[:entities]
            return 'No entities found in the provided text.' if entities.empty?

            lines = [format("Extracted %<n>d entities:\n", n: entities.size)]

            grouped = entities.group_by { |e| e[:type] }
            grouped.each do |type, items|
              lines << format('  [%<type>s]', type: type)
              items.sort_by { |e| -(e[:confidence] || 0) }.each do |entity|
                lines << format('    %<name>s (confidence: %<conf>.0f%%)',
                                name: entity[:name], conf: (entity[:confidence] || 0) * 100)
              end
            end

            lines.join("\n")
          end
        end
      end
    end
  end
end
