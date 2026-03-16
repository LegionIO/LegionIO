# frozen_string_literal: true

require 'legion/cli/chat_command'

module Legion
  module CLI
    class Chat
      module Permissions
        TIERS = if defined?(Tools::ReadFile)
                  {
                    Tools::ReadFile      => :read,
                    Tools::SearchFiles   => :read,
                    Tools::SearchContent => :read,
                    Tools::WriteFile     => :write,
                    Tools::EditFile      => :write,
                    Tools::RunCommand    => :shell
                  }.freeze
                else
                  {}.freeze
                end

        @mode = :interactive
        @extension_tiers = {}

        class << self
          attr_accessor :mode

          def auto_allow?
            %i[headless auto_approve].include?(mode)
          end

          def read_only?
            mode == :read_only
          end

          def confirm?(description)
            return false if read_only?
            return true if auto_allow?

            $stderr.print "\e[33m#{description}\e[0m\n  Allow? [y/n] "
            response = $stdin.gets&.strip&.downcase
            %w[y yes].include?(response)
          end

          def register_extension_tier(tool_class, tier)
            @extension_tiers ||= {}
            @extension_tiers[tool_class] = tier
          end

          def clear_extension_tiers!
            @extension_tiers = {}
          end

          def tier_for(tool_class)
            TIERS[tool_class] || @extension_tiers&.[](tool_class) || :read
          end

          def apply!(tool_classes)
            tool_classes.each do |klass|
              tier = tier_for(klass)
              klass.prepend(Gate) unless tier == :read
            end
          end
        end

        module Gate
          def call(args)
            normalized = normalize_args(args)
            desc = permission_description(normalized)
            return 'Tool execution denied by user.' unless Permissions.confirm?(desc)

            super
          end

          private

          def permission_description(args)
            tier = Permissions.tier_for(self.class)
            case tier
            when :write
              path = args[:path] || '(unknown)'
              action = self.class.name.split('::').last.gsub(/([a-z])([A-Z])/, '\1 \2')
              "#{action}: #{path}"
            when :shell
              "Run command: #{args[:command]}"
            else
              name
            end
          end
        end
      end
    end
  end
end
