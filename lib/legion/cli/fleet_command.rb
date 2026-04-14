# frozen_string_literal: true

require 'thor'
require_relative 'api_client'
require_relative 'output'
require_relative 'connection'

module Legion
  module CLI
    class FleetCommand < Thor
      def self.exit_on_failure?
        true
      end

      namespace 'fleet'

      class_option :json,     type: :boolean, default: false, desc: 'Output as JSON'
      class_option :no_color, type: :boolean, default: false, desc: 'Disable color output'

      desc 'status', 'Show fleet pipeline status (queue depths, active work items, workers)'
      def status
        out = formatter
        data = fetch_fleet_status

        if options[:json]
          out.json(data)
        else
          out.header('Fleet Pipeline Status')
          out.spacer

          puts "  Active work items: #{data[:active_work_items] || 0}"
          puts "  Workers:           #{data[:workers] || 0}"
          out.spacer

          if data[:queues]&.any?
            rows = data[:queues].map { |q| [q[:name], q[:depth].to_s] }
            out.table(%w[Queue Depth], rows)
          else
            puts '  No fleet queues found'
          end
        end
      end
      default_task :status

      desc 'pending', 'List work items awaiting human approval'
      option :limit, type: :numeric, default: 20, aliases: ['-n'], desc: 'Max items to show'
      def pending
        out = formatter
        items = fetch_pending_approvals

        if options[:json]
          out.json(items)
        elsif items.empty?
          puts '  No pending approvals'
        else
          out.header('Pending Approvals')
          rows = items.first(options[:limit]).map do |item|
            [item[:id].to_s, item[:source_ref].to_s, item[:title].to_s,
             item[:source].to_s, item[:created_at].to_s]
          end
          out.table(['ID', 'Source Ref', 'Title', 'Source', 'Created'], rows)
        end
      end

      desc 'approve ID', 'Approve a pending work item and resume the pipeline'
      def approve(id)
        out = formatter
        result = approve_work_item(id.to_i)

        if options[:json]
          out.json(result)
        elsif result[:success]
          out.success("Approved work item #{id} (#{result[:work_item_id]})")
          puts "  Pipeline resumed: #{result[:resumed]}"
        else
          out.error("Approval failed: #{result[:error]}")
          raise SystemExit, 1
        end
      end

      desc 'add SOURCE', 'Add a source to the fleet pipeline (e.g., github, slack)'
      option :owner, type: :string, desc: 'GitHub org/owner (for github source)'
      option :repo, type: :string, desc: 'GitHub repo name (for github source)'
      option :webhook_url, type: :string, desc: 'Webhook callback URL'
      def add(source)
        out = formatter
        result = add_fleet_source(source)

        if options[:json]
          out.json(result)
        elsif result[:success]
          out.success("Added #{source} as fleet source")
          puts "  Absorber: #{result[:absorber]}" if result[:absorber]
          puts "  Webhook:  #{result[:webhook_url]}" if result[:webhook_url]
          out.spacer
          puts '  The fleet will now process incoming events from this source.'
        else
          out.error("Failed to add source: #{result[:error]}")
          raise SystemExit, 1
        end
      end

      desc 'config', 'Show fleet configuration'
      def config
        out = formatter
        with_settings do
          fleet_settings = Legion::Settings[:fleet] || {}

          if options[:json]
            out.json(fleet_settings)
          else
            out.header('Fleet Configuration')
            out.spacer
            puts "  Enabled:  #{fleet_settings[:enabled] || false}"
            puts "  Sources:  #{(fleet_settings[:sources] || []).join(', ').then { |s| s.empty? ? 'none' : s }}"
            out.spacer

            puts '  Defaults:'
            puts "    Planning:       #{fleet_settings.dig(:planning, :enabled) ? 'enabled' : 'disabled'}"
            puts "    Validation:     #{fleet_settings.dig(:validation, :enabled) ? 'enabled' : 'disabled'}"
            puts "    Max iterations: #{fleet_settings.dig(:implementation, :max_iterations) || 5}"
            puts "    Validators:     #{fleet_settings.dig(:implementation, :validators) || 3}"
            puts "    Isolation:      #{fleet_settings.dig(:workspace, :isolation) || 'worktree'}"
          end
        end
      end

      no_commands do
        include ApiClient

        def formatter
          @formatter ||= Output::Formatter.new(json: options[:json], color: !options[:no_color])
        end

        private

        def fetch_fleet_status
          api_get('/api/fleet/status')
        rescue SystemExit
          { queues: [], active_work_items: 0, workers: 0 }
        end

        def fetch_pending_approvals
          api_get('/api/fleet/pending')
        rescue SystemExit
          []
        end

        def approve_work_item(id)
          api_post('/api/fleet/approve', id: id)
        end

        def add_fleet_source(source)
          payload = { source: source }
          payload[:owner] = options[:owner] if options[:owner]
          payload[:repo] = options[:repo] if options[:repo]
          payload[:webhook_url] = options[:webhook_url] if options[:webhook_url]
          api_post('/api/fleet/sources', **payload)
        end

        def with_settings
          Connection.config_dir = options[:config_dir] if options[:config_dir]
          Connection.log_level = 'error'
          Connection.ensure_settings
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
