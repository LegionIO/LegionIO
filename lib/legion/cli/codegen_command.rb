# frozen_string_literal: true

require_relative 'api_client'

module Legion
  module CLI
    class CodegenCommand < Thor
      namespace :codegen

      class_option :json,     type: :boolean, default: false, desc: 'Output as JSON'
      class_option :no_color, type: :boolean, default: false, desc: 'Disable color output'

      desc 'status', 'Show codegen cycle stats, pending gaps, registry counts'
      def status
        data = api_get('/api/codegen/status')
        formatter.json(data)
      end

      desc 'list', 'List generated functions'
      method_option :status, type: :string, desc: 'Filter by status'
      def list
        path = '/api/codegen/generated'
        path += "?status=#{options[:status]}" if options[:status]
        data = api_get(path)
        formatter.json(data)
      end

      desc 'show ID', 'Show details of a generated function'
      def show(id)
        data = api_get("/api/codegen/generated/#{id}")
        formatter.json(data)
      end

      desc 'approve ID', 'Manually approve a parked generated function'
      def approve(id)
        data = api_post("/api/codegen/generated/#{id}/approve")
        formatter.json(data)
      end

      desc 'reject ID', 'Manually reject a generated function'
      def reject(id)
        data = api_post("/api/codegen/generated/#{id}/reject")
        formatter.json(data)
      end

      desc 'retry ID', 'Re-queue a generated function for regeneration'
      def retry_generation(id)
        data = api_post("/api/codegen/generated/#{id}/retry")
        formatter.json(data)
      end
      map 'retry' => :retry_generation

      desc 'gaps', 'List detected capability gaps with priorities'
      def gaps
        data = api_get('/api/codegen/gaps')
        formatter.json(data)
      end

      desc 'cycle', 'Manually trigger a generation cycle (bypass cooldown)'
      def cycle
        data = api_post('/api/codegen/cycle')
        formatter.json(data)
      end

      no_commands do
        include ApiClient

        def formatter
          @formatter ||= Output::Formatter.new(json: options[:json], color: !options[:no_color])
        end
      end
    end
  end
end
