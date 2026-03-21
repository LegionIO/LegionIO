# frozen_string_literal: true

require 'thor'
require 'legion/cli/output'

module Legion
  module CLI
    class Docs < Thor
      namespace :docs

      def self.exit_on_failure?
        true
      end

      class_option :json,     type: :boolean, default: false, desc: 'Output as JSON'
      class_option :no_color, type: :boolean, default: false, desc: 'Disable color output'

      desc 'generate', 'Generate static documentation site'
      option :output, type: :string, default: 'docs/site', desc: 'Output directory'
      def generate
        out = formatter
        require 'legion/docs/site_generator'

        out.header('Generating documentation site...') unless options[:json]
        stats = Legion::Docs::SiteGenerator.new(output_dir: options[:output]).generate

        if options[:json]
          out.json(stats)
        else
          out.success("Documentation generated in #{stats[:output]}")
          puts "  #{out.colorize("#{stats[:pages]} pages", :accent)} written"
          puts "  #{out.colorize("#{stats[:sections]} guide sections", :label)} converted"
        end
      end

      desc 'serve', 'Preview documentation site locally'
      option :port, type: :numeric, default: 4000, desc: 'Port to listen on'
      option :dir,  type: :string,  default: 'docs/site', desc: 'Directory to serve'
      def serve
        out = formatter
        dir  = options[:dir]
        port = options[:port]

        unless Dir.exist?(dir)
          out.warn("Directory #{dir} does not exist. Run 'legion docs generate' first.")
          return
        end

        out.header('Documentation preview')
        puts "  Open http://localhost:#{port}/ in your browser"
        puts "  Serving files from: #{File.expand_path(dir)}"
        puts ''
        puts "  To start: python3 -m http.server #{port} --directory #{dir}"
        puts '  Press Ctrl+C to stop'
      end

      no_commands do
        def formatter
          @formatter ||= Output::Formatter.new(
            json:  options[:json],
            color: !options[:no_color]
          )
        end
      end
    end
  end
end
