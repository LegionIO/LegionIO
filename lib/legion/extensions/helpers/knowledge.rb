# frozen_string_literal: true

module Legion
  module Extensions
    module Helpers
      module Knowledge
        def ingest_knowledge(content_or_path, type: :auto, tags: [], **opts)
          unless defined?(Legion::Apollo) && Legion::Apollo.started?
            Legion::Logging.debug 'ingest_knowledge called but Apollo is not available' if defined?(Legion::Logging)
            return { success: false, error: :apollo_not_available }
          end

          text, metadata = extract_if_needed(content_or_path, type: type)
          return { success: false, error: :extraction_failed, detail: metadata } unless text

          extraction_tags = metadata_to_tags(metadata) if metadata
          all_tags = Array(tags) + Array(extraction_tags)

          Legion::Apollo.ingest(
            content:        text,
            tags:           all_tags,
            source_channel: opts[:source_channel] || derive_lex_name,
            **opts.except(:source_channel)
          )
        end

        def query_knowledge(text:, limit: 5, **opts)
          unless defined?(Legion::Apollo) && Legion::Apollo.started?
            Legion::Logging.debug 'query_knowledge called but Apollo is not available' if defined?(Legion::Logging)
            return { success: false, error: :apollo_not_available }
          end

          Legion::Apollo.query(text: text, limit: limit, **opts)
        end

        private

        def extract_if_needed(content_or_path, type:)
          if content_or_path.is_a?(String) && File.exist?(content_or_path)
            return extract_file(content_or_path, type: type)
          end

          return extract_file(content_or_path, type: type) if content_or_path.respond_to?(:read)

          [content_or_path.to_s, nil]
        end

        def extract_file(source, type:)
          return [source.to_s, nil] unless defined?(Legion::Data::Extract)

          result = Legion::Data::Extract.extract(source, type: type)
          if result[:text]
            [result[:text], result[:metadata]]
          else
            [nil, result]
          end
        end

        def metadata_to_tags(metadata)
          tags = []
          tags << metadata[:type].to_s if metadata[:type]
          tags << "pages:#{metadata[:pages]}" if metadata[:pages]
          tags
        end

        def derive_lex_name
          self.class.name&.split('::')&.dig(2)&.downcase || 'unknown'
        end
      end
    end
  end
end
