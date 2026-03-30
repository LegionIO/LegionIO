# frozen_string_literal: true

if defined?(Sequel)
  module Legion
    module Data
      module Model
        class TbiPattern < Sequel::Model(:tbi_patterns)
          plugin :timestamps, update_on_create: true

          def validate
            super
            errors.add(:pattern_type, 'is required') if !pattern_type || pattern_type.to_s.strip.empty?
            errors.add(:description,  'is required') if !description  || description.to_s.strip.empty?
            errors.add(:pattern_data, 'is required') if !pattern_data || pattern_data.to_s.strip.empty?
            errors.add(:tier,         'is required') if !tier         || tier.to_s.strip.empty?
          end
        end
      end
    end
  end
end
