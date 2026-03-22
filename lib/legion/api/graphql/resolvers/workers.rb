# frozen_string_literal: true

module Legion
  class API < Sinatra::Base
    module GraphQL
      module Resolvers
        module Workers
          def self.resolve(status: nil, risk_tier: nil, limit: nil)
            if defined?(Legion::Data) && Legion::Data.respond_to?(:connection) && Legion::Data.connection
              resolve_from_data(status: status, risk_tier: risk_tier, limit: limit)
            else
              resolve_from_registry(status: status, risk_tier: risk_tier, limit: limit)
            end
          end

          def self.find(id:)
            if defined?(Legion::Data) && Legion::Data.respond_to?(:connection) && Legion::Data.connection
              find_from_data(id: id)
            else
              resolve(limit: nil).find { |w| w[:id].to_s == id.to_s }
            end
          end

          def self.resolve_from_data(status: nil, risk_tier: nil, limit: nil)
            return [] unless defined?(Legion::Data::Model::DigitalWorker)

            dataset = Legion::Data::Model::DigitalWorker.order(:id)
            dataset = dataset.where(lifecycle_state: status) if status
            dataset = dataset.where(risk_tier: risk_tier)    if risk_tier
            dataset = dataset.limit(limit)                   if limit
            dataset.all.map { |w| worker_hash(w.values) }
          rescue StandardError => e
            Legion::Logging.warn "GraphQL::Workers#resolve_from_data failed: #{e.message}" if defined?(Legion::Logging)
            []
          end

          def self.resolve_from_registry(status: nil, risk_tier: nil, limit: nil)
            workers = []

            if defined?(Legion::DigitalWorker::Registry)
              ids = Legion::DigitalWorker::Registry.local_worker_ids
              ids.each do |wid|
                workers << { id: wid, name: "worker-#{wid}", status: 'active', risk_tier: nil, team: nil, extension: nil, created_at: nil }
              end
            end

            workers = workers.select { |w| w[:status] == status } if status
            workers = workers.select { |w| w[:risk_tier] == risk_tier } if risk_tier
            workers = workers.first(limit)                              if limit
            workers
          end

          def self.find_from_data(id:)
            return nil unless defined?(Legion::Data::Model::DigitalWorker)

            worker = Legion::Data::Model::DigitalWorker.first(id: id.to_i)
            worker ? worker_hash(worker.values) : nil
          rescue StandardError => e
            Legion::Logging.warn "GraphQL::Workers#find_from_data failed for id=#{id}: #{e.message}" if defined?(Legion::Logging)
            nil
          end

          def self.worker_hash(values)
            {
              id:         values[:id],
              name:       values[:name],
              status:     values[:lifecycle_state] || values[:status],
              risk_tier:  values[:risk_tier],
              team:       values[:team],
              extension:  values[:extension_name],
              created_at: values[:created_at]&.to_s
            }
          end

          private_class_method :resolve_from_data, :resolve_from_registry, :find_from_data, :worker_hash
        end
      end
    end
  end
end
