# frozen_string_literal: true

module Legion
  class API < Sinatra::Base
    module GraphQL
      module Resolvers
        module Extensions
          def self.resolve(status: nil)
            if defined?(Legion::Data) && Legion::Data.respond_to?(:connection) && Legion::Data.connection
              resolve_from_data(status: status)
            else
              resolve_from_registry(status: status)
            end
          end

          def self.find(name:)
            resolve.find { |e| e[:name] == name }
          end

          def self.resolve_from_data(status: nil)
            return [] unless defined?(Legion::Data::Model::Extension)

            dataset = Legion::Data::Model::Extension.order(:id)
            dataset = dataset.where(status: status) if status
            dataset.all.map { |e| extension_hash(e.values) }
          rescue StandardError
            []
          end

          def self.resolve_from_registry(status: nil)
            return [] unless defined?(Legion::Registry)

            entries = Legion::Registry.respond_to?(:all) ? Legion::Registry.all : []
            entries = entries.map { |e| e.is_a?(Hash) ? e : e.to_h }
            entries = entries.select { |e| e[:status].to_s == status } if status
            entries.map { |e| extension_hash(e) }
          rescue StandardError
            []
          end

          def self.extension_hash(values)
            {
              name:        values[:name],
              version:     values[:version],
              status:      values[:status]&.to_s || 'active',
              description: values[:description],
              risk_tier:   values[:risk_tier],
              runners:     Array(values[:runners])
            }
          end

          private_class_method :resolve_from_data, :resolve_from_registry, :extension_hash
        end
      end
    end
  end
end
