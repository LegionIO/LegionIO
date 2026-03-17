# frozen_string_literal: true

module Legion
  module Registry
    class Entry
      ATTRS = %i[name version author risk_tier permissions airb_status
                 description homepage checksum capabilities].freeze

      attr_reader(*ATTRS)

      def initialize(**attrs)
        ATTRS.each { |a| instance_variable_set(:"@#{a}", attrs[a]) }
        @risk_tier ||= 'low'
        @airb_status ||= 'pending'
        @capabilities ||= []
        @permissions ||= []
      end

      def approved?
        airb_status == 'approved'
      end

      def to_h
        ATTRS.to_h { |a| [a, send(a)] }
      end
    end

    class << self
      def register(entry)
        store[entry.name] = entry
      end

      def unregister(name)
        store.delete(name.to_s)
      end

      def lookup(name)
        store[name.to_s]
      end

      def all
        store.values
      end

      def search(query)
        pattern = query.to_s.downcase
        store.values.select do |e|
          e.name.downcase.include?(pattern) ||
            (e.description || '').downcase.include?(pattern)
        end
      end

      def approved
        store.values.select(&:approved?)
      end

      def by_risk_tier(tier)
        store.values.select { |e| e.risk_tier == tier.to_s }
      end

      def clear!
        @store = {}
      end

      private

      def store
        @store ||= {}
      end
    end
  end
end
