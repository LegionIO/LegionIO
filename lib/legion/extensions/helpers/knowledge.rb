# frozen_string_literal: true

require_relative 'base'

module Legion
  module Extensions
    module Helpers
      module Knowledge
        include Legion::Extensions::Helpers::Base

        def ingest_knowledge(content_or_path, type: :auto, tags: [], scope: :global, **opts)
          target = resolve_ingest_target(scope)
          return { success: false, error: :apollo_not_available } unless target

          text, metadata = extract_if_needed(content_or_path, type: type)
          return { success: false, error: :extraction_failed, detail: metadata } unless text

          extraction_tags = metadata_to_tags(metadata) if metadata
          all_tags = Array(tags) + Array(extraction_tags) + Array(knowledge_default_tags)

          target.ingest(
            content:        text,
            tags:           all_tags,
            source_channel: opts[:source_channel] || derive_lex_name,
            **opts.except(:source_channel)
          )
        end

        def query_knowledge(text:, limit: 5, scope: nil, **)
          scope ||= default_query_scope

          case scope.to_sym
          when :local  then query_local(text: text, limit: limit, **)
          when :global then query_global(text: text, limit: limit, **)
          else              query_all(text: text, limit: limit, **)
          end
        end

        # --- Status ---
        # Override these in your LEX to customise availability checks.

        def knowledge_connected?
          knowledge_global_connected? || knowledge_local_connected?
        rescue StandardError
          false
        end

        def knowledge_global_connected?
          global_available?
        rescue StandardError
          false
        end

        def knowledge_local_connected?
          local_available?
        rescue StandardError
          false
        end

        # --- Layered Defaults ---
        # Override in your LEX to set extension-level defaults.
        # Resolution chain: LEX override -> Settings -> hardcoded fallback

        # Override to set a custom default query scope for this extension.
        # Resolution: LEX override -> Settings[:apollo][:local][:default_query_scope] -> :all
        def knowledge_default_scope
          return :all unless defined?(Legion::Settings)

          scope = Legion::Settings.dig(:apollo, :local, :default_query_scope)
          scope ? scope.to_sym : :all
        rescue StandardError
          :all
        end

        # Override to automatically attach extension-level tags to every ingest call.
        # Resolution: LEX override -> [] (no default tags)
        def knowledge_default_tags
          []
        rescue StandardError
          []
        end

        private

        def resolve_ingest_target(scope)
          case scope.to_sym
          when :local
            local_available? ? Legion::Apollo::Local : nil
          else
            global_available? ? Legion::Apollo : nil
          end
        end

        def query_local(text:, limit:, **)
          unless local_available?
            Legion::Logging.debug 'query_knowledge(:local) called but Apollo::Local is not available' if defined?(Legion::Logging)
            return { success: false, error: :apollo_not_available }
          end

          Legion::Apollo::Local.query(text: text, limit: limit, **)
        end

        def query_global(text:, limit:, **)
          unless global_available?
            Legion::Logging.debug 'query_knowledge(:global) called but Apollo is not available' if defined?(Legion::Logging)
            return { success: false, error: :apollo_not_available }
          end

          Legion::Apollo.query(text: text, limit: limit, **)
        end

        def query_all(text:, limit:, **)
          local_results  = local_available?  ? Array((Legion::Apollo::Local.query(text: text, limit: limit, **) || {})[:results]) : []
          global_results = global_available? ? Array((Legion::Apollo.query(text: text, limit: limit, **) || {})[:results]) : []

          return { success: false, error: :apollo_not_available } if local_results.empty? && global_results.empty? && !local_available? && !global_available?

          merged = merge_results(local_results, global_results)
          { success: true, results: merged.first(limit), count: [merged.size, limit].min, mode: :all }
        end

        def merge_results(local_results, global_results)
          seen = {}
          merged = []

          local_results.each do |r|
            key = r[:content_hash] || r[:content]
            seen[key] = true
            merged << r
          end

          global_results.each do |r|
            key = r[:content_hash] || r[:content]
            merged << r unless seen[key]
          end

          merged
        end

        def global_available?
          defined?(Legion::Apollo) && Legion::Apollo.started?
        end

        def local_available?
          defined?(Legion::Apollo::Local) && Legion::Apollo::Local.started?
        end

        def default_query_scope
          knowledge_default_scope
        end

        def extract_if_needed(content_or_path, type:)
          return extract_file(content_or_path, type: type) if content_or_path.is_a?(String) && File.exist?(content_or_path)
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
          parts = self.class.name&.split('::')
          parts && parts[2] ? parts[2].downcase : 'unknown'
        end
      end
    end
  end
end
