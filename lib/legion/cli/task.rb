# frozen_string_literal: true

module Legion
  class Cli
    class Task < Thor
      package_name 'Legion'

      option :limit, type: :numeric, required: true, default: 10, desc: 'how many tasks to return'
      desc 'show', 'show'
      option :status, type: :string, required: false, desc: 'search for specific status'
      def show
        Legion::Service.new(cache: false, crypt: false, extensions: false, log_level: 'error')
        rows = [%w[id relationship function status]]
        Legion::Data::Model::Task.limit(options[:limit]).order(:id).reverse_each do |row|
          rows.push([row.values[:id], row.values[:relationship_id], row.values[:function_id], row.values[:status]])
        end

        print_table rows
      end

      desc 'test', 'test'
      def status(id)
        Legion::Service.new(cache: false, crypt: false, extensions: false, log_level: 'error')
        say Legion::Data::Model::Task[id].values
      end

      desc 'logs', 'logs'
      option :limit, type: :numeric, required: true, default: 10, desc: 'how many tasks to return'
      def logs(id)
        Legion::Service.new(cache: false, crypt: false, extensions: false, log_level: 'error')
        rows = [%w[id node_id created entry]]
        Legion::Data::Model::TaskLog.where(task_id: id).limit(options[:limit]).each do |row|
          rows.push([row.values[:id], row.values[:node_id], row.values[:created], row.values[:entry]])
        end
        print_table rows
      end

      desc 'purge', 'purge'
      def purge
        Legion::Service.new(cache: false, crypt: false, extensions: false, log_level: 'error')
        days = ask 'how many days do you want to keep?', default: 7
        dataset = Legion::Data::Model::Task.where { created < DateTime.now - days.to_i }
        yes? "This will delete #{dataset.count} tasks, continue?", :red
        dataset.delete
        say 'Done!'
      end

      default_task :show
    end
  end
end
