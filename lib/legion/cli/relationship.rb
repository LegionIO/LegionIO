# frozen_string_literal: true

module Legion
  class Cli
    class Relationship < Thor
      desc 'create', 'creates a new relationship'
      def create(_name, _type)
        trigger_id = invoke('legion:cli:function:find', [], internal: true, capture: true) # rubocop:disable Lint/UselessAssignment
      end

      desc 'activate', 'actives a relationship'
      def active; end

      desc 'deactivate', 'deactivates a relationship'
      def deactivate; end

      desc 'modify', 'modify an existing relationship'
      def modify; end

      desc 'delete', 'deletes a relationship'
      def delete; end
    end
  end
end
