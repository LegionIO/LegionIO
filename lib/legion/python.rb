# frozen_string_literal: true

module Legion
  module Python
    VENV_DIR = File.expand_path('~/.legionio/python').freeze
    MARKER   = File.expand_path('~/.legionio/.python-venv').freeze

    PACKAGES = %w[
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

    SYSTEM_CANDIDATES = %w[
      /opt/homebrew/bin/python3
      /usr/local/bin/python3
      /usr/bin/python3
    ].freeze

    module_function

    def venv_exists?
      File.exist?("#{VENV_DIR}/pyvenv.cfg")
    end

    def venv_python
      "#{VENV_DIR}/bin/python3"
    end

    def venv_pip
      "#{VENV_DIR}/bin/pip"
    end

    def venv_python_exists?
      File.executable?(venv_python)
    end

    def venv_pip_exists?
      File.executable?(venv_pip)
    end

    def interpreter
      return venv_python if venv_python_exists?

      find_system_python3 || 'python3'
    end

    def pip
      return venv_pip if venv_pip_exists?

      'pip3'
    end

    def find_system_python3
      path_python = `command -v python3 2>/dev/null`.strip
      candidates = SYSTEM_CANDIDATES.dup
      candidates.unshift(path_python) unless path_python.empty?
      candidates.uniq.find { |p| File.executable?(p) }
    end
  end
end
