# frozen_string_literal: true

require 'English'
require 'thor'
require 'rbconfig'
require 'legion/cli/output'

module Legion
  module CLI
    class Features < Thor
      namespace 'features'

      def self.exit_on_failure?
        true
      end

      class_option :json,     type: :boolean, default: false, desc: 'Output as JSON'
      class_option :no_color, type: :boolean, default: false, desc: 'Disable color output'

      BUNDLES = {
        tasking:       {
          label:       'Tasking Engine',
          description: 'Task scheduling, chaining, conditioning, and metering',
          gems:        %w[lex-tasker lex-scheduler lex-lex lex-conditioner lex-transformer lex-health lex-metering]
        },
        cognitive:     {
          label:       'Cognitive / Agentic',
          description: 'Full GAIA cognitive stack (13 agentic domains + tick + mesh + apollo)',
          gems:        %w[legion-gaia]
        },
        ai:            {
          label:       'AI / LLM',
          description: 'LLM routing, provider integration, and MCP tools',
          gems:        %w[legion-llm legion-mcp]
        },
        observability: {
          label:       'Observability',
          description: 'Telemetry, logging, anomaly detection, and webhooks',
          gems:        %w[lex-telemetry lex-log lex-webhook lex-detect]
        },
        governance:    {
          label:       'Governance & Security',
          description: 'RBAC, audit trails, FinOps, PII protection, and lifecycle governance',
          gems:        %w[lex-governance lex-audit lex-finops lex-privatecore]
        },
        channels:      {
          label:       'Chat Channels',
          description: 'Slack, Microsoft Teams, and GitHub chat adapters',
          gems:        %w[lex-slack lex-microsoft_teams lex-github]
        },
        devtools:      {
          label:       'Development Tools',
          description: 'Eval gating, datasets, prompt templates, autofix, and mind-growth',
          gems:        %w[lex-eval lex-dataset lex-prompt lex-autofix lex-mind-growth]
        },
        swarm:         {
          label:       'Swarm / Multi-Agent',
          description: 'Multi-agent orchestration, GitHub swarm pipeline, and ACP adapter',
          gems:        %w[lex-swarm lex-swarm-github lex-adapter lex-acp]
        },
        services:      {
          label:       'Service Integrations',
          description: 'HTTP, Vault, and Consul service connectors',
          gems:        %w[lex-http lex-vault lex-consul]
        }
      }.freeze

      desc 'install', 'Interactively select and install feature bundles'
      option :dry_run, type: :boolean, default: false, desc: 'Show what would be installed without installing'
      option :all,     type: :boolean, default: false, desc: 'Install all feature bundles'
      def install
        out = formatter
        selected = options[:all] ? BUNDLES.keys : prompt_bundle_selection(out)

        return out.error('No bundles selected') if selected.empty?

        gems = resolve_gems(selected)
        installed, missing = partition_gems(gems)

        if missing.empty?
          report_all_present(out, selected, installed)
        elsif options[:dry_run]
          report_dry_run(out, selected, installed, missing)
        else
          execute_install(out, selected, installed, missing)
        end
      end

      desc 'list', 'Show available feature bundles and their install status'
      def list
        out = formatter
        statuses = bundle_statuses

        if options[:json]
          out.json(bundles: statuses)
        else
          out.header('Feature Bundles')
          out.spacer
          statuses.each { |s| print_bundle_status(out, s) }
          out.spacer
          installed_count = statuses.count { |s| s[:missing].empty? }
          puts "  #{installed_count} of #{statuses.size} bundle(s) fully installed"
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

        def prompt_bundle_selection(out)
          require 'tty-prompt'
          prompt = ::TTY::Prompt.new
          statuses = bundle_statuses

          choices = statuses.map do |s|
            icon = s[:missing].empty? ? '(installed)' : "(#{s[:missing].size} gem(s) to install)"
            { name: "#{s[:label]}  #{icon}  - #{s[:description]}", value: s[:name] }
          end
          choices << { name: 'Everything  - install all bundles above', value: :everything }

          out.header('Legion Feature Bundles')
          out.spacer

          selected = prompt.multi_select('Select bundles to install:', choices, per_page: 12,
                                                                                echo:     false,
                                                                                min:      1)
          return BUNDLES.keys if selected.include?(:everything)

          selected
        rescue ::TTY::Reader::InputInterrupt, Interrupt
          out.spacer
          puts '  Cancelled.'
          []
        end

        def resolve_gems(bundle_keys)
          bundle_keys.flat_map { |key| BUNDLES[key][:gems] }.uniq.sort
        end

        def partition_gems(gem_names)
          installed = []
          missing = []
          gem_names.each do |name|
            Gem::Specification.find_by_name(name)
            installed << name
          rescue Gem::MissingSpecError
            missing << name
          end
          [installed, missing]
        end

        def gem_version(name)
          Gem::Specification.find_by_name(name).version.to_s
        rescue Gem::MissingSpecError
          nil
        end

        def bundle_statuses
          BUNDLES.map do |name, bundle|
            installed, missing = partition_gems(bundle[:gems])
            {
              name:        name,
              label:       bundle[:label],
              description: bundle[:description],
              installed:   installed.map { |g| { name: g, version: gem_version(g) } },
              missing:     missing
            }
          end
        end

        def print_bundle_status(out, status)
          icon = if status[:missing].empty?
                   out.colorize('installed', :success)
                 else
                   out.colorize("#{status[:missing].size} missing", :muted)
                 end
          puts "  #{out.colorize(status[:label].ljust(24), :label)} #{icon}"
          status[:installed].each do |g|
            puts "    #{out.colorize(g[:name], :success)} #{g[:version]}"
          end
          status[:missing].each do |g|
            puts "    #{out.colorize(g, :muted)} (not installed)"
          end
        end

        def report_all_present(out, selected, installed)
          labels = selected.map { |k| BUNDLES[k][:label] }.join(', ')
          if options[:json]
            out.json(status: 'already_installed', bundles: selected,
                     gems: installed.map { |g| { name: g, version: gem_version(g) } })
          else
            out.success("All gems already installed for: #{labels}")
            installed.each { |g| puts "  #{g} #{gem_version(g)}" }
          end
        end

        def report_dry_run(out, selected, installed, missing)
          labels = selected.map { |k| BUNDLES[k][:label] }.join(', ')
          if options[:json]
            out.json(status: 'dry_run', bundles: selected, to_install: missing,
                     already_installed: installed.map { |g| { name: g, version: gem_version(g) } })
          else
            out.header("Feature install dry run: #{labels}")
            out.spacer
            missing.each { |g| puts "  #{out.colorize('install', :accent)} #{g}" }
            installed.each { |g| puts "  #{out.colorize('skip', :muted)} #{g} #{gem_version(g)} (already installed)" }
          end
        end

        def execute_install(out, selected, installed, missing)
          labels = selected.map { |k| BUNDLES[k][:label] }.join(', ')
          out.header("Installing: #{labels}") unless options[:json]
          out.spacer unless options[:json]
          puts "  #{missing.size} gem(s) to install, #{installed.size} already present" unless options[:json]
          out.spacer unless options[:json]

          gem_bin = File.join(RbConfig::CONFIG['bindir'], 'gem')
          results = missing.map { |g| install_gem(g, gem_bin, out) }

          Gem::Specification.reset
          successes, failures = results.partition { |r| r[:status] == 'installed' }

          if options[:json]
            out.json(bundles: selected, installed: successes, failed: failures,
                     already_present: installed.map { |g| { name: g, version: gem_version(g) } })
          else
            out.spacer
            if failures.empty?
              out.success("#{successes.size} gem(s) installed successfully")
            else
              out.error("#{failures.size} gem(s) failed to install")
              failures.each { |f| puts "  #{f[:name]}: #{f[:error]}" }
              out.spacer
              out.success("#{successes.size} gem(s) installed") unless successes.empty?
            end
            suggest_next_steps(out, selected)
          end
        end

        def install_gem(name, gem_bin, out)
          puts "  Installing #{name}..." unless options[:json]
          output = `#{gem_bin} install #{name} --no-document 2>&1`
          if $CHILD_STATUS.success?
            out.success("  #{name} installed") unless options[:json]
            { name: name, status: 'installed' }
          else
            out.error("  #{name} failed") unless options[:json]
            { name: name, status: 'failed', error: output.strip.lines.last&.strip }
          end
        end

        def suggest_next_steps(out, selected)
          out.spacer
          puts '  Next steps:'
          if selected.include?(:cognitive) || selected.include?(:ai)
            puts '    legion start          # full daemon with cognitive stack'
            puts '    legion start --lite   # single-process, no external services'
            puts '    legion chat           # interactive AI conversation'
          end
          puts '    legion features list   # verify installed bundles'
          puts '    legion doctor          # check environment health'
        end
      end
    end
  end
end
