# frozen_string_literal: true

module Legion
  module CLI
    class Doctor
      class PidCheck
        PID_PATHS = ['/var/run/legion.pid', '/tmp/legion.pid'].freeze

        def name
          'PID files'
        end

        def run
          stale = stale_pid_files
          if stale.empty?
            Result.new(name: name, status: :pass, message: 'No stale PID files')
          else
            rm_cmds = stale.map { |f| "rm #{f}" }.join('; ')
            Result.new(
              name:         name,
              status:       :warn,
              message:      "Stale PID file(s): #{stale.join(', ')}",
              prescription: "Remove with: #{rm_cmds}",
              auto_fixable: true
            )
          end
        end

        def fix
          stale_pid_files.each { |f| File.delete(f) }
        end

        private

        def stale_pid_files
          PID_PATHS.select do |path|
            next false unless File.exist?(path)

            pid = File.read(path).strip.to_i
            !process_running?(pid)
          rescue StandardError
            false
          end
        end

        def process_running?(pid)
          return false if pid <= 0

          ::Process.kill(0, pid)
          true
        rescue Errno::ESRCH
          false
        rescue Errno::EPERM
          true
        end
      end
    end
  end
end
