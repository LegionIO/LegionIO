# frozen_string_literal: true

module Legion
  module MCP
    module Resources
      module RunnerCatalog
        RESOURCE = ::MCP::Resource.new(
          uri: 'legion://runners',
          name: 'runner-catalog',
          description: 'All available extension.runner.function paths in this Legion instance.',
          mime_type: 'application/json'
        )

        class << self
          def register(server)
            server.resources << RESOURCE

            server.resources_read_handler do |params|
              if params[:uri] == 'legion://runners'
                [{ uri: 'legion://runners', mimeType: 'application/json', text: catalog_json }]
              elsif params[:uri]&.start_with?('legion://extensions/')
                ExtensionInfo.read(params[:uri])
              else
                []
              end
            end
          end

          private

          def catalog_json
            unless data_connected?
              return Legion::JSON.dump({ error: 'legion-data is not connected' })
            end

            extensions = Legion::Data::Model::Extension.all
            catalog = extensions.map do |ext|
              runners = Legion::Data::Model::Runner.where(extension_id: ext.values[:id]).all
              {
                extension: ext.values[:name],
                runners: runners.map do |r|
                  functions = Legion::Data::Model::Function.where(runner_id: r.values[:id]).all
                  {
                    runner: r.values[:namespace],
                    functions: functions.map { |f| f.values[:name] }
                  }
                end
              }
            end

            Legion::JSON.dump(catalog)
          rescue StandardError => e
            Legion::JSON.dump({ error: "Failed to build catalog: #{e.message}" })
          end

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
