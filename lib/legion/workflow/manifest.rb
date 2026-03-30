# frozen_string_literal: true

require 'yaml'

module Legion
  module Workflow
    class Manifest
      attr_reader :name, :version, :description, :requires, :relationships, :settings

      def initialize(path:)
        raw = YAML.safe_load(File.read(path), symbolize_names: true)
        @name = raw[:name]
        @version = raw[:version]
        @description = raw[:description]
        @requires = raw[:requires] || []
        @relationships = parse_relationships(raw[:relationships] || [])
        @settings = raw[:settings] || {}
      end

      def valid?
        errors.empty?
      end

      def errors
        errs = []
        errs << 'name is required' unless name
        errs << 'at least one relationship is required' if relationships.empty?
        relationships.each_with_index do |rel, i|
          errs << "relationship #{i}: trigger is required" unless rel[:trigger]
          errs << "relationship #{i}: action is required" unless rel[:action]
          %i[trigger action].each do |key|
            next unless rel[key]

            %i[extension runner function].each do |field|
              errs << "relationship #{i}: #{key}.#{field} is required" unless rel[key][field]
            end
          end
        end
        errs
      end

      private

      def parse_relationships(rels)
        rels.map do |rel|
          {
            name: rel[:name],
            trigger: rel[:trigger],
            action: rel[:action],
            conditions: rel[:conditions],
            transformation: rel[:transformation],
            delay: rel.fetch(:delay, 0),
            allow_new_chains: rel.fetch(:allow_new_chains, false)
          }
        end
      end
    end
  end
end
