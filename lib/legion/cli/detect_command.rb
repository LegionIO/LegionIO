# frozen_string_literal: true

require 'thor'
require 'legion/cli/output'

module Legion
  module CLI
    class Detect < Thor
      namespace 'detect'

      def self.exit_on_failure?
        true
      end

      class_option :json, type: :boolean, default: false, desc: 'Output as JSON'
      class_option :no_color, type: :boolean, default: false, desc: 'Disable color output'

      default_task :scan

      desc 'scan', 'Scan environment and recommend extensions (default)'
      option :install, type: :boolean, default: false, desc: 'Install missing extensions after scan'
      option :dry_run, type: :boolean, default: false, desc: 'Show what would be installed without installing'
      def scan
        out = formatter
        require_detect_gem

        results = Legion::Extensions::Detect.scan

        if options[:json]
          out.json(detections: results)
        else
          display_detections(out, results)
          install_missing(out) if options[:install]
        end
      end

      desc 'catalog', 'Show the full detection catalog'
      def catalog
        out = formatter
        require_detect_gem

        catalog = Legion::Extensions::Detect.catalog

        if options[:json]
          catalog_data = catalog.map do |rule|
            { name: rule[:name], extensions: rule[:extensions],
              signals: rule[:signals].map { |s| "#{s[:type]}:#{s[:match]}" } }
          end
          out.json(catalog: catalog_data)
        else
          out.header('Detection Catalog')
          out.spacer
          catalog.each do |rule|
            signals = rule[:signals].map { |s| "#{s[:type]}:#{s[:match]}" }.join(', ')
            extensions = rule[:extensions].join(', ')
            puts "  #{out.colorize(rule[:name].ljust(20), :label)} #{extensions.ljust(30)} #{signals}"
          end
          out.spacer
          puts "  #{catalog.size} detection rules"
        end
      end

      desc 'missing', 'List extensions that should be installed but are not'
      def missing
        out = formatter
        require_detect_gem

        missing_gems = Legion::Extensions::Detect.missing

        if options[:json]
          out.json(missing: missing_gems)
        elsif missing_gems.empty?
          out.success('All detected extensions are installed')
        else
          out.header('Missing Extensions')
          missing_gems.each { |name| puts "  gem install #{name}" }
          out.spacer
          puts "  #{missing_gems.size} extension(s) recommended"
          puts "  Run 'legionio detect --install' to install them"
        end
      end

      no_commands do
        def formatter
          @formatter ||= Output::Formatter.new(
            json:  options[:json],
            color: !options[:no_color]
          )
        end

        private

        def require_detect_gem
          require 'legion/extensions/detect'
        rescue LoadError => e
          formatter.error("lex-detect gem not installed: #{e.message}")
          puts '  Install with: gem install lex-detect'
          raise SystemExit, 1
        end

        def display_detections(out, results)
          if results.empty?
            out.detail('No software detected that maps to Legion extensions.')
            return
          end

          out.header('Environment Detection')
          out.spacer

          installed_count = 0
          total_count = 0

          results.each do |detection|
            signals = detection[:matched_signals].join(', ')
            detection[:extensions].each do |ext|
              total_count += 1
              is_installed = detection[:installed][ext]
              installed_count += 1 if is_installed
              status = is_installed ? out.colorize('installed', :success) : out.colorize('missing', :error)
              puts "  #{out.colorize(detection[:name].ljust(20), :label)} #{signals.ljust(35)} #{ext.ljust(25)} #{status}"
            end
          end

          out.spacer
          puts "  #{installed_count} of #{total_count} extension(s) installed"
        end

        def install_missing(out)
          missing_gems = Legion::Extensions::Detect.missing
          return if missing_gems.empty?

          out.spacer
          if options[:dry_run]
            out.header('Would install')
            missing_gems.each { |name| puts "  #{name}" }
            return
          end

          out.header('Installing missing extensions')
          result = Legion::Extensions::Detect.install_missing!

          result[:installed].each { |name| out.success("  Installed #{name}") }
          result[:failed].each { |f| out.error("  Failed: #{f[:name]} — #{f[:error]}") }

          out.spacer
          if result[:failed].empty?
            out.success("#{result[:installed].size} extension(s) installed")
          else
            out.warn("#{result[:installed].size} installed, #{result[:failed].size} failed")
          end
        end
      end
    end
  end
end
