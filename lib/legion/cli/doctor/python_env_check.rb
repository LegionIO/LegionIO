# frozen_string_literal: true

require 'legion/python'

module Legion
  module CLI
    class Doctor
      class PythonEnvCheck
        def name
          'Python env'
        end

        def run
          return skip_result('python3 not found on PATH') unless Legion::Python.find_system_python3
          unless Legion::Python.venv_exists?
            return warn_result(
              'Python venv missing',
              'Run: legionio setup python'
            )
          end

          unless Legion::Python.venv_pip_exists?
            return warn_result(
              'pip not found in venv — venv may be corrupt',
              'Run: legionio setup python --rebuild',
              auto_fixable: true
            )
          end

          missing = missing_packages
          if missing.any?
            return warn_result(
              "Missing packages: #{missing.join(', ')}",
              'Run: legionio setup python',
              auto_fixable: true
            )
          end

          pass_result(venv_summary)
        rescue StandardError => e
          Legion::Logging.error("PythonEnvCheck#run: #{e.message}") if defined?(Legion::Logging)
          Result.new(
            name:         name,
            status:       :fail,
            message:      "Python env check error: #{e.message}",
            prescription: 'Run: legionio setup python'
          )
        end

        def fix
          system('legionio', 'setup', 'python')
        end

        private

        def missing_packages
          pip = Legion::Python.venv_pip
          output = `"#{pip}" list --format=columns 2>/dev/null`
          installed_names = output.lines
                                  .drop(2)
                                  .map { |l| l.split.first&.downcase&.tr('-', '_') }
                                  .compact

          Legion::Python::PACKAGES.reject do |pkg|
            normalised = pkg.downcase.tr('-', '_')
            installed_names.include?(normalised)
          end
        rescue StandardError
          Legion::Python::PACKAGES.dup
        end

        def venv_summary
          python_bin = Legion::Python.venv_python
          if File.executable?(python_bin)
            version = `"#{python_bin}" --version 2>&1`.strip
            "#{version} at #{Legion::Python::VENV_DIR}"
          else
            Legion::Python::VENV_DIR
          end
        rescue StandardError
          Legion::Python::VENV_DIR
        end

        def pass_result(message)
          Result.new(name: name, status: :pass, message: message)
        end

        def warn_result(message, prescription, auto_fixable: false)
          Result.new(
            name:         name,
            status:       :warn,
            message:      message,
            prescription: prescription,
            auto_fixable: auto_fixable
          )
        end

        def skip_result(message)
          Result.new(name: name, status: :skip, message: message)
        end
      end
    end
  end
end
