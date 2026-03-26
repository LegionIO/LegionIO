# frozen_string_literal: true

require 'English'
require 'json'
require 'fileutils'
require 'rbconfig'
require 'thor'
require 'legion/cli/output'

module Legion
  module CLI
    class Bootstrap < Thor
      namespace 'bootstrap'

      def self.exit_on_failure?
        true
      end

      class_option :json,       type: :boolean, default: false, desc: 'Machine-readable output'
      class_option :no_color,   type: :boolean, default: false, desc: 'Disable color output'
      class_option :skip_packs, type: :boolean, default: false, desc: 'Skip gem pack installation (config only)'
      class_option :start,      type: :boolean, default: false, desc: 'Start redis + legionio via brew services after bootstrap'
      class_option :force,      type: :boolean, default: false, desc: 'Overwrite existing config files'

      desc 'SOURCE', 'Bootstrap Legion from a URL or local config file (fetch config, scaffold, install packs)'
      long_desc <<~DESC
        Combines three manual steps into one:

          legionio config import SOURCE   (fetch + write config)
          legionio config scaffold        (fill gaps with env-detected defaults)
          legionio setup agentic          (install cognitive gem packs)

        SOURCE may be an HTTPS URL or a local file path to a bootstrap JSON file.
        The JSON may include a "packs" array (e.g. ["agentic"]) which controls which
        gem packs are installed. That key is removed before the config is written.

        Options:
          --skip-packs   Skip gem pack installation entirely
          --start        After bootstrap, run: brew services start redis && brew services start legionio
          --force        Overwrite existing config files
          --json         Machine-readable JSON output
      DESC
      def execute(source)
        require_relative 'config_import'
        require_relative 'config_scaffold'
        require_relative 'setup_command'

        out     = formatter
        results = {}
        warns   = []

        # 1. Pre-flight checks
        print_step(out, 'Pre-flight checks')
        results[:preflight] = run_preflight_checks(out, warns)

        # 2. Fetch + parse config
        print_step(out, "Fetching config from #{source}")
        body   = ConfigImport.fetch_source(source)
        config = ConfigImport.parse_payload(body)

        # 3. Extract packs before writing (bootstrap-only directive)
        pack_names = Array(config.delete(:packs)).map(&:to_s).reject(&:empty?)
        results[:packs_requested] = pack_names

        # 4. Write config
        path = ConfigImport.write_config(config, force: options[:force])
        results[:config_written] = path
        out.success("Config written to #{path}") unless options[:json]

        # 5. Scaffold missing subsystem files
        print_step(out, 'Scaffolding missing subsystem files')
        silent_out = Output::Formatter.new(json: false, color: false)
        scaffold_opts = build_scaffold_opts
        ConfigScaffold.run(options[:json] ? silent_out : out, scaffold_opts)
        results[:scaffold] = :done

        # 6. Install packs (unless --skip-packs)
        if options[:skip_packs]
          results[:packs_installed] = []
          out.warn('Skipping pack installation (--skip-packs)') unless options[:json]
        else
          print_step(out, "Installing packs: #{pack_names.join(', ')}") unless pack_names.empty?
          results[:packs_installed] = install_packs(pack_names, out)
        end

        # 7. Post-bootstrap summary
        summary = build_summary(config, results, warns)
        results[:summary] = summary
        print_summary(out, summary)

        # 8. Optional --start
        if options[:start]
          print_step(out, 'Starting services')
          results[:services_started] = start_services(out)
        end

        out.json(results) if options[:json]
      rescue CLI::Error => e
        formatter.error(e.message)
        raise SystemExit, 1
      end

      default_task :execute

      no_commands do # rubocop:disable Metrics/BlockLength
        def formatter
          @formatter ||= Output::Formatter.new(
            json:  options[:json],
            color: !options[:no_color]
          )
        end

        private

        def print_step(out, message)
          return if options[:json]

          out.spacer
          out.header(message)
        end

        # Wraps backtick execution, returning [output, success_bool].
        # Extracted as a method so specs can stub it cleanly.
        def shell_capture(cmd)
          output = `#{cmd} 2>&1`
          [output, $CHILD_STATUS.success?]
        end

        # -----------------------------------------------------------------------
        # Pre-flight checks
        # -----------------------------------------------------------------------

        def run_preflight_checks(out, warns)
          {
            klist:    check_klist(out, warns),
            brew:     check_brew(out, warns),
            legionio: check_legionio_binary(out, warns)
          }
        end

        def check_klist(out, warns)
          output, success = shell_capture('klist')
          if success && output.match?(/principal|Credentials/i)
            out.success('Kerberos ticket valid') unless options[:json]
            { status: :ok }
          else
            msg = 'No valid Kerberos ticket found. Run `kinit` before bootstrapping.'
            warns << msg
            out.warn(msg) unless options[:json]
            { status: :warn, message: msg }
          end
        rescue StandardError => e
          msg = "klist check failed: #{e.message}"
          warns << msg
          out.warn(msg) unless options[:json]
          { status: :warn, message: msg }
        end

        def check_brew(out, warns)
          _, success = shell_capture('brew --version')
          if success
            out.success('Homebrew available') unless options[:json]
            { status: :ok }
          else
            msg = 'Homebrew not found. Install from https://brew.sh'
            warns << msg
            out.warn(msg) unless options[:json]
            { status: :warn, message: msg }
          end
        rescue StandardError => e
          msg = "brew check failed: #{e.message}"
          warns << msg
          out.warn(msg) unless options[:json]
          { status: :warn, message: msg }
        end

        def check_legionio_binary(out, warns)
          _, success = shell_capture('legionio version')
          if success
            out.success('legionio binary works') unless options[:json]
            { status: :ok }
          else
            msg = 'legionio binary not responding. Try reinstalling: brew reinstall legionio'
            warns << msg
            out.warn(msg) unless options[:json]
            { status: :warn, message: msg }
          end
        rescue StandardError => e
          msg = "legionio binary check failed: #{e.message}"
          warns << msg
          out.warn(msg) unless options[:json]
          { status: :warn, message: msg }
        end

        # -----------------------------------------------------------------------
        # Scaffold options
        # -----------------------------------------------------------------------

        def build_scaffold_opts
          {
            force: options[:force],
            json:  options[:json],
            only:  options[:only],
            full:  options[:full],
            dir:   options[:dir]
          }
        end

        # -----------------------------------------------------------------------
        # Pack installation
        # -----------------------------------------------------------------------

        def install_packs(pack_names, out)
          return [] if pack_names.empty?

          gem_bin  = File.join(RbConfig::CONFIG['bindir'], 'gem')
          results  = []

          pack_names.each do |pack_name|
            pack_sym = pack_name.to_sym
            pack     = Setup::PACKS[pack_sym]
            unless pack
              out.warn("Unknown pack: #{pack_name} (valid: #{Setup::PACKS.keys.join(', ')})") unless options[:json]
              next
            end

            out.header("Installing pack: #{pack_name}") unless options[:json]
            gem_results = install_pack_gems(pack[:gems], gem_bin, out)
            Gem::Specification.reset
            results << { pack: pack_name, results: gem_results }
          end

          results
        end

        def install_pack_gems(gem_names, gem_bin, out)
          already_installed = []
          to_install        = []

          gem_names.each do |name|
            Gem::Specification.find_by_name(name)
            already_installed << name
          rescue Gem::MissingSpecError
            to_install << name
          end

          gem_results = to_install.map { |g| install_single_gem(g, gem_bin, out) }

          already_installed.each do |g|
            out.success("  #{g} already installed") unless options[:json]
          end

          gem_results
        end

        def install_single_gem(name, gem_bin, out)
          puts "  Installing #{name}..." unless options[:json]
          output, success = shell_capture("#{gem_bin} install #{name} --no-document")
          if success
            out.success("  #{name} installed") unless options[:json]
            { name: name, status: 'installed' }
          else
            out.error("  #{name} failed") unless options[:json]
            { name: name, status: 'failed', error: output.strip.lines.last&.strip }
          end
        end

        # -----------------------------------------------------------------------
        # Summary
        # -----------------------------------------------------------------------

        def build_summary(config, results, warns)
          settings_dir = ConfigImport::SETTINGS_DIR
          subsystem_files = ConfigScaffold::SUBSYSTEMS.to_h do |s|
            path = File.join(settings_dir, "#{s}.json")
            [s, File.exist?(path)]
          end

          {
            config_sections: config.keys.map(&:to_s),
            packs_requested: results[:packs_requested] || [],
            packs_installed: results[:packs_installed] || [],
            subsystem_files: subsystem_files,
            warnings:        warns,
            preflight:       results[:preflight] || {}
          }
        end

        def print_summary(out, summary)
          return if options[:json]

          out.spacer
          out.header('Bootstrap Summary')
          out.spacer

          print_config_sections(summary)
          print_subsystem_files(summary)
          print_packs_summary(out, summary)
          print_warnings_section(out, summary)
          print_next_steps(out)
        end

        def print_config_sections(summary)
          puts "  Config sections: #{summary[:config_sections].join(', ')}" if summary[:config_sections].any?
        end

        def print_subsystem_files(summary)
          present = summary[:subsystem_files].select { |_, v| v }.keys
          absent  = summary[:subsystem_files].reject { |_, v| v }.keys
          puts "  Subsystem files present: #{present.join(', ')}" if present.any?
          puts "  Subsystem files missing: #{absent.join(', ')}"  if absent.any?
        end

        def print_packs_summary(out, summary)
          summary[:packs_installed].each do |pack_result|
            successes = (pack_result[:results] || []).count { |r| r[:status] == 'installed' }
            failures  = (pack_result[:results] || []).count { |r| r[:status] == 'failed' }
            if failures.zero?
              out.success("Pack #{pack_result[:pack]}: #{successes} gem(s) installed")
            else
              out.warn("Pack #{pack_result[:pack]}: #{successes} installed, #{failures} failed")
            end
          end
          out.warn('Pack installation skipped') if options[:skip_packs]
        end

        def print_warnings_section(out, summary)
          return unless summary[:warnings].any?

          out.spacer
          out.header('Attention')
          summary[:warnings].each { |w| out.warn(w) }
        end

        def print_next_steps(out)
          return if options[:start]

          out.spacer
          puts '  Next steps:'
          puts '    brew services start redis && brew services start legionio'
          puts '    legion'
        end

        # -----------------------------------------------------------------------
        # Service startup (--start)
        # -----------------------------------------------------------------------

        def start_services(out)
          redis_ok   = run_brew_service('redis', out)
          legion_ok  = run_brew_service('legionio', out)
          poll_daemon_ready(out) if redis_ok && legion_ok
          { redis: redis_ok, legionio: legion_ok }
        end

        def run_brew_service(service, out)
          output, success = shell_capture("brew services start #{service}")
          if success
            out.success("#{service} started") unless options[:json]
            true
          else
            out.warn("#{service} failed to start: #{output.strip.lines.last&.strip}") unless options[:json]
            false
          end
        rescue StandardError => e
          out.warn("brew services start #{service} raised: #{e.message}") unless options[:json]
          false
        end

        def poll_daemon_ready(out, port: 4567, timeout: 30)
          require 'net/http'
          deadline = ::Time.now + timeout
          until ::Time.now > deadline
            begin
              resp = Net::HTTP.get_response(URI("http://localhost:#{port}/api/ready"))
              if resp.is_a?(Net::HTTPSuccess)
                out.success("Daemon ready on port #{port}") unless options[:json]
                return true
              end
            rescue StandardError
              # not ready yet — keep polling
            end
            sleep 1
          end
          out.warn("Daemon did not become ready within #{timeout}s") unless options[:json]
          false
        end
      end
    end
  end
end
