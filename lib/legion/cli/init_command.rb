# frozen_string_literal: true

require 'thor'

module Legion
  module CLI
    class Init < Thor
      def self.exit_on_failure?
        true
      end

      desc 'workspace', 'Initialize a new Legion workspace in the current directory'
      option :askid, type: :string, desc: 'ASK ID for the deployment'
      option :local, type: :boolean, default: false, desc: 'Local dev mode (no external dependencies)'
      option :force, type: :boolean, default: false, desc: 'Overwrite existing config files'
      def workspace
        detect_environment
        generate_config
        scaffold_workspace
        verify_setup
      end
      default_task :workspace

      private

      def detect_environment
        require 'legion/cli/init/environment_detector'
        @env = InitHelpers::EnvironmentDetector.detect
        say 'Environment detected:', :green
        @env.each { |k, v| say "  #{k}: #{v[:available] ? 'available' : 'not found'}" }
      end

      def generate_config
        require 'legion/cli/init/config_generator'
        opts = options.to_h.transform_keys(&:to_sym)
        opts[:redis] = @env[:redis][:available]

        files = InitHelpers::ConfigGenerator.generate(opts)
        if files.empty?
          say '  Config files already exist (use --force to overwrite)', :yellow
        else
          files.each { |f| say "  Created: #{f}", :green }
        end
      end

      def scaffold_workspace
        require 'legion/cli/init/config_generator'
        dir = InitHelpers::ConfigGenerator.scaffold_workspace
        say "  Workspace scaffolded: #{dir}", :green
      end

      def verify_setup
        say "\nVerifying setup...", :yellow
        say "Run 'legion doctor' to check environment health", :cyan
      end
    end
  end
end
