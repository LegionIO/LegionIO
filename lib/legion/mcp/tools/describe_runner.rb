# frozen_string_literal: true

module Legion
  module MCP
    module Tools
      class DescribeRunner < ::MCP::Tool
        tool_name 'legion.describe_runner'
        description 'Discover available functions on a runner. Use dot notation (e.g., "http.request") or omit to list all.'

        input_schema(
          properties: {
            runner: {
              type: 'string',
              description: 'Dot notation path: extension.runner (e.g., "http.request"). Omit to list all.'
            }
          }
        )

        class << self
          def call(runner: nil)
            return error_response('legion-data is not connected') unless data_connected?

            runner ? describe_single(runner) : describe_all
          rescue StandardError => e
            error_response("Failed to describe runners: #{e.message}")
          end

          private

          def data_connected?
            Legion::Settings[:data][:connected]
          rescue StandardError
            false
          end

          def describe_single(runner)
            parts = runner.split('.')
            return error_response("Invalid format '#{runner}'. Expected: extension.runner") unless parts.length == 2

            runners = Legion::Data::Model::Runner.all
            matching = runners.select do |r|
              ns = r.values[:namespace]&.downcase
              ns&.include?(parts[0]) && ns&.include?(parts[1])
            end

            return error_response("No runner found matching '#{runner}'") if matching.empty?

            results = matching.map do |r|
              functions = Legion::Data::Model::Function.where(runner_id: r.values[:id]).all
              {
                runner: r.values[:namespace],
                runner_id: r.values[:id],
                functions: functions.map { |f| { id: f.values[:id], name: f.values[:name] } }
              }
            end

            text_response(results)
          end

          def describe_all
            extensions = Legion::Data::Model::Extension.all
            catalog = extensions.map do |ext|
              runners = Legion::Data::Model::Runner.where(extension_id: ext.values[:id]).all
              {
                extension: ext.values[:name],
                extension_id: ext.values[:id],
                runners: runners.map do |r|
                  functions = Legion::Data::Model::Function.where(runner_id: r.values[:id]).all
                  {
                    runner: r.values[:namespace],
                    runner_id: r.values[:id],
                    functions: functions.map { |f| { id: f.values[:id], name: f.values[:name] } }
                  }
                end
              }
            end

            text_response(catalog)
          end

          def text_response(data)
            ::MCP::Tool::Response.new([{ type: 'text', text: Legion::JSON.dump(data) }])
          end

          def error_response(message)
            ::MCP::Tool::Response.new([{ type: 'text', text: Legion::JSON.dump({ error: message }) }], error: true)
          end
        end
      end
    end
  end
end
