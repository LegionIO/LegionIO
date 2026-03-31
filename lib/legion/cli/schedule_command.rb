# frozen_string_literal: true

require_relative 'api_client'

module Legion
  module CLI
    class Schedule < Thor
      def self.exit_on_failure?
        true
      end

      class_option :json,       type: :boolean, default: false, desc: 'Output as JSON'
      class_option :no_color,   type: :boolean, default: false, desc: 'Disable color output'
      class_option :verbose,    type: :boolean, default: false, aliases: ['-V'], desc: 'Verbose logging'
      class_option :config_dir, type: :string, desc: 'Config directory path'

      desc 'list', 'List schedules'
      option :active, type: :boolean, default: false, desc: 'Show only active schedules'
      option :limit, type: :numeric, default: 20, desc: 'Max results'
      def list
        out = formatter
        query = "/api/schedules?limit=#{options[:limit]}"
        query += '&active=true' if options[:active]
        schedules = api_get(query)
        schedules = [] if schedules.nil?

        if options[:json]
          out.json(schedules)
        else
          rows = Array(schedules).map do |s|
            [s[:id], s[:function_id] || '-', s[:cron] || s[:interval] || '-',
             out.status(s[:active] ? 'active' : 'inactive'), s[:description] || '-']
          end
          out.table(%w[ID Function Schedule Status Description], rows)
          puts "  #{rows.size} schedule(s)"
        end
      end
      default_task :list

      desc 'show ID', 'Show schedule details'
      def show(id)
        out = formatter
        schedule = api_get("/api/schedules/#{id}")

        if options[:json]
          out.json(schedule)
        else
          out.header("Schedule ##{id}")
          out.spacer
          out.detail(schedule.transform_keys(&:to_s))
        end
      end

      desc 'add', 'Create a new schedule'
      option :function_id, type: :numeric, required: true, desc: 'Function ID to schedule'
      option :cron, type: :string, desc: 'Cron expression (e.g., "0 * * * *")'
      option :interval, type: :numeric, desc: 'Interval in seconds'
      option :description, type: :string, desc: 'Schedule description'
      def add
        out = formatter

        unless options[:cron] || options[:interval]
          out.error('Either --cron or --interval is required')
          return
        end

        payload = { function_id: options[:function_id], active: true }
        payload[:cron] = options[:cron] if options[:cron]
        payload[:interval] = options[:interval] if options[:interval]
        payload[:description] = options[:description] if options[:description]

        result = api_post('/api/schedules', **payload)
        if options[:json]
          out.json(result)
        else
          out.success("Schedule ##{result[:id]} created")
        end
      end

      desc 'remove ID', 'Delete a schedule'
      option :yes, type: :boolean, default: false, aliases: '-y', desc: 'Skip confirmation'
      def remove(id)
        out = formatter

        unless options[:yes]
          print "Delete schedule ##{id}? [y/N] "
          return unless $stdin.gets&.strip&.downcase == 'y'
        end

        result = api_delete("/api/schedules/#{id}")
        if options[:json]
          out.json({ id: id.to_i, deleted: true }.merge(result || {}))
        else
          out.success("Schedule ##{id} deleted")
        end
      end

      desc 'logs ID', 'Show schedule run logs'
      option :limit, type: :numeric, default: 20, desc: 'Max results'
      def logs(id)
        out = formatter
        log_entries = api_get("/api/schedules/#{id}/logs?limit=#{options[:limit]}")
        log_entries = [] if log_entries.nil?

        if options[:json]
          out.json(log_entries)
        else
          out.header("Logs for Schedule ##{id}")
          if Array(log_entries).empty?
            puts '  No logs found.'
          else
            rows = Array(log_entries).map do |l|
              [l[:id], l[:status] || '-', l[:started_at]&.to_s || '-', l[:message] || '-']
            end
            out.table(%w[ID Status Started Message], rows)
          end
        end
      end

      no_commands do
        include ApiClient

        def formatter
          @formatter ||= Output::Formatter.new(
            json:  options[:json],
            color: !options[:no_color]
          )
        end
      end
    end
  end
end
