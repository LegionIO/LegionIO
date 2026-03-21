# frozen_string_literal: true

require 'securerandom'

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
            out.detail({
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
                       })
          end
        end
      end

      desc 'pause WORKER_ID', 'Pause a digital worker'
      option :reason, type: :string, desc: 'Reason for pausing'
      def pause(worker_id)
        with_data { transition_worker(worker_id, 'paused', options[:reason], authority_verified: true) }
      end

      desc 'retire WORKER_ID', 'Retire a digital worker'
      option :reason, type: :string, desc: 'Reason for retiring'
      def retire(worker_id)
        with_data { transition_worker(worker_id, 'retired', options[:reason], authority_verified: true) }
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
        with_data { transition_worker(worker_id, 'terminated', options[:reason], governance_override: true) }
      end

      desc 'activate WORKER_ID', 'Activate a worker (from bootstrap or paused)'
      def activate(worker_id)
        with_data { transition_worker(worker_id, 'active', nil, authority_verified: true) }
      end

      desc 'create NAME', 'Register a new digital worker'
      method_option :entra_app_id, type: :string, required: true, desc: 'Entra Application (client) ID'
      method_option :owner_msid, type: :string, required: true, desc: 'Owner Microsoft ID (email)'
      method_option :extension, type: :string, required: true, desc: 'Extension name (e.g., lex-github)'
      method_option :team, type: :string, desc: 'Team assignment'
      method_option :manager_msid, type: :string, desc: 'Manager Microsoft ID'
      method_option :business_role, type: :string, desc: 'Business role description'
      method_option :risk_tier, type: :string, default: 'low', desc: 'Risk tier (low/medium/high/critical)'
      method_option :consent_tier, type: :string, default: 'supervised', desc: 'Consent tier'
      method_option :client_secret, type: :string, desc: 'Entra app client secret (stored in Vault)'
      def create(name)
        with_data { create_worker(name) }
      end

      desc 'approvals', 'List workers pending AIRB approval'
      def approvals
        out = formatter
        with_data do
          require 'legion/digital_worker/registration'
          workers = Legion::DigitalWorker::Registration.pending_approvals

          if options[:json]
            out.json(workers.map(&:to_hash))
          else
            rows = workers.map do |w|
              age = w.created_at ? "#{((Time.now.utc - w.created_at) / 3600).round(1)}h" : '-'
              [w.worker_id[0..7], w.name, w.risk_tier || '-', w.owner_msid, age]
            end
            out.table(%w[ID Name RiskTier Owner PendingFor], rows)
            puts "  #{workers.size} worker(s) pending approval"
          end
        end
      end

      desc 'approve WORKER_ID', 'Approve a worker registration'
      option :notes, type: :string, desc: 'Approval notes'
      def approve(worker_id)
        out = formatter
        with_data do
          require 'legion/digital_worker/registration'
          worker = Legion::DigitalWorker::Registration.approve(worker_id, approver: 'cli', notes: options[:notes])
          if options[:json]
            out.json({ worker_id: worker.worker_id, lifecycle_state: worker.lifecycle_state, approved: true })
          else
            out.success("Worker #{worker.name} approved and activated")
          end
        rescue ArgumentError => e
          out.error(e.message)
        rescue Legion::DigitalWorker::Lifecycle::InvalidTransition => e
          out.error("Invalid transition: #{e.message}")
        end
      end

      desc 'reject WORKER_ID', 'Reject a worker registration'
      option :reason, type: :string, required: true, desc: 'Rejection reason'
      def reject(worker_id)
        out = formatter
        with_data do
          require 'legion/digital_worker/registration'
          unless options[:reason]
            out.error('--reason is required to reject a worker')
            return
          end
          worker = Legion::DigitalWorker::Registration.reject(worker_id, approver: 'cli', reason: options[:reason])
          if options[:json]
            out.json({ worker_id: worker.worker_id, lifecycle_state: worker.lifecycle_state, rejected: true })
          else
            out.success("Worker #{worker.name} rejected")
          end
        rescue ArgumentError => e
          out.error(e.message)
        rescue Legion::DigitalWorker::Lifecycle::InvalidTransition => e
          out.error("Invalid transition: #{e.message}")
        end
      end

      desc 'costs WORKER_ID', 'Show cost summary for a worker'
      option :period, type: :string, default: 'weekly', desc: 'Period: daily, weekly, monthly'
      def costs(worker_id)
        out = formatter
        out.warn('Cost reporting requires lex-metering extension (coming soon)')
        out.warn("Worker: #{worker_id}, Period: #{options[:period]}")
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

        def find_worker(worker_id)
          Legion::Data::Model::DigitalWorker.first(worker_id: worker_id) ||
            Legion::Data::Model::DigitalWorker.where(Sequel.like(:worker_id, "#{worker_id}%")).first
        end

        def create_worker(name) # rubocop:disable Metrics/AbcSize
          out = formatter
          worker_id = SecureRandom.uuid

          attrs = {
            worker_id:       worker_id,
            name:            name,
            entra_app_id:    options[:entra_app_id],
            owner_msid:      options[:owner_msid],
            extension_name:  options[:extension],
            lifecycle_state: 'bootstrap',
            consent_tier:    options[:consent_tier],
            trust_score:     0.0,
            created_at:      Time.now.utc
          }
          attrs[:team] = options[:team] if options[:team]
          attrs[:manager_msid] = options[:manager_msid] if options[:manager_msid]
          attrs[:business_role] = options[:business_role] if options[:business_role]
          attrs[:risk_tier] = options[:risk_tier] if options[:risk_tier]

          worker = Legion::Data::Model::DigitalWorker.create(attrs)
          store_client_secret(out, worker_id) if options[:client_secret]

          if options[:json]
            out.json(worker.to_hash)
          else
            out.success('Worker created successfully:')
            out.spacer
            out.detail({
                         'Worker ID'    => worker_id,
                         'Name'         => name,
                         'Entra App ID' => options[:entra_app_id],
                         'Owner'        => options[:owner_msid],
                         'Extension'    => options[:extension],
                         'State'        => 'bootstrap',
                         'Consent Tier' => options[:consent_tier],
                         'Risk Tier'    => options[:risk_tier],
                         'Team'         => options[:team] || '(none)'
                       })
            out.spacer
            out.success("Next: legion worker activate #{worker_id}")
          end
        rescue Sequel::UniqueConstraintViolation
          out.error("A worker with entra_app_id '#{options[:entra_app_id]}' already exists.")
        rescue Sequel::ValidationFailed => e
          out.error(e.message)
        end

        def store_client_secret(out, worker_id)
          if defined?(Legion::Extensions::Identity::Helpers::VaultSecrets) &&
             Legion::Extensions::Identity::Helpers::VaultSecrets.send(:vault_available?)
            Legion::Extensions::Identity::Helpers::VaultSecrets.store_client_secret(
              worker_id: worker_id, client_secret: options[:client_secret],
              entra_app_id: options[:entra_app_id]
            )
            out.success('Client secret stored in Vault.')
          else
            out.warn('Vault not connected. Client secret was NOT stored.')
          end
        end

        def transition_worker(worker_id, to_state, reason, **)
          out = formatter
          require 'legion/digital_worker/lifecycle'

          worker = find_worker(worker_id)

          unless worker
            out.error("Worker not found: #{worker_id}")
            return
          end

          begin
            Legion::DigitalWorker::Lifecycle.transition!(worker, to_state: to_state, by: 'cli', reason: reason, **)
            if options[:json]
              out.json({ worker_id: worker.worker_id, lifecycle_state: to_state, transitioned: true })
            else
              out.success("Worker #{worker.name} transitioned to #{to_state}")
            end
          rescue Legion::DigitalWorker::Lifecycle::GovernanceRequired => e
            out.error("Governance approval required: #{e.message}")
          rescue Legion::DigitalWorker::Lifecycle::AuthorityRequired => e
            out.error("Insufficient authority/permission: #{e.message}")
          rescue Legion::DigitalWorker::Lifecycle::InvalidTransition => e
            out.error(e.message)
          end
        end
      end
    end
  end
end
