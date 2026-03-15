# frozen_string_literal: true

module Legion
  module CLI
    class Completion < Thor
      def self.exit_on_failure?
        true
      end

      COMPLETION_DIR = File.expand_path('../../../completions', __dir__)

      desc 'bash', 'Output bash completion script'
      long_desc <<~DESC
        Outputs the bash completion script for the legion CLI.

        Add to your shell permanently:
          echo 'source <(legion completion bash)' >> ~/.bashrc

        Or copy to the bash completions directory:
          legion completion bash > /etc/bash_completion.d/legion
      DESC
      def bash
        puts File.read(File.join(COMPLETION_DIR, 'legion.bash'))
      end

      desc 'zsh', 'Output zsh completion script'
      long_desc <<~DESC
        Outputs the zsh completion script for the legion CLI.

        Add to a directory in your $fpath:
          legion completion zsh > "${fpath[1]}/_legion"

        Or with oh-my-zsh:
          legion completion zsh > ~/.oh-my-zsh/completions/_legion
          exec zsh
      DESC
      def zsh
        puts File.read(File.join(COMPLETION_DIR, '_legion'))
      end

      desc 'install', 'Print shell completion installation instructions'
      def install
        shell = detect_shell
        out = Output::Formatter.new(color: true, json: false)

        out.header('Legion Shell Completion')
        out.spacer

        case shell
        when 'zsh'
          print_zsh_instructions(out)
        when 'bash'
          print_bash_instructions(out)
        else
          print_bash_instructions(out)
          out.spacer
          print_zsh_instructions(out)
        end
      end

      no_commands do
        private

        def detect_shell
          shell = ENV.fetch('SHELL', '')
          return 'zsh'  if shell.end_with?('zsh')
          return 'bash' if shell.end_with?('bash')

          nil
        end

        def print_bash_instructions(out)
          out.header('Bash')
          puts '  # One-time (current session):'
          puts '  source <(legion completion bash)'
          out.spacer
          puts '  # Permanent (add to ~/.bashrc):'
          puts "  echo 'source <(legion completion bash)' >> ~/.bashrc"
          out.spacer
          puts '  # Or copy to completions directory:'
          puts '  legion completion bash > /etc/bash_completion.d/legion'
        end

        def print_zsh_instructions(out)
          out.header('Zsh')
          puts '  # One-time (current session):'
          puts '  source <(legion completion zsh)'
          out.spacer
          puts '  # Permanent — add to a directory in your $fpath:'
          puts '  legion completion zsh > "${fpath[1]}/_legion"'
          out.spacer
          puts '  # Or with oh-my-zsh:'
          puts '  legion completion zsh > ~/.oh-my-zsh/completions/_legion'
          puts '  exec zsh'
        end
      end
    end
  end
end
