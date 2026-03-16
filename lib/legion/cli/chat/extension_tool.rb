# frozen_string_literal: true

module Legion
  module CLI
    class Chat
      module ExtensionTool
        VALID_TIERS = %i[read write shell].freeze

        def self.included(base)
          base.extend(ClassMethods)
        end

        module ClassMethods
          def permission_tier(tier = nil)
            if tier
              raise ArgumentError, "Invalid permission tier: #{tier}" unless VALID_TIERS.include?(tier)

              @declared_permission_tier = tier
            end
            @declared_permission_tier
          end

          def declared_permission_tier
            @declared_permission_tier || :write
          end
        end
      end
    end
  end
end
