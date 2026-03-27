# frozen_string_literal: true

module Legion
  module Extensions
    module Absorbers
      class Base
        attr_accessor :job_id, :runners

        class << self
          def pattern(type, value, priority: 100)
            @patterns ||= []
            @patterns << { type: type, value: value, priority: priority }
          end

          def patterns
            @patterns || []
          end

          def description(text = nil)
            text ? @description = text : @description
          end
        end

        def handle(url: nil, content: nil, metadata: {}, context: {})
          raise NotImplementedError, "#{self.class.name} must implement #handle"
        end

        def absorb_to_knowledge(content:, tags: [], scope: :global, **opts)
          unless defined?(Legion::Extensions::Knowledge::Helpers::Chunker)
            Legion::Logging.warn('absorb_to_knowledge: lex-knowledge not available, falling back to absorb_raw') if defined?(Legion::Logging)
            return absorb_raw(content: content, tags: tags, scope: scope, **opts)
          end

          sections = [{ heading:      opts.delete(:heading) || 'absorbed',
                        content:      content,
                        section_path: opts.delete(:section_path) || 'absorbed',
                        source_file:  opts.delete(:source_file) || 'absorber' }]
          chunks = Legion::Extensions::Knowledge::Helpers::Chunker.chunk(sections: sections)
          embeddings = if defined?(Legion::LLM) && Legion::LLM.respond_to?(:embed_batch)
                         begin
                           Legion::LLM.embed_batch(chunks.map { |c| c[:content] })
                         rescue StandardError
                           []
                         end
                       else
                         []
                       end

          chunks.each_with_index do |chunk, idx|
            vector = embeddings.is_a?(Array) ? embeddings.dig(idx, :vector) : nil
            payload = {
              content:      chunk[:content],
              content_type: opts[:content_type] || 'absorbed_chunk',
              content_hash: chunk[:content_hash],
              tags:         (Array(tags) + [chunk[:heading], 'absorbed']).compact.uniq,
              metadata:     { source_file: chunk[:source_file], heading: chunk[:heading],
                          section_path: chunk[:section_path], chunk_index: chunk[:chunk_index],
                          token_count: chunk[:token_count] }.merge(opts.fetch(:metadata, {}))
            }
            payload[:embedding] = vector if vector
            Legion::Apollo.ingest(content: payload[:content], tags: payload[:tags],
                                  scope: scope, **payload.except(:content, :tags))
          end
        end

        def absorb_raw(content:, tags: [], scope: :global, **)
          if defined?(Legion::Apollo)
            Legion::Apollo.ingest(content: content, tags: Array(tags), scope: scope, **)
          elsif defined?(Legion::Logging)
            Legion::Logging.warn('absorb_raw: Apollo not available')
          end
        end

        def translate(source, type: :auto)
          raise 'legion-data is required for translate — add it to your Gemfile' unless defined?(Legion::Data::Extract)

          Legion::Data::Extract.extract(source, type: type)
        end

        def report_progress(message:, percent: nil)
          return unless job_id

          return unless defined?(Legion::Logging)

          Legion::Logging.info("absorb[#{job_id}] #{"#{percent}% " if percent}#{message}")
        end
      end
    end
  end
end
