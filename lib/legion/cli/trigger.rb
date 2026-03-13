# frozen_string_literal: true

module Legion
  class Cli
    class Trigger < Thor
      desc 'queue', 'used to send a job directly to a worker via Legion::Transport'
      option :extension, type: :string, required: false, desc: 'extension short name'
      option :runner, type: :string, required: false, desc: 'runner short name'
      option :function, type: :string, required: false, desc: 'function short name'
      option :delay, type: :numeric, default: 0, desc: 'how long to wait before running the task'
      def queue(*args) # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity,Metrics/MethodLength
        Legion::Service.new(cache: false, crypt: false, extensions: false, log_level: 'error')
        include Legion::Extensions::Helpers::Task

        response = if options['extension'].is_a? String
                     options[:extension]
                   else
                     ask 'trigger extension?', limited_to: Legion::Data::Model::Extension.map(:name)
                   end
        trigger_extension = Legion::Data::Model::Extension.where(name: response).first
        runners = Legion::Data::Model::Runner.where(extension_id: trigger_extension.values[:id])
        if runners.one?
          trigger_runner = runners.first
          say "Auto selecting #{trigger_runner.values[:name]} since it is the only option for runners"
        else
          response = options[:runner].is_a?(String) ? options[:runner] : ask('trigger runner?', limited_to: runners.map(:name))
          trigger_runner = Legion::Data::Model::Runner.where(name: response).where(extension_id: trigger_extension.values[:id]).first
        end

        functions = Legion::Data::Model::Function.where(runner_id: trigger_runner.values[:id])

        if functions.one?
          trigger_function = functions.first
          say "Auto selecting #{trigger_function.values[:name]} since it is the only option for functions"
        else
          response = if options[:function].is_a?(String)
                       options[:function]
                     else
                       ask('trigger function?',
                           limited_to: Legion::Data::Model::Function.where(runner_id: trigger_runner.values[:id]).map(:name))
                     end
          trigger_function = Legion::Data::Model::Function.where(runner_id: trigger_runner.values[:id]).where(name: response).first
        end
        say "#{trigger_runner.values[:namespace]}.#{trigger_function.values[:name]} selected as trigger", :green, :italicized
        payload = {}
        auto_opts = {}
        unless args.none?
          args.each do |arg|
            test = arg.split(':')
            auto_opts[test[0].to_sym] = test[1]
          end
        end

        Legion::JSON.load(trigger_function.values[:args]).each do |arg, required|
          next if %w[args payload opts options].include? arg.to_s

          if auto_opts.key? arg
            payload[arg.to_sym] = auto_opts[arg]
            next
          end
          response = ask "#{required == 'keyreq' ? '[required]' : '[optional]'} #{arg} value:"
          if response.empty? && required == 'keyreq'
            say "Error! #{arg} is required and cannot be empty", :red
            redo
          end
          payload[arg.to_sym] = response unless response.empty?
        end

        status = options[:delay].zero? ? 'task.queued' : 'task.delayed'
        task = generate_task_id(function_id: trigger_function.values[:id], status: status, runner_id: trigger_runner.values[:id], args: payload,
                                delay: options[:delay])

        unless options[:delay].zero?
          say "Task: #{task[:task_id]} is queued and will be run in #{options[:delay]}s"
          return true
        end

        routing_key = "#{trigger_extension.values[:exchange]}.#{trigger_runner.values[:queue]}.#{trigger_function.values[:name]}"
        exchange = Legion::Transport::Messages::Dynamic.new(function: trigger_function.values[:name], function_id: trigger_function.values[:id],
                                                            routing_key: routing_key, args: payload)
        exchange.options[:task_id] = task[:task_id]
        exchange.publish if options[:delay].zero?

        say "Task: #{task[:task_id]} was queued"
      end
      remove_command :generate_task_id

      default_task :queue
    end
  end
end
