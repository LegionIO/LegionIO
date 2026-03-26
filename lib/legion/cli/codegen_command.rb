# frozen_string_literal: true

module Legion
  module CLI
    class CodegenCommand < Thor
      namespace :codegen

      desc 'status', 'Show codegen cycle stats, pending gaps, registry counts'
      def status
        if defined?(Legion::MCP::SelfGenerate)
          data = Legion::MCP::SelfGenerate.status
          say Legion::JSON.dump({ data: data })
        else
          say Legion::JSON.dump({ error: 'codegen not available' })
        end
      end

      desc 'list', 'List generated functions'
      method_option :status, type: :string, desc: 'Filter by status'
      def list
        unless defined?(Legion::Extensions::Codegen::Helpers::GeneratedRegistry)
          say Legion::JSON.dump({ error: 'codegen registry not available' })
          return
        end

        records = Legion::Extensions::Codegen::Helpers::GeneratedRegistry.list(status: options[:status])
        say Legion::JSON.dump({ data: records })
      end

      desc 'show ID', 'Show details of a generated function'
      def show(id)
        unless defined?(Legion::Extensions::Codegen::Helpers::GeneratedRegistry)
          say Legion::JSON.dump({ error: 'codegen registry not available' })
          return
        end

        record = Legion::Extensions::Codegen::Helpers::GeneratedRegistry.get(id: id)
        if record
          say Legion::JSON.dump({ data: record })
        else
          say Legion::JSON.dump({ error: 'not found' })
        end
      end

      desc 'approve ID', 'Manually approve a parked generated function'
      def approve(id)
        unless defined?(Legion::Extensions::Codegen::Runners::ReviewHandler)
          say Legion::JSON.dump({ error: 'review handler not available' })
          return
        end

        result = Legion::Extensions::Codegen::Runners::ReviewHandler.handle_verdict(
          review: { generation_id: id, verdict: :approve, confidence: 1.0 }
        )
        say Legion::JSON.dump({ data: result })
      end

      desc 'reject ID', 'Manually reject a generated function'
      def reject(id)
        unless defined?(Legion::Extensions::Codegen::Helpers::GeneratedRegistry)
          say Legion::JSON.dump({ error: 'codegen registry not available' })
          return
        end

        Legion::Extensions::Codegen::Helpers::GeneratedRegistry.update_status(id: id, status: 'rejected')
        say Legion::JSON.dump({ data: { id: id, status: 'rejected' } })
      end

      desc 'retry ID', 'Re-queue a generated function for regeneration'
      def retry_generation(id)
        unless defined?(Legion::Extensions::Codegen::Helpers::GeneratedRegistry)
          say Legion::JSON.dump({ error: 'codegen registry not available' })
          return
        end

        Legion::Extensions::Codegen::Helpers::GeneratedRegistry.update_status(id: id, status: 'pending')
        say Legion::JSON.dump({ data: { id: id, status: 'pending' } })
      end
      map 'retry' => :retry_generation

      desc 'gaps', 'List detected capability gaps with priorities'
      def gaps
        if defined?(Legion::MCP::GapDetector)
          detected = Legion::MCP::GapDetector.detect_gaps
          say Legion::JSON.dump({ data: detected })
        else
          say Legion::JSON.dump({ error: 'gap detector not available' })
        end
      end

      desc 'cycle', 'Manually trigger a generation cycle (bypass cooldown)'
      def cycle
        unless defined?(Legion::MCP::SelfGenerate)
          say Legion::JSON.dump({ error: 'self_generate not available' })
          return
        end

        Legion::MCP::SelfGenerate.instance_variable_set(:@last_cycle_at, nil)
        result = Legion::MCP::SelfGenerate.run_cycle
        say Legion::JSON.dump({ data: result })
      end
    end
  end
end
