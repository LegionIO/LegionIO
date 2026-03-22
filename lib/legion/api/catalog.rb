# frozen_string_literal: true

module Legion
  class API < Sinatra::Base
    module Routes
      module ExtensionCatalog
        def self.registered(app)
          app.get '/api/catalog' do
            entries = Legion::Extensions::Catalog.all.map do |name, entry|
              build_catalog_manifest(name, entry)
            end
            json_response(entries)
          end

          app.get '/api/catalog/:name' do
            name = params[:name]
            entry = Legion::Extensions::Catalog.entry(name)
            unless entry
              halt 404, { 'Content-Type' => 'application/json' },
                   Legion::JSON.dump({ error: { code: 'not_found', message: "Extension #{name} not found" } })
            end

            json_response(build_catalog_manifest(name, entry))
          end
        end
      end
    end

    helpers do # rubocop:disable Metrics/BlockLength
      def build_catalog_manifest(name, entry)
        {
          name:          name,
          state:         entry[:state].to_s,
          started_at:    entry[:started_at]&.iso8601,
          permissions:   build_catalog_permissions(name),
          runners:       build_catalog_runners(name),
          known_intents: build_catalog_known_intents(name)
        }
      end

      def build_catalog_permissions(name)
        declared = Legion::Extensions::Permissions.declared_paths(name)
        {
          sandbox:     Legion::Extensions::Permissions.sandbox_path(name),
          read_paths:  declared[:read_paths],
          write_paths: declared[:write_paths]
        }
      rescue StandardError => e
        Legion::Logging.warn "API#build_catalog_permissions failed for #{name}: #{e.message}" if defined?(Legion::Logging)
        { sandbox: Legion::Extensions::Permissions.sandbox_path(name), read_paths: [], write_paths: [] }
      end

      def build_catalog_runners(name)
        return {} unless defined?(Legion::Data) && Legion::Data.respond_to?(:connected?) && Legion::Data.connected?

        ext = Legion::Data::Model::Extension.where(gem_name: name).first
        return {} unless ext

        ext.runners.to_h do |runner|
          [runner.values[:name], {
            methods:     runner.functions.map { |f| f.values[:name] },
            description: runner.values[:description]
          }]
        end
      rescue StandardError => e
        Legion::Logging.warn "API#build_catalog_runners failed for #{name}: #{e.message}" if defined?(Legion::Logging)
        {}
      end

      def build_catalog_known_intents(name)
        return [] unless defined?(Legion::MCP::PatternStore)

        matched = Legion::MCP::PatternStore.patterns.select do |_hash, pattern|
          pattern[:tool_chain]&.any? { |t| t.start_with?(name) }
        end
        matched.map do |_hash, pattern|
          { intent: pattern[:intent_text], tool_chain: pattern[:tool_chain], confidence: pattern[:confidence] }
        end
      rescue StandardError => e
        Legion::Logging.warn "API#build_catalog_known_intents failed for #{name}: #{e.message}" if defined?(Legion::Logging)
        []
      end
    end
  end
end
