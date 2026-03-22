# frozen_string_literal: true

module Legion
  module CLI
    class Task < Thor
      def self.exit_on_failure?
        true
      end

      class_option :json, type: :boolean, default: false, desc: 'Output as JSON'
      class_option :no_color, type: :boolean, default: false, desc: 'Disable color output'
      class_option :verbose, type: :boolean, default: false, aliases: ['-V'], desc: 'Verbose logging'
      class_option :config_dir, type: :string, desc: 'Config directory path'

      desc 'list', 'List recent tasks'
      option :limit, type: :numeric, default: 20, aliases: ['-n'], desc: 'Number of tasks to return'
      option :status, type: :string, aliases: ['-s'], desc: 'Filter by status (e.g. completed, failed, queued)'
      option :extension, type: :string, aliases: ['-e'], desc: 'Filter by extension name'
      def list
        out = formatter
        with_data do
          dataset = Legion::Data::Model::Task.order(Sequel.desc(:id)).limit(options[:limit])
          dataset = dataset.where(Sequel.like(:status, "%#{options[:status]}%")) if options[:status]

          rows = dataset.map do |row|
            v = row.values
            [
              v[:id].to_s,
              v[:function_id].to_s,
              out.status(short_status(v[:status])),
              format_time(v[:created]),
              (v[:relationship_id] || '-').to_s
            ]
          end

          out.table(%w[id function status created relationship], rows)
        end
      end
      default_task :list

      desc 'show ID', 'Show task details'
      def show(id)
        out = formatter
        with_data do
          task = Legion::Data::Model::Task[id.to_i]
          unless task
            out.error("Task #{id} not found")
            raise SystemExit, 1
          end

          v = task.values
          if options[:json]
            out.json(v)
            return
          end

          out.header("Task ##{v[:id]}")
          out.spacer
          out.detail({
                       id:              v[:id],
                       status:          v[:status],
                       function_id:     v[:function_id],
                       relationship_id: v[:relationship_id],
                       runner_id:       v[:runner_id],
                       created:         v[:created],
                       updated:         v[:updated],
                       parent_id:       v[:parent_id],
                       master_id:       v[:master_id]
                     })

          if v[:args] && !v[:args].to_s.empty?
            out.spacer
            out.header('Arguments')
            begin
              args = Legion::JSON.load(v[:args])
              out.detail(args)
            rescue StandardError => e
              Legion::Logging.debug("TaskCommand#show args parse failed: #{e.message}") if defined?(Legion::Logging)
              puts "  #{v[:args]}"
            end
          end
        end
      end

      desc 'logs ID', 'Show task execution logs'
      option :limit, type: :numeric, default: 50, aliases: ['-n'], desc: 'Number of log entries'
      def logs(id)
        out = formatter
        with_data do
          rows = Legion::Data::Model::TaskLog
                 .where(task_id: id.to_i)
                 .order(Sequel.desc(:id))
                 .limit(options[:limit])
                 .map do |row|
            v = row.values
            [
              v[:id].to_s,
              (v[:node_id] || '-').to_s,
              format_time(v[:created]),
              v[:entry].to_s
            ]
          end

          if rows.empty?
            out.warn("No logs found for task #{id}")
          else
            out.table(%w[id node created entry], rows)
          end
        end
      end

      desc 'trigger FUNCTION', 'Trigger a task directly'
      long_desc <<~DESC
        Run a function directly by specifying it as extension.runner.function
        or interactively select from available options.

        Examples:
          legion task run http.request.get url:https://example.com
          legion task run --extension http --runner request --function get
          legion task run  (interactive mode)
      DESC
      option :extension, type: :string, aliases: ['-e'], desc: 'Extension name'
      option :runner, type: :string, aliases: ['-r'], desc: 'Runner name'
      option :function, type: :string, aliases: ['-f'], desc: 'Function name'
      option :delay, type: :numeric, default: 0, desc: 'Delay execution by N seconds'
      map 'run' => :trigger
      def trigger(function_spec = nil, *args)
        out = formatter
        with_data do
          with_transport do
            target = resolve_target(function_spec, out)
            payload = parse_args(args, target[:function_args], out)

            result = execute_task(target, payload, out)

            if options[:json]
              out.json(result)
            else
              out.spacer
              out.success("Task #{result[:task_id]} #{result[:status]}")
            end
          end
        end
      end

      desc 'purge', 'Delete old tasks'
      option :days, type: :numeric, default: 7, desc: 'Keep tasks newer than N days'
      option :confirm, type: :boolean, default: false, aliases: ['-y'], desc: 'Skip confirmation'
      def purge
        out = formatter
        with_data do
          cutoff = DateTime.now - options[:days]
          dataset = Legion::Data::Model::Task.where { created < cutoff }
          count = dataset.count

          if count.zero?
            out.success('No tasks to purge')
            return
          end

          unless options[:confirm]
            out.warn("This will delete #{count} tasks older than #{options[:days]} days")
            print '  Continue? [y/N] '
            response = $stdin.gets&.chomp
            unless response&.downcase == 'y'
              out.warn('Aborted')
              return
            end
          end

          dataset.delete
          out.success("Purged #{count} tasks")
        end
      end

      no_commands do # rubocop:disable Metrics/BlockLength
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

        def with_transport
          Connection.ensure_transport
          yield
        end

        def short_status(status)
          return status unless status.is_a?(String)

          status.sub('task.', '')
        end

        def format_time(time)
          return '-' if time.nil?

          time.strftime('%Y-%m-%d %H:%M:%S')
        rescue StandardError => e
          Legion::Logging.debug("TaskCommand#format_time failed: #{e.message}") if defined?(Legion::Logging)
          time.to_s
        end

        def resolve_target(function_spec, out) # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/MethodLength,Metrics/PerceivedComplexity
          # Parse dot-notation: extension.runner.function
          if function_spec&.include?('.')
            parts = function_spec.split('.')
            ext_name = parts[0]
            runner_name = parts[1]
            func_name = parts[2]
          else
            ext_name = options[:extension] || function_spec
            runner_name = options[:runner]
            func_name = options[:function]
          end

          # Interactive fallback for extension
          if ext_name.nil?
            extensions = Legion::Data::Model::Extension.map(:name)
            out.header('Available Extensions')
            extensions.each_with_index { |e, i| puts "  #{i + 1}. #{e}" }
            print '  Select extension: '
            choice = $stdin.gets&.chomp
            ext_name = choice.match?(/^\d+$/) ? extensions[choice.to_i - 1] : choice
          end

          extension = Legion::Data::Model::Extension.where(name: ext_name).first
          raise CLI::Error, "Extension '#{ext_name}' not found in database" unless extension

          # Resolve runner
          runners = Legion::Data::Model::Runner.where(extension_id: extension.values[:id])
          if runner_name
            trigger_runner = runners.where(name: runner_name).first
          elsif runners.one?
            trigger_runner = runners.first
            out.success("Auto-selected runner: #{trigger_runner.values[:name]}") unless options[:json]
          else
            out.header('Available Runners')
            runners.each_with_index { |r, i| puts "  #{i + 1}. #{r.values[:name]}" }
            print '  Select runner: '
            choice = $stdin.gets&.chomp
            runner_name = choice.match?(/^\d+$/) ? runners.all[choice.to_i - 1].values[:name] : choice
            trigger_runner = runners.where(name: runner_name).first
          end
          raise CLI::Error, "Runner '#{runner_name}' not found" unless trigger_runner

          # Resolve function
          functions = Legion::Data::Model::Function.where(runner_id: trigger_runner.values[:id])
          if func_name
            trigger_function = functions.where(name: func_name).first
          elsif functions.one?
            trigger_function = functions.first
            out.success("Auto-selected function: #{trigger_function.values[:name]}") unless options[:json]
          else
            out.header('Available Functions')
            functions.each_with_index { |f, i| puts "  #{i + 1}. #{f.values[:name]}" }
            print '  Select function: '
            choice = $stdin.gets&.chomp
            func_name = choice.match?(/^\d+$/) ? functions.all[choice.to_i - 1].values[:name] : choice
            trigger_function = functions.where(name: func_name).first
          end
          raise CLI::Error, "Function '#{func_name}' not found" unless trigger_function

          function_args = begin
            Legion::JSON.load(trigger_function.values[:args])
          rescue StandardError => e
            Legion::Logging.warn("TaskCommand#resolve_target failed to parse function args: #{e.message}") if defined?(Legion::Logging)
            {}
          end

          {
            extension:     extension,
            runner:        trigger_runner,
            function:      trigger_function,
            function_args: function_args
          }
        end

        def parse_args(cli_args, function_args, _out)
          payload = {}

          # Parse key:value pairs from command line
          inline = {}
          cli_args.each do |arg|
            key, value = arg.split(':', 2)
            inline[key.to_sym] = value if key && value
          end

          function_args.each do |arg_name, required|
            next if %w[args payload opts options].include?(arg_name.to_s)

            if inline.key?(arg_name.to_sym)
              payload[arg_name.to_sym] = inline[arg_name.to_sym]
              next
            end

            next if options[:json] # interactive mode

            req_label = required == 'keyreq' ? '(required)' : '(optional)'
            print "  #{arg_name} #{req_label}: "
            response = $stdin.gets&.chomp

            if response.nil? || response.empty?
              raise CLI::Error, "#{arg_name} is required" if required == 'keyreq'

              next
            end
            payload[arg_name.to_sym] = response
          end

          payload
        end

        def execute_task(target, payload, _out)
          include Legion::Extensions::Helpers::Task

          ext = target[:extension]
          runner = target[:runner]
          func = target[:function]

          status = options[:delay].positive? ? 'task.delayed' : 'task.queued'
          task = generate_task_id(
            function_id: func.values[:id],
            status:      status,
            runner_id:   runner.values[:id],
            args:        payload,
            delay:       options[:delay]
          )

          return { task_id: task[:task_id], status: 'delayed', delay: options[:delay] } if options[:delay].positive?

          routing_key = "#{ext.values[:exchange]}.#{runner.values[:queue]}.#{func.values[:name]}"
          message = Legion::Transport::Messages::Dynamic.new(
            function:    func.values[:name],
            function_id: func.values[:id],
            routing_key: routing_key,
            args:        payload
          )
          message.options[:task_id] = task[:task_id]
          message.publish

          { task_id: task[:task_id], status: 'queued', routing_key: routing_key }
        end
      end
    end
  end
end
