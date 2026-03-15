# frozen_string_literal: true

require_relative 'config_scaffold'

module Legion
  module CLI
    class Config < Thor
      def self.exit_on_failure?
        true
      end

      class_option :json, type: :boolean, default: false, desc: 'Output as JSON'
      class_option :no_color, type: :boolean, default: false, desc: 'Disable color output'
      class_option :config_dir, type: :string, desc: 'Config directory path'

      desc 'show', 'Show resolved configuration'
      option :section, type: :string, aliases: ['-s'], desc: 'Show only a specific section (e.g. transport, data, extensions)'
      def show
        out = formatter
        Connection.config_dir = options[:config_dir] if options[:config_dir]
        Connection.ensure_settings

        settings = if Legion::Settings.respond_to?(:to_hash)
                     Legion::Settings.to_hash
                   elsif Legion::Settings.respond_to?(:to_h)
                     Legion::Settings.to_h
                   else
                     # Settings uses [] accessor, enumerate known sections
                     %i[client transport data cache crypt extensions api].to_h do |key|
                       [key, Legion::Settings[key]]
                     rescue StandardError
                       [key, nil]
                     end.compact
                   end

        if options[:section]
          key = options[:section].to_sym
          unless settings.key?(key)
            out.error("Section '#{options[:section]}' not found. Available: #{settings.keys.join(', ')}")
            raise SystemExit, 1
          end
          settings = { key => settings[key] }
        end

        # Redact sensitive values
        redacted = deep_redact(settings)

        if options[:json]
          out.json(redacted)
        else
          print_nested(out, redacted)
        end
      rescue CLI::Error => e
        formatter.error(e.message)
        raise SystemExit, 1
      end
      default_task :show

      desc 'path', 'Show configuration file search paths'
      def path
        out = formatter
        paths = config_search_paths

        if options[:json]
          out.json(paths.map { |p| { path: p[:path], exists: p[:exists], active: p[:active] } })
          return
        end

        out.header('Configuration Search Paths')
        out.spacer
        paths.each do |p|
          if p[:active]
            puts "  #{out.colorize('>>', :green)} #{p[:path]} #{out.colorize('(active)', :green)}"
          elsif p[:exists]
            puts "  #{out.colorize(' *', :yellow)} #{p[:path]} #{out.colorize('(exists)', :yellow)}"
          else
            puts "  #{out.colorize('  ', :gray)} #{out.colorize(p[:path], :gray)}"
          end
        end

        out.spacer
        out.header('Environment Variables')
        env_vars = %w[LEGION_ENV LEGION_CONFIG_DIR LEGION_LOG_LEVEL]
        env_vars.each do |var|
          val = ENV.fetch(var, nil)
          if val
            puts "  #{out.colorize(var, :cyan)} = #{val}"
          else
            puts "  #{out.colorize(var, :gray)} (not set)"
          end
        end
      end

      desc 'validate', 'Validate current configuration'
      def validate # rubocop:disable Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity
        out = formatter
        Connection.config_dir = options[:config_dir] if options[:config_dir]

        issues = []
        warnings = []

        # Check settings load
        begin
          Connection.ensure_settings
          out.success('Settings loaded successfully') unless options[:json]
        rescue StandardError => e
          issues << "Settings failed to load: #{e.message}"
        end

        # Check transport config
        if Connection.settings?
          transport = Legion::Settings[:transport] || {}
          warnings << 'Transport host not configured (RabbitMQ will use default localhost)' if transport[:host].nil? || transport[:host].to_s.empty?

          # Check data config
          data = Legion::Settings[:data] || {}
          warnings << 'Database adapter not configured' if data[:adapter].nil?

          # Check extensions config
          extensions = Legion::Settings[:extensions] || {}
          warnings << 'No extensions configured in settings' if extensions.empty?
        end

        # Check LLM config
        validate_llm(warnings) if Connection.settings?

        if options[:json]
          out.json(valid: issues.empty?, issues: issues, warnings: warnings)
          return
        end

        if issues.any?
          out.spacer
          out.header('Issues')
          issues.each { |i| out.error(i) }
        end

        if warnings.any?
          out.spacer
          out.header('Warnings')
          warnings.each { |w| out.warn(w) }
        end

        if issues.empty? && warnings.empty?
          out.success('Configuration looks good')
        elsif issues.empty?
          out.warn("Configuration valid with #{warnings.size} warning(s)")
        else
          out.error("Configuration has #{issues.size} issue(s)")
          raise SystemExit, 1
        end
      end

      desc 'scaffold', 'Generate starter config files for each subsystem'
      long_desc <<~DESC
        Generates JSON config files for LegionIO subsystems (transport, data, cache,
        crypt, logging, llm). Files are written to --dir (default: ./settings/).

        By default, generates minimal starter files with only the most commonly
        changed fields. Use --full for the complete schema with all defaults.
      DESC
      option :dir, type: :string, default: './settings', desc: 'Output directory'
      option :only, type: :string, desc: 'Comma-separated subsystems (transport,data,cache,crypt,logging,llm)'
      option :full, type: :boolean, default: false, desc: 'Include all fields with defaults'
      option :force, type: :boolean, default: false, desc: 'Overwrite existing files'
      def scaffold
        out = formatter
        exit_code = ConfigScaffold.run(out, options)
        raise SystemExit, exit_code if exit_code != 0
      end

      no_commands do # rubocop:disable Metrics/BlockLength
        def formatter
          @formatter ||= Output::Formatter.new(
            json:  options[:json],
            color: !options[:no_color]
          )
        end

        def config_search_paths
          active_found = false
          [
            '/etc/legionio',
            File.expand_path('~/legionio'),
            File.expand_path('./settings')
          ].map do |path|
            exists = Dir.exist?(path)
            active = exists && !active_found
            active_found = true if active
            { path: path, exists: exists, active: active }
          end
        end

        def deep_redact(obj, depth: 0)
          case obj
          when Hash
            obj.to_h do |k, v|
              if sensitive_key?(k)
                [k, '***REDACTED***']
              else
                [k, deep_redact(v, depth: depth + 1)]
              end
            end
          when Array
            obj.map { |v| deep_redact(v, depth: depth + 1) }
          else
            obj
          end
        end

        def validate_llm(warnings)
          llm = Legion::Settings[:llm] || {}
          return unless llm[:enabled]

          warnings << 'LLM enabled but no default provider configured' if llm[:default_provider].nil? || llm[:default_provider].to_s.empty?

          keyless_providers = %i[bedrock ollama]
          (llm[:providers] || {}).each do |name, config|
            next unless config.is_a?(Hash) && config[:enabled]
            next if keyless_providers.include?(name.to_sym)
            next if config[:api_key] && !config[:api_key].to_s.empty?

            warnings << "LLM provider '#{name}' enabled but no api_key configured"
          end
        end

        def sensitive_key?(key)
          name = key.to_s.downcase
          name.match?(/(?:\A|_)(?:password|secret|token|key|credential|auth)\z/)
        end

        def print_nested(out, hash, indent: 0)
          hash.each do |key, value|
            pad = '  ' * (indent + 1)
            case value
            when Hash
              puts "#{pad}#{out.colorize("#{key}:", :cyan)}"
              print_nested(out, value, indent: indent + 1)
            when Array
              puts "#{pad}#{out.colorize("#{key}:", :cyan)} [#{value.join(', ')}]"
            else
              puts "#{pad}#{out.colorize("#{key}:", :cyan)} #{value}"
            end
          end
        end
      end
    end
  end
end
