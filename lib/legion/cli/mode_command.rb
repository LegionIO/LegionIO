# frozen_string_literal: true

require 'thor'
require 'fileutils'
require 'legion/cli/output'
require 'legion/cli/connection'

module Legion
  module CLI
    class Mode < Thor
      SETTINGS_DIR = File.expand_path('~/.legionio/settings')
      ROLE_FILE    = File.join(SETTINGS_DIR, 'role.json')

      VALID_PROFILES = %i[core cognitive service dev custom].freeze

      PROFILE_DESCRIPTIONS = {
        core:      '14 core operational extensions only',
        cognitive: 'core + all agentic extensions',
        service:   'core + service + other integrations',
        dev:       'core + AI + essential agentic (~20 extensions)',
        custom:    'only extensions listed in role.extensions'
      }.freeze

      def self.exit_on_failure?
        true
      end

      class_option :json,     type: :boolean, default: false, desc: 'Output as JSON'
      class_option :no_color, type: :boolean, default: false, desc: 'Disable color output'

      desc 'show', 'Show current process role and extension profile'
      def show
        out = formatter
        Connection.ensure_settings

        process_role = Legion::ProcessRole.current
        profile = Legion::Settings.dig(:role, :profile)&.to_s || '(none — all extensions load)'
        custom_exts = Array(Legion::Settings.dig(:role, :extensions))

        if options[:json]
          out.json({ process_role: process_role, extension_profile: profile,
                     custom_extensions: custom_exts })
          return
        end

        out.header('Current Mode')
        details = {
          'Process Role'      => process_role.to_s,
          'Extension Profile' => profile
        }
        details['Custom Extensions'] = custom_exts.join(', ') if profile.to_s == 'custom' && custom_exts.any?
        out.detail(details)
      end

      desc 'list', 'List available extension profiles and process roles'
      def list
        out = formatter
        Connection.ensure_settings

        if options[:json]
          out.json({ profiles: PROFILE_DESCRIPTIONS, process_roles: Legion::ProcessRole::ROLES.keys })
          return
        end

        out.header('Extension Profiles')
        profile_rows = PROFILE_DESCRIPTIONS.map do |name, desc|
          count = count_extensions_for_profile(name)
          [name.to_s, desc, count.to_s]
        end
        out.table(%w[profile description extensions], profile_rows)

        out.spacer
        out.header('Process Roles')
        role_rows = Legion::ProcessRole::ROLES.map do |name, subsystems|
          enabled = subsystems.select { |_, v| v }.keys.join(', ')
          [name.to_s, enabled]
        end
        out.table(%w[role enabled_subsystems], role_rows)
      end

      desc 'set PROFILE', 'Set extension profile and/or process role'
      long_desc <<~DESC
        Set the extension profile (core, cognitive, service, dev, custom) and
        optionally the process role (full, api, worker, router, lite).

        Examples:
          legionio mode set dev
          legionio mode set custom --extensions tick,react,knowledge
          legionio mode set --process-role worker
          legionio mode set cognitive --process-role worker
      DESC
      option :process_role, type: :string, desc: 'Process role (full, api, worker, router, lite)'
      option :extensions,   type: :string, desc: 'Comma-separated extension list (for custom profile)'
      option :dry_run,      type: :boolean, default: false, desc: 'Preview changes without writing config'
      option :reload,       type: :boolean, default: false, desc: 'Trigger daemon reload after writing config'
      def set(profile = nil)
        out = formatter
        Connection.ensure_settings

        validate_inputs!(out, profile)

        new_config = build_config(profile)
        existing = read_existing_config

        if options[:dry_run]
          show_dry_run(out, existing, new_config)
          return
        end

        write_config(new_config)
        out.success("Mode updated: #{ROLE_FILE}")
        show_written_config(out, new_config)

        trigger_reload(out) if options[:reload]
      end

      no_commands do
        def formatter
          @formatter ||= Output::Formatter.new(json: options[:json], color: !options[:no_color])
        end

        def validate_inputs!(out, profile)
          if profile
            sym = profile.to_sym
            unless VALID_PROFILES.include?(sym)
              out.error("Unknown profile: '#{profile}'. Valid profiles: #{VALID_PROFILES.join(', ')}")
              raise SystemExit, 1
            end

            if sym == :custom && !options[:extensions]
              out.error('Custom profile requires --extensions (comma-separated list)')
              raise SystemExit, 1
            end
          end

          return unless options[:process_role]

          role_sym = options[:process_role].to_sym
          return if Legion::ProcessRole::ROLES.key?(role_sym)

          out.error("Unknown process role: '#{options[:process_role]}'. Valid roles: #{Legion::ProcessRole::ROLES.keys.join(', ')}")
          raise SystemExit, 1
        end

        def build_config(profile)
          config = read_existing_config

          if profile
            config[:role] ||= {}
            config[:role][:profile] = profile.to_s
            if profile.to_sym == :custom && options[:extensions]
              config[:role][:extensions] = options[:extensions].split(',').map(&:strip)
            elsif profile.to_sym != :custom
              config[:role].delete(:extensions)
            end
          end

          if options[:process_role]
            config[:process] ||= {}
            config[:process][:role] = options[:process_role]
          end

          config
        end

        def read_existing_config
          return {} unless File.exist?(ROLE_FILE)

          Legion::JSON.load(File.read(ROLE_FILE))
        rescue StandardError
          {}
        end

        def write_config(config)
          FileUtils.mkdir_p(SETTINGS_DIR)
          File.write(ROLE_FILE, ::JSON.pretty_generate(config))
        end

        def show_dry_run(out, existing, new_config)
          out.header('Dry Run — changes that would be written')
          out.detail({
                       'File'   => ROLE_FILE,
                       'Before' => existing.empty? ? '(no file)' : existing.to_s,
                       'After'  => new_config.to_s
                     })

          profile = new_config.dig(:role, :profile) || new_config.dig('role', 'profile')
          return unless profile

          count = count_extensions_for_profile(profile.to_sym)
          out.spacer
          puts "  Extensions that would load: #{count}"
        end

        def show_written_config(out, config)
          profile = config.dig(:role, :profile)
          role = config.dig(:process, :role)
          parts = []
          parts << "profile=#{profile}" if profile
          parts << "process_role=#{role}" if role
          exts = config.dig(:role, :extensions)
          parts << "extensions=#{exts.join(',')}" if exts.is_a?(Array) && exts.any?
          out.dim("  #{parts.join('  ')}")&.then { |msg| puts msg }
        end

        def trigger_reload(out)
          require 'net/http'
          uri = URI('http://127.0.0.1:4567/api/reload')
          response = Net::HTTP.post(uri, '', 'Content-Type' => 'application/json')
          if response.is_a?(Net::HTTPSuccess)
            out.success('Daemon reload triggered')
          else
            out.warn("Daemon reload returned #{response.code}: #{response.body}")
          end
        rescue StandardError => e
          out.warn("Could not reach daemon for reload: #{e.message}")
          out.dim('  Changes will take effect on next `legionio start`')&.then { |msg| puts msg }
        end

        def count_extensions_for_profile(profile)
          Legion::Extensions.find_extensions if Legion::Extensions.instance_variable_get(:@extensions).nil?

          all_extensions = Legion::Extensions.instance_variable_get(:@extensions) || []
          all_names = all_extensions.map { |e| e[:gem_name] }

          allowed = Legion::Extensions.allowed_gem_names_for_profile(profile, { extensions: [] })
          return all_names.count unless allowed

          (all_names & allowed).count
        rescue StandardError
          '?'
        end
      end
    end
  end
end
