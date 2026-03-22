# frozen_string_literal: true

module Legion
  module Registry
    VALID_STATUSES = %i[pending_review approved rejected deprecated sunset active].freeze

    class Entry
      ATTRS = %i[name version author risk_tier permissions airb_status
                 description homepage checksum capabilities
                 status review_notes reject_reason successor sunset_date
                 submitted_at approved_at rejected_at deprecated_at].freeze

      attr_reader(*ATTRS)

      def initialize(**attrs)
        ATTRS.each { |a| instance_variable_set(:"@#{a}", attrs[a]) }
        @risk_tier   ||= 'low'
        @airb_status ||= 'pending'
        @capabilities ||= []
        @permissions  ||= []
        @status       ||= :active
      end

      def approved?
        airb_status == 'approved'
      end

      def deprecated?
        %i[deprecated sunset].include?(status)
      end

      def pending_review?
        status == :pending_review
      end

      def to_h
        ATTRS.to_h { |a| [a, send(a)] }
      end
    end

    class << self
      def register(entry)
        raise ArgumentError, "Extension name '#{entry.name}' violates naming convention" if defined?(Governance) && !Governance.check_name(entry.name)

        store[entry.name] = entry

        if defined?(Governance) && Governance.auto_approve?(entry.risk_tier)
          update_entry(entry.name, entry, status: :approved, airb_status: 'approved', approved_at: Time.now.utc)
        end

        Persistence.persist(store[entry.name]) if defined?(Persistence)
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

      # Review workflow

      def submit_for_review(name)
        entry = find_or_raise(name)
        update_entry(name, entry, status: :pending_review, submitted_at: Time.now.utc)
        true
      end

      def approve(name, notes: nil)
        entry = find_or_raise(name)
        update_entry(name, entry,
                     status:       :approved,
                     airb_status:  'approved',
                     review_notes: notes,
                     approved_at:  Time.now.utc)
        true
      end

      def reject(name, reason: nil)
        entry = find_or_raise(name)
        update_entry(name, entry,
                     status:        :rejected,
                     reject_reason: reason,
                     rejected_at:   Time.now.utc)
        true
      end

      def deprecate(name, successor: nil, sunset_date: nil)
        entry = find_or_raise(name)
        update_entry(name, entry,
                     status:        :deprecated,
                     successor:     successor,
                     sunset_date:   sunset_date,
                     deprecated_at: Time.now.utc)
        true
      end

      def pending_reviews
        store.values.select(&:pending_review?)
      end

      def usage_stats(name)
        entry = lookup(name.to_s)
        return nil unless entry

        {
          name:             entry.name,
          version:          entry.version,
          install_count:    0,
          active_instances: 0,
          last_updated:     nil,
          downloads_7d:     0,
          downloads_30d:    0
        }
      end

      private

      def store
        @store ||= {}
      end

      def find_or_raise(name)
        entry = lookup(name.to_s)
        raise ArgumentError, "Extension '#{name}' not found in registry" unless entry

        entry
      end

      def update_entry(name, entry, **overrides)
        attrs = entry.to_h.merge(overrides)
        store[name.to_s] = Entry.new(**attrs)
        Persistence.persist(store[name.to_s]) if defined?(Persistence)
      end
    end
  end
end

require_relative 'registry/persistence'
require_relative 'registry/governance'
