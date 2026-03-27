# frozen_string_literal: true

module Legion
  module Extensions
    module Absorbers
      module Matchers
        class Base
          @registry = {}

          class << self
            attr_reader :registry

            def inherited(subclass)
              super
              TracePoint.new(:end) do |tp|
                if tp.self == subclass
                  register(subclass) if subclass.respond_to?(:type) && subclass.type
                  tp.disable
                end
              end.enable
            end

            def register(matcher_class)
              @registry[matcher_class.type] = matcher_class
            end

            def for_type(type)
              @registry[type&.to_sym]
            end

            def type = nil

            def match?(_pattern, _input)
              raise NotImplementedError, "#{name} must implement .match?"
            end
          end
        end
      end
    end
  end
end
