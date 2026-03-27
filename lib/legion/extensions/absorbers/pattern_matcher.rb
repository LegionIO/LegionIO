# frozen_string_literal: true

module Legion
  module Extensions
    module Absorbers
      module PatternMatcher
        @registrations = []
        @mutex = Mutex.new

        module_function

        def register(absorber_class)
          @mutex.synchronize do
            absorber_class.patterns.each do |pat|
              @registrations << {
                type:           pat[:type],
                value:          pat[:value],
                priority:       pat[:priority],
                absorber_class: absorber_class,
                description:    absorber_class.description
              }
            end
          end
        end

        def resolve(input)
          matches = @mutex.synchronize { @registrations.dup }.select do |reg|
            matcher = Matchers::Base.for_type(reg[:type])
            next false unless matcher

            matcher.match?(reg[:value], input)
          end
          return nil if matches.empty?

          matches.min_by { |m| [m[:priority], -m[:value].gsub('*', '').length] }&.dig(:absorber_class)
        end

        def list
          @mutex.synchronize { @registrations.dup }
        end

        def registrations
          @mutex.synchronize { @registrations.dup }
        end

        def reset!
          @mutex.synchronize { @registrations.clear }
        end
      end
    end
  end
end
