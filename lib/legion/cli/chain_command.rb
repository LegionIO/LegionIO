# frozen_string_literal: true

module Legion
  module CLI
    class Chain < Thor
      def self.exit_on_failure?
        true
      end

      class_option :json, type: :boolean, default: false, desc: 'Output as JSON'
      class_option :no_color, type: :boolean, default: false, desc: 'Disable color output'
      class_option :config_dir, type: :string, desc: 'Config directory path'

      desc 'list', 'List task chains'
      option :limit, type: :numeric, default: 20, aliases: ['-n'], desc: 'Number of chains to show'
      def list
        out = formatter
        with_data do
          rows = Legion::Data::Model::Chain
                 .order(Sequel.desc(:id))
                 .limit(options[:limit])
                 .map do |row|
            v = row.values
            active_str = v[:active] ? out.status('enabled') : out.status('disabled')
            [v[:id].to_s, v[:name].to_s, active_str]
          end

          out.table(%w[id name active], rows)
        end
      end
      default_task :list

      desc 'create NAME', 'Create a new task chain'
      def create(name)
        out = formatter
        with_data do
          id = Legion::Data::Model::Chain.insert(name: name)

          if options[:json]
            out.json(id: id, name: name)
          else
            out.success("Chain created: ##{id} (#{name})")
          end
        end
      end

      desc 'delete ID', 'Delete a chain and its relationships'
      option :confirm, type: :boolean, default: false, aliases: ['-y'], desc: 'Skip confirmation'
      def delete(id)
        out = formatter
        with_data do
          chain = Legion::Data::Model::Chain[id.to_i]
          unless chain
            out.error("Chain #{id} not found")
            raise SystemExit, 1
          end

          unless options[:confirm]
            out.warn("This will delete chain '#{chain.values[:name]}' and all dependent relationships")
            print '  Continue? [y/N] '
            response = $stdin.gets&.chomp
            unless response&.downcase == 'y'
              out.warn('Aborted')
              return
            end
          end

          chain.delete
          out.success("Chain ##{id} deleted")
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
