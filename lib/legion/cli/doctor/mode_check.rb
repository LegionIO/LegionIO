# frozen_string_literal: true

module Legion
  module CLI
    class Doctor
      class ModeCheck
        def name
          'Process mode'
        end

        def run
          unless defined?(Legion::Settings)
            return Result.new(
              name:    name,
              status:  :pass,
              message: 'Settings not loaded'
            )
          end

          explicit_mode = Legion::Settings.dig(:process, :mode) || Legion::Settings[:mode]

          if explicit_mode
            Result.new(
              name:    name,
              status:  :pass,
              message: "Explicit process mode configured: #{explicit_mode}"
            )
          else
            Result.new(
              name:         name,
              status:       :warn,
              message:      'No explicit process.mode configured (defaulting to agent)',
              prescription: 'Set {"process": {"mode": "agent"}} in settings to prepare for Phase 9 default change to worker'
            )
          end
        end
      end
    end
  end
end
