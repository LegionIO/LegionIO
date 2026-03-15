# frozen_string_literal: true

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
        with_data do
          require_scheduler!
          ds = Legion::Extensions::Scheduler::Data::Model::Schedule.dataset
          ds = ds.where(active: true) if options[:active]
          schedules = ds.limit(options[:limit]).all

          if options[:json]
            out.json(schedules.map(&:values))
          else
            rows = schedules.map do |s|
              [s[:id], s[:function_id] || '-', s[:cron] || s[:interval] || '-',
               out.status(s[:active] ? 'active' : 'inactive'), s[:description] || '-']
            end
            out.table(%w[ID Function Schedule Status Description], rows)
            puts "  #{schedules.size} schedule(s)"
          end
        end
      end
      default_task :list

      desc 'show ID', 'Show schedule details'
      def show(id)
        out = formatter
        with_data do
          require_scheduler!
          schedule = Legion::Extensions::Scheduler::Data::Model::Schedule[id.to_i]
          unless schedule
            out.error("Schedule not found: #{id}")
            return
          end

          if options[:json]
            out.json(schedule.values)
          else
            out.header("Schedule ##{id}")
            out.spacer
            out.detail(schedule.values.transform_keys(&:to_s))
          end
        end
      end

      desc 'add', 'Create a new schedule'
      option :function_id, type: :numeric, required: true, desc: 'Function ID to schedule'
      option :cron, type: :string, desc: 'Cron expression (e.g., "0 * * * *")'
      option :interval, type: :numeric, desc: 'Interval in seconds'
      option :description, type: :string, desc: 'Schedule description'
      def add
        out = formatter
        with_data do
          require_scheduler!
          attrs = { function_id: options[:function_id], active: true, created_at: Time.now.utc }
          attrs[:cron] = options[:cron] if options[:cron]
          attrs[:interval] = options[:interval] if options[:interval]
          attrs[:description] = options[:description] if options[:description]

          unless attrs[:cron] || attrs[:interval]
            out.error('Either --cron or --interval is required')
            return
          end

          id = Legion::Extensions::Scheduler::Data::Model::Schedule.insert(attrs)
          if options[:json]
            out.json({ id: id, created: true })
          else
            out.success("Schedule ##{id} created")
          end
        end
      end

      desc 'remove ID', 'Delete a schedule'
      option :yes, type: :boolean, default: false, aliases: '-y', desc: 'Skip confirmation'
      def remove(id)
        out = formatter
        with_data do
          require_scheduler!
          schedule = Legion::Extensions::Scheduler::Data::Model::Schedule[id.to_i]
          unless schedule
            out.error("Schedule not found: #{id}")
            return
          end

          unless options[:yes]
            print "Delete schedule ##{id}? [y/N] "
            return unless $stdin.gets&.strip&.downcase == 'y'
          end

          schedule.delete
          if options[:json]
            out.json({ id: id.to_i, deleted: true })
          else
            out.success("Schedule ##{id} deleted")
          end
        end
      end

      desc 'logs ID', 'Show schedule run logs'
      option :limit, type: :numeric, default: 20, desc: 'Max results'
      def logs(id)
        out = formatter
        with_data do
          require_scheduler!
          schedule = Legion::Extensions::Scheduler::Data::Model::Schedule[id.to_i]
          unless schedule
            out.error("Schedule not found: #{id}")
            return
          end

          log_entries = Legion::Extensions::Scheduler::Data::Model::ScheduleLog
                        .where(schedule_id: id.to_i)
                        .order(Sequel.desc(:id))
                        .limit(options[:limit]).all

          if options[:json]
            out.json(log_entries.map(&:values))
          else
            out.header("Logs for Schedule ##{id}")
            if log_entries.empty?
              puts '  No logs found.'
            else
              rows = log_entries.map { |l| [l[:id], l[:status] || '-', l[:started_at]&.to_s || '-', l[:message] || '-'] }
              out.table(%w[ID Status Started Message], rows)
            end
          end
        end
      end

      no_commands do
        def formatter
          @formatter ||= Output::Formatter.new(
            json:  options[:json],
            color: !options[:no_color]
          )
        end

        def with_data
          Connection.config_dir = options[:config_dir] if options[:config_dir]
          Connection.log_level = options[:verbose] ? 'debug' : 'error'
          Connection.ensure_data
          yield
        rescue CLI::Error => e
          formatter.error(e.message)
          raise SystemExit, 1
        ensure
          Connection.shutdown
        end

        def require_scheduler!
          return if defined?(Legion::Extensions::Scheduler::Data::Model::Schedule)

          raise CLI::Error, 'lex-scheduler extension is not loaded. Install and enable it first.'
        end
      end
    end
  end
end
