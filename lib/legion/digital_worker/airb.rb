# frozen_string_literal: true

module Legion
  module DigitalWorker
    module Airb
      class << self
        # Create an AIRB intake form for a worker registration.
        # Returns an intake_id string.
        def create_intake(worker_id, description:)
          return mock_create_intake(worker_id, description) unless live_api?

          endpoint = api_endpoint
          raise ArgumentError, 'AIRB API endpoint not configured' unless endpoint

          response = http_post(
            "#{endpoint}/intakes",
            { worker_id: worker_id, description: description, submitted_at: Time.now.utc.iso8601 }
          )

          response[:intake_id] || response['intake_id']
        rescue StandardError => e
          log_warn "AIRB create_intake failed: #{e.message}"
          nil
        end

        # Check the AIRB approval status for a given intake_id.
        # Returns: 'pending', 'approved', or 'rejected'
        def check_status(intake_id)
          return mock_check_status(intake_id) unless live_api?

          endpoint = api_endpoint
          raise ArgumentError, 'AIRB API endpoint not configured' unless endpoint

          response = http_get("#{endpoint}/intakes/#{intake_id}/status")
          response[:status] || response['status'] || 'pending'
        rescue StandardError => e
          log_warn "AIRB check_status failed for #{intake_id}: #{e.message}"
          'pending'
        end

        # Sync AIRB status back to the Legion worker state.
        # Calls approve/reject on the Registration module when AIRB has a decision.
        def sync_status(worker_id)
          return { synced: false, reason: 'DigitalWorker not defined' } unless defined?(Legion::DigitalWorker)

          worker = find_worker(worker_id)
          return { synced: false, reason: 'worker not found' } unless worker
          return { synced: false, reason: 'not pending approval' } unless worker.lifecycle_state == 'pending_approval'

          intake_id = lookup_intake_id(worker_id)
          return { synced: false, reason: 'no intake_id found' } unless intake_id

          status = check_status(intake_id)
          log_info "worker=#{worker_id} intake=#{intake_id} airb_status=#{status}"

          case status
          when 'approved'
            apply_airb_approval(worker_id)
          when 'rejected'
            apply_airb_rejection(worker_id)
          else
            { synced: false, reason: "airb_status=#{status}", intake_id: intake_id }
          end
        end

        private

        def live_api?
          api_endpoint && api_credentials
        end

        def api_endpoint
          return nil unless defined?(Legion::Settings)

          Legion::Settings.dig(:airb, :api_endpoint)
        end

        def api_credentials
          return nil unless defined?(Legion::Settings)

          Legion::Settings.dig(:airb, :credentials)
        end

        def http_post(url, payload)
          require 'net/http'
          require 'json'
          uri  = URI.parse(url)
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = uri.scheme == 'https'
          req = Net::HTTP::Post.new(uri.request_uri, { 'Content-Type' => 'application/json' })
          req.body = ::JSON.generate(payload)
          resp = http.request(req)
          ::JSON.parse(resp.body, symbolize_names: true)
        end

        def http_get(url)
          require 'net/http'
          require 'json'
          uri  = URI.parse(url)
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = uri.scheme == 'https'
          req  = Net::HTTP::Get.new(uri.request_uri)
          resp = http.request(req)
          ::JSON.parse(resp.body, symbolize_names: true)
        end

        def mock_create_intake(worker_id, description)
          intake_id = "airb-mock-#{worker_id[0..7]}-#{Time.now.utc.to_i}"
          log_info "mock AIRB intake created: #{intake_id} desc=#{description[0..60]}"
          intake_id
        end

        def mock_check_status(_intake_id)
          'pending'
        end

        def find_worker(worker_id)
          return nil unless defined?(Legion::Data::Model::DigitalWorker)

          Legion::Data::Model::DigitalWorker.first(worker_id: worker_id)
        end

        def lookup_intake_id(worker_id)
          return nil unless defined?(Legion::Data::Model::DigitalWorker)

          worker = Legion::Data::Model::DigitalWorker.first(worker_id: worker_id)
          worker.respond_to?(:airb_intake_id) ? worker.airb_intake_id : nil
        end

        def apply_airb_approval(worker_id)
          Legion::DigitalWorker::Registration.approve(worker_id, approver: 'airb', notes: 'Auto-approved by AIRB')
          { synced: true, action: 'approved', worker_id: worker_id }
        rescue StandardError => e
          log_warn "AIRB sync approve failed for #{worker_id}: #{e.message}"
          { synced: false, reason: e.message }
        end

        def apply_airb_rejection(worker_id)
          Legion::DigitalWorker::Registration.reject(worker_id, approver: 'airb', reason: 'Rejected by AIRB review board')
          { synced: true, action: 'rejected', worker_id: worker_id }
        rescue StandardError => e
          log_warn "AIRB sync reject failed for #{worker_id}: #{e.message}"
          { synced: false, reason: e.message }
        end

        def log_info(msg)
          Legion::Logging.info "[airb] #{msg}" if defined?(Legion::Logging)
        end

        def log_warn(msg)
          Legion::Logging.warn "[airb] #{msg}" if defined?(Legion::Logging)
        end
      end
    end
  end
end
