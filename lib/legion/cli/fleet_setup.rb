# frozen_string_literal: true

require 'rbconfig'
require 'fileutils'

module Legion
  module CLI
    class FleetSetup
      FLEET_GEMS = %w[
        lex-assessor lex-planner lex-developer lex-validator
        lex-codegen lex-eval lex-exec
        lex-tasker lex-conditioner lex-transformer
        lex-audit lex-governance lex-agentic-social
      ].freeze

      MANIFEST_PATH = File.expand_path('../fleet/manifest.yml', __dir__)

      attr_reader :formatter, :options

      def initialize(formatter:, options:)
        @formatter = formatter
        @options = options
      end

      def self.fleet_gems
        FLEET_GEMS
      end

      def self.manifest_path
        MANIFEST_PATH
      end

      # Phase 1: Install gems. Extensions register themselves on next LegionIO start.
      def phase1_install
        formatter.header('Fleet Setup - Phase 1: Install') unless options[:json]

        installed, missing = partition_gems
        if missing.empty?
          formatter.success('All fleet gems already installed') unless options[:json]
          return { success: true, installed: installed.size, skipped: 0 }
        end

        result = install_gems(missing)
        if result[:failed].positive?
          formatter.error("#{result[:failed]} gem(s) failed to install") unless options[:json]
          return { success: false, error: :install_failed, **result }
        end

        formatter.success("Phase 1 complete: #{result[:installed]} gem(s) installed") unless options[:json]
        { success: true, **result }
      end

      # Phase 2: Wire relationships, seed rules, register settings.
      # Requires that extensions have been loaded and registered (LexRegister).
      def phase2_wire
        formatter.header('Fleet Setup - Phase 2: Wire') unless options[:json]

        require 'legion/workflow/manifest'
        require 'legion/workflow/loader'

        manifest = Legion::Workflow::Manifest.new(path: MANIFEST_PATH)
        unless manifest.valid?
          formatter.error("Invalid manifest: #{manifest.errors.join(', ')}") unless options[:json]
          return { success: false, error: :invalid_manifest, errors: manifest.errors }
        end

        loader_result = Legion::Workflow::Loader.new.install(manifest)
        unless loader_result[:success]
          formatter.error("Relationship install failed: #{loader_result[:error]}") unless options[:json]
          return { success: false, error: :relationship_install_failed, detail: loader_result }
        end

        apply_planner_timeout_policy
        rules_result = seed_conditioner_rules
        settings_result = register_settings

        unless options[:json]
          formatter.success(
            "Phase 2 complete: chain_id=#{loader_result[:chain_id]}, " \
            "#{loader_result[:relationship_ids].size} relationships"
          )
        end

        {
          success:       true,
          chain_id:      loader_result[:chain_id],
          relationships: loader_result[:relationship_ids].size,
          rules:         rules_result,
          settings:      settings_result
        }
      end

      private

      def partition_gems
        installed = []
        missing = []
        FLEET_GEMS.each do |name|
          Gem::Specification.find_by_name(name)
          installed << name
        rescue Gem::MissingSpecError
          missing << name
        end
        [installed, missing]
      end

      def install_gems(gems = nil)
        gems ||= partition_gems.last
        gem_bin = File.join(RbConfig::CONFIG['bindir'], 'gem')
        installed = 0
        failed = 0

        gems.each do |name|
          formatter.spacer unless options[:json]
          puts "  Installing #{name}..." unless options[:json]
          output = `#{gem_bin} install #{name} --no-document 2>&1`
          if $CHILD_STATUS&.success?
            installed += 1
          else
            failed += 1
            formatter.error("  #{name} failed: #{output.strip.lines.last&.strip}") unless options[:json]
          end
        end

        { installed: installed, failed: failed }
      end

      # Apply RabbitMQ consumer timeout policy for planner queue.
      # The planner queue needs a longer consumer timeout for LLM plan generation.
      # Default RabbitMQ consumer timeout is 30min; planner may need up to 60min.
      def apply_planner_timeout_policy
        system(
          'rabbitmqctl', 'set_policy', 'fleet-timeout',
          '^lex\\.planner\\.', '{"consumer-timeout": 3600000}',
          '--apply-to', 'queues'
        )
        formatter.success('Applied planner queue timeout policy (60min)') unless options[:json]
      rescue StandardError => e
        formatter.warn("Planner timeout policy skipped: #{e.message}") unless options[:json]
      end

      # Register fleet settings and LLM routing overrides via load_module_settings.
      # This uses the Loader's internal deep_merge and mark_dirty! automatically.
      def register_settings
        require 'legion/fleet/settings'
        Legion::Fleet::Settings.apply!
        { success: true }
      rescue StandardError => e
        formatter.warn("Settings registration skipped: #{e.message}") unless options[:json]
        { success: false, error: e.message }
      end

      def seed_conditioner_rules
        require 'legion/fleet/conditioner_rules'
        Legion::Fleet::ConditionerRules.seed!
      rescue StandardError => e
        formatter.warn("Conditioner rules seeding skipped: #{e.message}") unless options[:json]
        { success: false, error: e.message }
      end
    end
  end
end
