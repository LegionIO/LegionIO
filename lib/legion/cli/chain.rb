# frozen_string_literal: true

module Legion
  class Cli
    class Chain < Thor
      desc 'create', 'create'
      def create(name)
        Legion::Service.new(cache: false, crypt: false, extensions: false, log_level: 'error')
        say "chain created, id: #{Legion::Data::Model::Chain.insert({ name: name })}", :green
      end

      desc 'show', 'show'
      option :limit, type: :numeric, required: true, default: 10, desc: 'how many tasks to return'
      def show
        Legion::Service.new(cache: false, crypt: false, extensions: false, log_level: 'error')
        rows = [%w[id name active]]
        Legion::Data::Model::Chain.limit(options[:limit]).order(:id).reverse_each do |row|
          rows.push([row.values[:id], row.values[:name], row.values[:active]])
        end

        print_table rows
      end

      desc 'delete', 'delete'
      option :confirm, type: :boolean
      def delete(id)
        Legion::Service.new(cache: false, crypt: false, extensions: false, log_level: 'error')
        return if !options[:confirm] && !(yes? "Are you sure you want to delete chain #{id} and all dependent relationships", :red)

        Legion::Data::Model::Chain[id].delete
        say 'Deleted!'
      end

      default_task :show
    end
  end
end
