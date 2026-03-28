# frozen_string_literal: true

module Legion
  module Extensions
    module Actors
      module Dsl
        def define_dsl_accessor(name, default:)
          define_singleton_method(name) do |val = :_unset|
            if val == :_unset
              if instance_variable_defined?(:"@#{name}")
                instance_variable_get(:"@#{name}")
              elsif superclass.respond_to?(name)
                superclass.public_send(name)
              else
                default
              end
            else
              instance_variable_set(:"@#{name}", val)
            end
          end

          define_method(name) do
            self.class.public_send(name)
          end
        end
      end
    end
  end
end
