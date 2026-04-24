# frozen_string_literal: true

module Legion
  module Identity
    module Trust
      LEVELS = %i[verified authenticated configured cached unverified].freeze
      RANK = LEVELS.each_with_index.to_h.freeze

      module_function

      def levels
        LEVELS
      end

      def rank(level)
        RANK[level]
      end

      def above?(level_a, level_b)
        rank_a = RANK[level_a]
        rank_b = RANK[level_b]
        return false if rank_a.nil? || rank_b.nil?

        rank_a < rank_b
      end

      def at_least?(level, minimum)
        rank_level = RANK[level]
        rank_min   = RANK[minimum]
        return false if rank_level.nil? || rank_min.nil?

        rank_level <= rank_min
      end
    end
  end
end
