# frozen_string_literal: true

module Legion
  class API < Sinatra::Base
    module GraphQL
      module Resolvers
        module Tasks
          def self.resolve(status: nil, limit: nil)
            return [] unless defined?(Legion::Data) &&
                             Legion::Data.respond_to?(:connection) &&
                             Legion::Data.connection

            resolve_from_data(status: status, limit: limit)
          rescue StandardError => e
            Legion::Logging.warn "GraphQL::Tasks#resolve failed: #{e.message}" if defined?(Legion::Logging)
            []
          end

          def self.resolve_from_data(status: nil, limit: nil)
            return [] unless defined?(Legion::Data::Model::Task)

            dataset = Legion::Data::Model::Task.order(Sequel.desc(:id))
            dataset = dataset.where(status: status) if status
            dataset = dataset.limit(limit)          if limit
            dataset.all.map { |t| task_hash(t.values) }
          rescue StandardError => e
            Legion::Logging.warn "GraphQL::Tasks#resolve_from_data failed: #{e.message}" if defined?(Legion::Logging)
            []
          end

          def self.task_hash(values)
            {
              id:           values[:id],
              status:       values[:status],
              extension:    values[:extension],
              runner:       values[:runner],
              function:     values[:function],
              created_at:   values[:created_at]&.to_s,
              completed_at: values[:completed_at]&.to_s
            }
          end

          private_class_method :resolve_from_data, :task_hash
        end
      end
    end
  end
end
