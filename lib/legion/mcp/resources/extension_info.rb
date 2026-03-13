# frozen_string_literal: true

module Legion
  module MCP
    module Resources
      module ExtensionInfo
        class << self
          def static_resources
            []
          end

          def resource_templates
            [
              ::MCP::ResourceTemplate.new(
                uri_template: 'legion://extensions/{name}',
                name: 'extension-info',
                description: 'Detailed info about a Legion extension including runners, actors, and functions.',
                mime_type: 'application/json'
              )
            ]
          end

          def register_read_handler(_server)
            # Read handler is registered by RunnerCatalog to handle both resource types
          end

          def read(uri)
            name = uri.sub('legion://extensions/', '')
            return [] if name.empty?

            unless data_connected?
              return [{ uri: uri, mimeType: 'application/json',
                        text: Legion::JSON.dump({ error: 'legion-data is not connected' }) }]
            end

            ext = Legion::Data::Model::Extension.where(name: name).first
            unless ext
              return [{ uri: uri, mimeType: 'application/json',
                        text: Legion::JSON.dump({ error: "Extension '#{name}' not found" }) }]
            end

            runners = Legion::Data::Model::Runner.where(extension_id: ext.values[:id]).all
            result = ext.values.merge(
              runners: runners.map do |r|
                functions = Legion::Data::Model::Function.where(runner_id: r.values[:id]).all
                r.values.merge(functions: functions.map(&:values))
              end
            )

            [{ uri: uri, mimeType: 'application/json', text: Legion::JSON.dump(result) }]
          rescue StandardError => e
            [{ uri: uri, mimeType: 'application/json',
               text: Legion::JSON.dump({ error: "Failed to read extension: #{e.message}" }) }]
          end

          private

          def data_connected?
            Legion::Settings[:data][:connected]
          rescue StandardError
            false
          end
        end
      end
    end
  end
end
