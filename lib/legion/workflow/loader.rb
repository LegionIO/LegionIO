# frozen_string_literal: true

module Legion
  module Workflow
    class Loader
      def install(manifest)
        return { success: false, errors: manifest.errors } unless manifest.valid?

        missing = check_requirements(manifest.requires)
        return { success: false, error: :missing_gems, gems: missing } if missing.any?

        chain_id = find_or_create_chain(manifest.name)
        ids = []

        manifest.relationships.each_with_index do |rel, idx|
          trigger_id = resolve_function_id(rel[:trigger])
          return { success: false, error: :trigger_not_found, relationship: rel[:name] || idx } unless trigger_id

          action_id = resolve_function_id(rel[:action])
          return { success: false, error: :action_not_found, relationship: rel[:name] || idx } unless action_id

          id = Legion::Data::Model::Relationship.insert(
            trigger_id:        trigger_id,
            action_id:         action_id,
            name:              rel[:name],
            chain_id:          chain_id,
            conditions:        rel[:conditions] ? Legion::JSON.dump(rel[:conditions]) : nil,
            transformation:    rel[:transformation] ? Legion::JSON.dump(rel[:transformation]) : nil,
            delay:             rel.fetch(:delay, 0),
            allow_new_chains:  idx.zero? || rel[:allow_new_chains],
            active:            true,
            status:            'active',
            relationship_type: 'chain'
          )
          ids << id
        end

        { success: true, chain_id: chain_id, relationship_ids: ids }
      end

      def uninstall(name)
        chain = Legion::Data::Model::Chain.where(name: name).first
        return { success: false, error: :not_found } unless chain

        chain_id = chain.values[:id]
        count = Legion::Data::Model::Relationship.where(chain_id: chain_id).delete
        chain.delete

        { success: true, deleted_relationships: count }
      end

      def list
        Legion::Data::Model::Chain.all.map do |chain|
          v = chain.values
          rel_count = Legion::Data::Model::Relationship.where(chain_id: v[:id]).count
          { id: v[:id], name: v[:name], relationships: rel_count }
        end
      end

      def status(name)
        chain = Legion::Data::Model::Chain.where(name: name).first
        return { success: false, error: :not_found } unless chain

        chain_id = chain.values[:id]
        rels = Legion::Data::Model::Relationship
               .where(chain_id: chain_id)
               .all
               .map { |r| format_relationship(r) }

        { success: true, name: name, chain_id: chain_id, relationships: rels }
      end

      private

      def check_requirements(requires)
        requires.select do |gem_name|
          Gem::Specification.find_all_by_name(gem_name).empty?
        end
      end

      def find_or_create_chain(name)
        existing = Legion::Data::Model::Chain.where(name: name).first
        return existing.values[:id] if existing

        Legion::Data::Model::Chain.insert(name: name)
      end

      def resolve_function_id(ref)
        ext = Legion::Data::Model::Extension.where(name: ref[:extension].to_s).first
        return nil unless ext

        runner = Legion::Data::Model::Runner.where(
          extension_id: ext.values[:id],
          name:         ref[:runner].to_s
        ).first
        return nil unless runner

        func = Legion::Data::Model::Function.where(
          runner_id: runner.values[:id],
          name:      ref[:function].to_s
        ).first

        func&.values&.[](:id)
      end

      def format_relationship(rel)
        v = rel.values
        trigger = v[:trigger_id] ? Legion::Data::Model::Function[v[:trigger_id]] : nil
        action = v[:action_id] ? Legion::Data::Model::Function[v[:action_id]] : nil

        {
          id:         v[:id],
          name:       v[:name],
          trigger:    trigger&.values&.[](:name),
          action:     action&.values&.[](:name),
          conditions: !v[:conditions].nil?,
          active:     v[:active]
        }
      end
    end
  end
end
