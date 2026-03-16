# frozen_string_literal: true

module Legion
  module CLI
    class Openapi < Thor
      def self.exit_on_failure?
        true
      end

      class_option :json,     type: :boolean, default: false, desc: 'Output as JSON'
      class_option :no_color, type: :boolean, default: false, desc: 'Disable color output'

      desc 'generate', 'Generate OpenAPI spec JSON'
      method_option :output, aliases: '-o', type: :string, desc: 'Output file path'
      def generate
        require 'sinatra/base'
        require 'legion/version'
        require 'legion/settings'
        require 'legion/api/openapi'

        Legion::Settings.load unless Legion::Settings.instance_variable_get(:@loader)
        loader = Legion::Settings.loader
        loader.settings[:client] ||= { name: 'legion' }

        spec = Legion::API::OpenAPI.to_json

        if options[:output]
          File.write(options[:output], spec)
          say "OpenAPI spec written to #{options[:output]}"
        else
          puts spec
        end
      end

      desc 'routes', 'List all API routes'
      def routes
        require 'sinatra/base'
        require 'legion/version'
        require 'legion/settings'
        require 'legion/api/openapi'

        Legion::Settings.load unless Legion::Settings.instance_variable_get(:@loader)
        loader = Legion::Settings.loader
        loader.settings[:client] ||= { name: 'legion' }

        Legion::API::OpenAPI.spec[:paths].each do |path, methods|
          methods.each do |method, details|
            summary = details.is_a?(Hash) ? (details[:summary] || '') : ''
            puts "#{method.to_s.upcase.ljust(7)} #{path}  # #{summary}"
          end
        end
      end
    end
  end
end
