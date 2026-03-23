# frozen_string_literal: true

module Legion
  module CLI
    class Chat
      module Tools
        class EntityExtract < RubyLLM::Tool
          description 'Extract named entities (people, services, repos, concepts) from text using Apollo'

          param :text,
                type:     :string,
                desc:     'Text to extract entities from',
                required: true

          param :entity_types,
                type:     :string,
                desc:     'Comma-separated entity types to extract (default: person,service,repository,concept)',
                required: false

          param :min_confidence,
                type:     :number,
                desc:     'Minimum confidence threshold 0.0-1.0 (default: 0.7)',
                required: false

          def execute(text:, entity_types: nil, min_confidence: 0.7)
            return 'Apollo entity extractor not available.' unless extractor_available?

            types = parse_types(entity_types)
            result = run_extraction(text, types, min_confidence.to_f)
            format_result(result)
          end

          private

          def extractor_available?
            defined?(Legion::Extensions::Apollo::Runners::EntityExtractor)
          end

          def parse_types(types_str)
            return nil if types_str.nil? || types_str.strip.empty?

            types_str.split(',').map(&:strip)
          end

          def run_extraction(text, types, min_confidence)
            extractor = Object.new.extend(Legion::Extensions::Apollo::Runners::EntityExtractor)
            extractor.extract_entities(
              text:           text,
              entity_types:   types,
              min_confidence: min_confidence
            )
          end

          def format_result(result)
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
