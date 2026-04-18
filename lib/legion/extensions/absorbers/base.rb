# frozen_string_literal: true

require_relative '../definitions'
require_relative '../helpers/lex'

module Legion
  module Extensions
    module Absorbers
      class Base
        extend Legion::Extensions::Definitions
        include Legion::Extensions::Helpers::Lex

        class TokenRevocationError < StandardError
        end

        class TokenUnavailableError < StandardError
        end

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

        def absorb(url: nil, content: nil, metadata: {}, context: {})
          raise NotImplementedError, "#{self.class.name} must implement #absorb"
        end

        # @deprecated Use {#absorb} instead. Will be removed in a future major release.
        def handle(url: nil, content: nil, metadata: {}, context: {})
          Legion::Logging.warn("#{self.class.name}#handle is deprecated — use #absorb instead") if defined?(Legion::Logging)
          absorb(url: url, content: content, metadata: metadata, context: context)
        end

        def absorb_to_knowledge(content:, tags: [], scope: :global, **opts)
          return fallback_absorb(:chunker, content, tags, scope, opts) unless chunker_available?

          target = resolve_apollo_target(scope)
          return fallback_absorb(:apollo, content, tags, scope, opts) unless target

          sections = [{ heading:      opts.delete(:heading) || 'absorbed',
                        content:      content,
                        section_path: opts.delete(:section_path) || 'absorbed',
                        source_file:  opts.delete(:source_file) || 'absorber' }]
          chunks     = Legion::Extensions::Knowledge::Helpers::Chunker.chunk(sections: sections)
          embeddings = fetch_embeddings(chunks)
          ingest_chunks(chunks, embeddings, tags, scope, opts)
        end

        def absorb_raw(content:, tags: [], scope: :global, **)
          target = resolve_apollo_target(scope)
          unless target
            Legion::Logging.warn("absorb_raw: Apollo not available for scope=#{scope}") if defined?(Legion::Logging)
            return { success: false, error: :apollo_not_available }
          end

          target.ingest(content: content, tags: Array(tags), scope: scope, **)
        end

        def query_knowledge(text:, limit: 5, scope: :all, **)
          case scope.to_sym
          when :local
            return { success: false, error: :apollo_not_available } unless apollo_local_available?

            Legion::Apollo::Local.query(text: text, limit: limit, **)
          when :global
            return { success: false, error: :apollo_not_available } unless apollo_available?

            Legion::Apollo.query(text: text, limit: limit, **)
          else
            query_all_scopes(text: text, limit: limit, **)
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

        def with_token(provider:)
          raise TokenUnavailableError, "#{provider} token not available" unless token_manager_for(provider).token_valid?
          raise TokenRevocationError, "#{provider} token has been revoked" if token_manager_for(provider).revoked?

          token = token_manager_for(provider).ensure_valid_token
          raise TokenUnavailableError, "#{provider} token refresh failed" unless token

          yield token
        rescue Legion::Auth::TokenManager::TokenExpiredError => e
          raise TokenUnavailableError, e.message
        end

        private

        def token_manager_for(provider)
          @token_managers ||= {}
          @token_managers[provider] ||= begin
            require 'legion/auth/token_manager'
            Legion::Auth::TokenManager.new(provider: provider)
          end
        end

        def chunker_available?
          defined?(Legion::Extensions::Knowledge::Helpers::Chunker)
        end

        def apollo_available?
          defined?(Legion::Apollo) &&
            Legion::Apollo.respond_to?(:ingest) &&
            (!Legion::Apollo.respond_to?(:started?) || Legion::Apollo.started?)
        end

        def apollo_local_available?
          defined?(Legion::Apollo::Local) &&
            Legion::Apollo::Local.respond_to?(:ingest) &&
            (!Legion::Apollo::Local.respond_to?(:started?) || Legion::Apollo::Local.started?)
        rescue NameError
          false
        end

        def resolve_apollo_target(scope)
          case scope.to_sym
          when :local
            apollo_local_available? ? Legion::Apollo::Local : nil
          else
            apollo_available? ? Legion::Apollo : nil
          end
        end

        def query_all_scopes(text:, limit:, **)
          local_results  = apollo_local_available? ? Array((Legion::Apollo::Local.query(text: text, limit: limit, **) || {})[:results]) : []
          global_results = apollo_available? ? Array((Legion::Apollo.query(text: text, limit: limit, **) || {})[:results]) : []

          if local_results.empty? && global_results.empty? && !apollo_local_available? && !apollo_available?
            return { success: false, error: :apollo_not_available }
          end

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

          { success: true, results: merged.first(limit), count: [merged.size, limit].min, scope: :all }
        end

        def fallback_absorb(reason, content, tags, scope, opts)
          if defined?(Legion::Logging)
            label = reason == :chunker ? 'lex-knowledge not available' : 'Apollo not available'
            Legion::Logging.warn("absorb_to_knowledge: #{label}, falling back to absorb_raw")
          end
          absorb_raw(content: content, tags: tags, scope: scope, **opts)
        end

        def fetch_embeddings(chunks)
          return [] unless defined?(Legion::LLM) && Legion::LLM.respond_to?(:embed_batch)

          Legion::LLM.embed_batch(chunks.map { |c| c[:content] })
        rescue StandardError
          []
        end

        def ingest_chunks(chunks, embeddings, tags, scope, opts)
          target = resolve_apollo_target(scope)
          return unless target

          chunks.each_with_index do |chunk, idx|
            vector  = embeddings.is_a?(Array) ? embeddings.dig(idx, :vector) : nil
            payload = build_chunk_payload(chunk, tags, opts)
            payload[:embedding] = vector if vector
            target.ingest(content: payload[:content], tags: payload[:tags],
                          scope: scope, **payload.except(:content, :tags))
          end
        end

        def build_chunk_payload(chunk, tags, opts)
          {
            content:      chunk[:content],
            content_type: opts[:content_type] || 'absorbed_chunk',
            content_hash: chunk[:content_hash],
            tags:         (Array(tags) + [chunk[:heading], 'absorbed']).compact.uniq,
            metadata:     {
              source_file:  chunk[:source_file],
              heading:      chunk[:heading],
              section_path: chunk[:section_path],
              chunk_index:  chunk[:chunk_index],
              token_count:  chunk[:token_count]
            }.merge(opts.fetch(:metadata, {}))
          }
        end
      end
    end
  end
end
