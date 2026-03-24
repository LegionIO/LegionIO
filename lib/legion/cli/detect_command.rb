# frozen_string_literal: true

require 'json'
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

      CORE_RECOMMENDATIONS = {
        'legion-gaia' => 'Cognitive coordination (GAIA + agentic extensions)',
        'legion-llm'  => 'LLM routing and provider integration'
      }.freeze

      default_task :scan

      desc 'scan', 'Scan environment and recommend extensions (default)'
      option :install, type: :boolean, default: false, desc: 'Interactive install of missing extensions after scan'
      option :install_all, type: :boolean, default: false, desc: 'Install all missing extensions without prompting'
      option :dry_run, type: :boolean, default: false, desc: 'Show what would be installed without installing'
      option :format, type: :string, enum: %w[sarif markdown json], desc: 'Output format (sarif, markdown, json)'
      def scan
        out = formatter
        require_detect_gem

        results = Legion::Extensions::Detect.scan

        if options[:format]
          output = Legion::Extensions::Detect.format_results(format: options[:format], detections: results)
          puts output.is_a?(String) ? output : ::JSON.pretty_generate(output)
        elsif options[:json]
          out.json(detections: results)
        else
          display_detections(out, results)
          if options[:install]
            interactive_install(out, results)
          elsif options[:install_all]
            install_missing(out)
          end
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
          display_pack_recommendations(out)

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

        def display_pack_recommendations(out)
          missing = CORE_RECOMMENDATIONS.reject { |gem_name, _| gem_installed?(gem_name) }
          return if missing.empty?

          out.header('Recommended Feature Packs')
          out.spacer
          missing.each do |gem_name, desc|
            puts "  #{out.colorize(gem_name.ljust(20), :label)} #{desc}"
          end
          out.spacer
          puts "  Install with: #{out.colorize('legion setup agentic', :accent)}"
          out.spacer
        end

        def gem_installed?(name)
          Gem::Specification.find_by_name(name)
          true
        rescue Gem::MissingSpecError
          false
        end

        def interactive_install(out, results)
          missing_gems = Legion::Extensions::Detect.missing
          return out.success('All detected extensions are installed') if missing_gems.empty?

          signal_map = build_signal_map(results)
          selected = pick_extensions(out, missing_gems, signal_map)
          if selected.empty?
            puts '  No extensions selected'
            return
          end

          if options[:dry_run]
            out.header('Would install')
            selected.each { |name| puts "  #{name}" }
            return
          end

          install_selected(out, selected)
        end

        def pick_extensions(out, missing_gems, signal_map)
          if tty_prompt_available?
            pick_with_tty_prompt(missing_gems, signal_map)
          else
            pick_with_numbers(out, missing_gems, signal_map)
          end
        end

        def pick_with_tty_prompt(missing_gems, signal_map)
          require 'tty-prompt'
          prompt = ::TTY::Prompt.new

          choices = missing_gems.map do |name|
            label = signal_map[name] ? "#{name} (#{signal_map[name]})" : name
            { name: label, value: name }
          end

          prompt.multi_select('Select extensions to install:', choices, per_page: 20, echo: false)
        end

        def pick_with_numbers(out, missing_gems, signal_map)
          out.spacer
          out.header('Missing Extensions')
          missing_gems.each_with_index do |name, idx|
            reason = signal_map[name] ? " (#{signal_map[name]})" : ''
            puts "  #{out.colorize((idx + 1).to_s.rjust(3), :label)}  #{name}#{reason}"
          end
          out.spacer
          puts '  Enter numbers to install (comma-separated), "all", or "none":'
          print '  > '
          input = $stdin.gets&.strip || 'none'

          return missing_gems.dup if input.downcase == 'all'
          return [] if input.empty? || input.downcase == 'none'

          indices = input.split(/[,\s]+/).filter_map { |s| s.to_i - 1 if s.match?(/\A\d+\z/) }
          indices.filter_map { |i| missing_gems[i] if i >= 0 && i < missing_gems.size }.uniq
        end

        def build_signal_map(results)
          map = {}
          results.each do |detection|
            signals = detection[:matched_signals].join(', ')
            detection[:installed].each do |gem_name, installed|
              map[gem_name] = signals unless installed
            end
          end
          map
        end

        def install_selected(out, selected)
          out.header("Installing #{selected.size} extension(s)")
          result = Legion::Extensions::Detect::Installer.install(selected)

          result[:installed].each { |name| out.success("  Installed #{name}") }
          result[:failed].each { |f| out.error("  Failed: #{f[:name]} — #{f[:error]}") }

          out.spacer
          if result[:failed].empty?
            out.success("#{result[:installed].size} extension(s) installed")
          else
            out.warn("#{result[:installed].size} installed, #{result[:failed].size} failed")
          end
        end

        def tty_prompt_available?
          require 'tty-prompt'
          true
        rescue LoadError => e
          Legion::Logging.debug("DetectCommand#tty_prompt_available? tty-prompt not available: #{e.message}") if defined?(Legion::Logging)
          false
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
