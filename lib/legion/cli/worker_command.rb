# frozen_string_literal: true

module Legion
  module CLI
    class Worker < Thor
      def self.exit_on_failure?
        true
      end

      class_option :json,     type: :boolean, default: false, desc: 'Output as JSON'
      class_option :no_color, type: :boolean, default: false, desc: 'Disable color output'
      class_option :verbose,  type: :boolean, default: false, aliases: ['-V'], desc: 'Verbose logging'
      class_option :config_dir, type: :string, desc: 'Config directory path'

      desc 'list', 'List digital workers'
      option :team,  type: :string,  desc: 'Filter by team'
      option :owner, type: :string,  desc: 'Filter by owner MSID'
      option :state, type: :string,  desc: 'Filter by lifecycle state'
      option :limit, type: :numeric, default: 20, desc: 'Max results'
      def list
        out = formatter
        with_data do
          ds = Legion::Data::Model::DigitalWorker.dataset

          ds = ds.where(team: options[:team])               if options[:team]
          ds = ds.where(owner_msid: options[:owner])        if options[:owner]
          ds = ds.where(lifecycle_state: options[:state])   if options[:state]

          workers = ds.limit(options[:limit]).all

          if options[:json]
            out.json(workers.map(&:to_hash))
          else
            rows = workers.map do |w|
              [w.worker_id[0..7], w.name, out.status(w.lifecycle_state), w.consent_tier, w.owner_msid, w.team || '-']
            end
            out.table(%w[ID Name State Consent Owner Team], rows)
            puts "  #{workers.size} worker(s)"
          end
        end
      end
      default_task :list

      desc 'show WORKER_ID', 'Show digital worker details'
      def show(worker_id)
        out = formatter
        with_data do
          worker = find_worker(worker_id)

          unless worker
            out.error("Worker not found: #{worker_id}")
            return
          end

          if options[:json]
            out.json(worker.to_hash)
          else
            out.header("Worker: #{worker.name}")
            out.spacer
            out.detail(
              'Worker ID'       => worker.worker_id,
              'Name'            => worker.name,
              'Extension'       => worker.extension_name,
              'Entra App ID'    => worker.entra_app_id,
              'Owner MSID'      => worker.owner_msid,
              'Owner Name'      => worker.owner_name || '-',
              'Lifecycle State' => worker.lifecycle_state,
              'Consent Tier'    => worker.consent_tier,
              'Trust Score'     => worker.trust_score.to_s,
              'Risk Tier'       => worker.risk_tier || '-',
              'Team'            => worker.team || '-',
              'Manager'         => worker.manager_msid || '-',
              'Created'         => worker.created_at.to_s,
              'Updated'         => worker.updated_at&.to_s || '-'
            )
          end
        end
      end

      desc 'pause WORKER_ID', 'Pause a digital worker'
      option :reason, type: :string, desc: 'Reason for pausing'
      def pause(worker_id)
        with_data { transition_worker(worker_id, 'paused', options[:reason]) }
      end

      desc 'retire WORKER_ID', 'Retire a digital worker'
      option :reason, type: :string, desc: 'Reason for retiring'
      def retire(worker_id)
        with_data { transition_worker(worker_id, 'retired', options[:reason]) }
      end

      desc 'terminate WORKER_ID', 'Terminate a digital worker (irreversible)'
      option :reason, type: :string, desc: 'Reason for termination'
      option :yes, type: :boolean, default: false, aliases: '-y', desc: 'Skip confirmation'
      def terminate(worker_id)
        out = formatter
        unless options[:yes]
          out.warn('This action is IRREVERSIBLE.')
          print "Type 'yes' to confirm termination: "
          return unless $stdin.gets&.strip == 'yes'
        end
        with_data { transition_worker(worker_id, 'terminated', options[:reason]) }
      end

      desc 'activate WORKER_ID', 'Activate a worker (from bootstrap or paused)'
      def activate(worker_id)
        with_data { transition_worker(worker_id, 'active', nil) }
      end

      desc 'costs WORKER_ID', 'Show cost summary for a worker'
      option :period, type: :string, default: 'weekly', desc: 'Period: daily, weekly, monthly'
      def costs(worker_id)
        out = formatter
        out.warn('Cost reporting requires lex-metering extension (coming soon)')
        out.warn("Worker: #{worker_id}, Period: #{options[:period]}")
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

        def find_worker(worker_id)
          Legion::Data::Model::DigitalWorker.first(worker_id: worker_id) ||
            Legion::Data::Model::DigitalWorker.where(Sequel.like(:worker_id, "#{worker_id}%")).first
        end

        def transition_worker(worker_id, to_state, reason)
          out = formatter
          require 'legion/digital_worker/lifecycle'

          worker = find_worker(worker_id)

          unless worker
            out.error("Worker not found: #{worker_id}")
            return
          end

          begin
            Legion::DigitalWorker::Lifecycle.transition!(worker, to_state: to_state, by: 'cli', reason: reason)
            if options[:json]
              out.json({ worker_id: worker.worker_id, lifecycle_state: to_state, transitioned: true })
            else
              out.success("Worker #{worker.name} transitioned to #{to_state}")
            end
          rescue Legion::DigitalWorker::Lifecycle::InvalidTransition => e
            out.error(e.message)
          end
        end
      end
    end
  end
end
