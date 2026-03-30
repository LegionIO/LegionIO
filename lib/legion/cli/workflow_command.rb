# frozen_string_literal: true

require 'thor'

module Legion
  module CLI
    class Workflow < Thor
      def self.exit_on_failure?
        true
      end

      class_option :json, type: :boolean, default: false, desc: 'Output as JSON'
      class_option :no_color, type: :boolean, default: false, desc: 'Disable color output'
      class_option :config_dir, type: :string, desc: 'Config directory path'

      desc 'install FILE', 'Install a workflow from a YAML manifest'
      def install(file)
        out = formatter
        with_data do
          require 'legion/workflow/manifest'
          require 'legion/workflow/loader'

          unless File.exist?(file)
            out.error("File not found: #{file}")
            raise SystemExit, 1
          end

          manifest = Legion::Workflow::Manifest.new(path: file)
          unless manifest.valid?
            manifest.errors.each { |e| out.error(e) }
            raise SystemExit, 1
          end

          result = Legion::Workflow::Loader.new.install(manifest)

          if result[:success]
            if options[:json]
              out.json(result)
            else
              out.success("Workflow '#{manifest.name}' installed " \
                          "(chain_id=#{result[:chain_id]}, #{result[:relationship_ids].size} relationships)")
            end
          else
            out.error("Install failed: #{result[:error]}")
            raise SystemExit, 1
          end
        end
      end

      desc 'list', 'List installed workflows'
      def list
        out = formatter
        with_data do
          require 'legion/workflow/loader'

          workflows = Legion::Workflow::Loader.new.list
          if options[:json]
            out.json(workflows)
          else
            rows = workflows.map { |w| [w[:id].to_s, w[:name].to_s, w[:relationships].to_s] }
            out.table(%w[chain_id name relationships], rows)
          end
        end
      end
      default_task :list

      desc 'uninstall NAME', 'Uninstall a workflow by name'
      option :confirm, type: :boolean, default: false, aliases: ['-y'], desc: 'Skip confirmation'
      def uninstall(name)
        out = formatter
        with_data do
          require 'legion/workflow/loader'

          unless options[:confirm]
            out.warn("This will delete workflow '#{name}' and all its relationships")
            print '  Continue? [y/N] '
            response = $stdin.gets&.chomp
            unless response&.downcase == 'y'
              out.warn('Aborted')
              return
            end
          end

          result = Legion::Workflow::Loader.new.uninstall(name)

          if result[:success]
            out.success("Workflow '#{name}' uninstalled (#{result[:deleted_relationships]} relationships removed)")
          else
            out.error("Workflow '#{name}' not found")
            raise SystemExit, 1
          end
        end
      end

      desc 'status NAME', 'Show workflow chain details'
      def status(name)
        out = formatter
        with_data do
          require 'legion/workflow/loader'

          result = Legion::Workflow::Loader.new.status(name)

          if result[:success]
            if options[:json]
              out.json(result)
            else
              puts "Workflow: #{result[:name]} (chain_id=#{result[:chain_id]})"
              rows = result[:relationships].map do |r|
                [r[:id].to_s, r[:name].to_s, r[:trigger].to_s, r[:action].to_s,
                 r[:conditions] ? 'yes' : 'no', r[:active] ? 'active' : 'inactive']
              end
              out.table(%w[id name trigger action conditions active], rows)
            end
          else
            out.error("Workflow '#{name}' not found")
            raise SystemExit, 1
          end
        end
      end

      no_commands do
        def formatter
          @formatter ||= Output::Formatter.new(json: options[:json], color: !options[:no_color])
        end

        def with_data
          Connection.config_dir = options[:config_dir] if options[:config_dir]
          Connection.log_level = 'error'
          Connection.ensure_data
          yield
        rescue CLI::Error => e
          formatter.error(e.message)
          raise SystemExit, 1
        ensure
          Connection.shutdown
        end
      end
    end
  end
end
