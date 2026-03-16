# frozen_string_literal: true

module Legion
  module CLI
    class Doctor
      class PermissionsCheck
        DIRECTORIES = [
          '/var/log/legion',
          '/var/run',
          '/tmp'
        ].freeze

        def name
          'Permissions'
        end

        def run
          denied = unwritable_directories

          if denied.empty?
            Result.new(name: name, status: :pass, message: 'Directory permissions ok')
          else
            prescriptions = denied.map { |d| "Fix permissions: `chmod 755 #{d}`" }
            Result.new(
              name:         name,
              status:       :warn,
              message:      "Cannot write to: #{denied.join(', ')}",
              prescription: prescriptions.join('; ')
            )
          end
        end

        private

        def unwritable_directories
          DIRECTORIES.select do |dir|
            Dir.exist?(dir) && !File.writable?(dir)
          end
        end
      end
    end
  end
end
