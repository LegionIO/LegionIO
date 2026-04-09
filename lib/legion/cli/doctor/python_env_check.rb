# frozen_string_literal: true

module Legion
  module CLI
    class Doctor
      class PythonEnvCheck
        VENV_DIR = File.expand_path('~/.legionio/python').freeze
        MARKER   = File.expand_path('~/.legionio/.python-venv').freeze

        # Packages we consider mandatory — a missing one is a :warn, not a :fail,
        # because Python tools are optional addons rather than daemon requirements.
        REQUIRED_PACKAGES = %w[
          python-pptx
          python-docx
          openpyxl
          pandas
          pillow
          requests
          lxml
          PyYAML
          tabulate
          markdown
        ].freeze

        def name
          'Python env'
        end

        def run
          return skip_result('python3 not found on PATH') unless python3_available?
          return warn_result(
            'Python venv missing',
            'Run: legionio setup python'
          ) unless venv_exists?

          return warn_result(
            'pip not found in venv — venv may be corrupt',
            'Run: legionio setup python --rebuild',
            auto_fixable: true
          ) unless pip_exists?

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

        def python3_available?
          %w[
            /opt/homebrew/bin/python3
            /usr/local/bin/python3
            /usr/bin/python3
          ].any? { |p| File.executable?(p) }
        end

        def venv_exists?
          File.exist?("#{VENV_DIR}/pyvenv.cfg")
        end

        def pip_exists?
          File.executable?("#{VENV_DIR}/bin/pip")
        end

        def missing_packages
          output = `"#{VENV_DIR}/bin/pip" list --format=columns 2>/dev/null`
          installed_names = output.lines
                                  .drop(2) # skip header lines
                                  .map { |l| l.split.first&.downcase&.tr('-', '_') }
                                  .compact

          REQUIRED_PACKAGES.reject do |pkg|
            normalised = pkg.downcase.tr('-', '_')
            installed_names.include?(normalised)
          end
        rescue StandardError
          # If pip itself errors, surface the missing-venv warning instead
          REQUIRED_PACKAGES.dup
        end

        def venv_summary
          python_bin = "#{VENV_DIR}/bin/python3"
          if File.executable?(python_bin)
            version = `"#{python_bin}" --version 2>&1`.strip
            "#{version} at #{VENV_DIR}"
          else
            VENV_DIR
          end
        rescue StandardError
          VENV_DIR
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
