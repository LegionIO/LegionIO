# frozen_string_literal: true

require 'ruby_llm'
require 'legion/cli/chat_command'
require 'open3'
require 'timeout'

module Legion
  module CLI
    class Chat
      module Tools
        class RunCommand < RubyLLM::Tool
          MAX_OUTPUT_CHARS = 48_000

          description 'Execute a shell command and return its output. Use for running tests, builds, git commands, etc.'
          param :command, type: 'string', desc: 'The shell command to execute'
          param :timeout, type: 'integer', desc: 'Timeout in seconds (default: 120)', required: false
          param :working_directory, type: 'string', desc: 'Working directory (default: current dir)', required: false

          def execute(command:, timeout: 120, working_directory: nil)
            dir = working_directory ? File.expand_path(working_directory) : Dir.pwd

            if sandbox_enabled? && sandbox_available?
              execute_sandboxed(command: command, timeout: timeout, dir: dir)
            else
              execute_direct(command: command, timeout: timeout, dir: dir)
            end
          end

          private

          def sandbox_enabled?
            Legion::Settings.dig(:chat, :sandboxed_commands, :enabled) == true
          rescue StandardError
            false
          end

          def sandbox_available?
            defined?(Legion::Extensions::Exec::Runners::Shell)
          end

          def execute_sandboxed(command:, timeout:, dir:)
            timeout_ms = timeout * 1000
            result = Legion::Extensions::Exec::Runners::Shell.execute(
              command: command, cwd: dir, timeout: timeout_ms
            )

            if result[:error] == :blocked
              "Command blocked by sandbox: #{result[:reason]}"
            elsif result[:error] == :timeout
              "[command timed out after #{timeout}s]: #{command}"
            elsif result[:success] == false && result[:error]
              "Error executing command: #{result[:error]}"
            else
              truncate_output(format_output(command, result[:stdout], result[:stderr], result[:exit_code]))
            end
          rescue StandardError => e
            "Error executing command: #{e.message}"
          end

          def execute_direct(command:, timeout:, dir:)
            stdout, stderr, status = Open3.popen3(command, chdir: dir) do |stdin, out, err, wait_thr|
              stdin.close
              out_reader = Thread.new { out.read }
              err_reader = Thread.new { err.read }

              unless wait_thr.join(timeout)
                ::Process.kill('TERM', wait_thr.pid)
                wait_thr.join(5) || ::Process.kill('KILL', wait_thr.pid)
                out_reader.kill
                err_reader.kill
                raise ::Timeout::Error, "command timed out after #{timeout}s"
              end

              [out_reader.value, err_reader.value, wait_thr.value]
            end

            truncate_output(format_output(command, stdout, stderr, status.exitstatus))
          rescue ::Timeout::Error
            "[command timed out after #{timeout}s]: #{command}"
          rescue StandardError => e
            "Error executing command: #{e.message}"
          end
          def format_output(command, stdout, stderr, exit_code)
            output = String.new
            output << "$ #{command}\n"
            output << stdout.to_s unless stdout.to_s.empty?
            output << stderr.to_s unless stderr.to_s.empty?
            output << "\n[exit code: #{exit_code}]"
            output
          end

          def truncate_output(text)
            max_chars = max_output_chars
            return text if text.length <= max_chars

            "#{text[0, max_chars]}\n\n[... truncated at #{max_chars} characters (#{text.length} total)]"
          end

          # Returns the max output chars from settings with fallback to constant.
          # Memory usage note: Still reads entire command output before truncation - this is intentional
          # to avoid complex streaming logic. For verbose commands, consider output redirection.
          def max_output_chars
            Legion::Settings.dig(:chat, :tools, :max_output_chars) || MAX_OUTPUT_CHARS
          rescue StandardError
            MAX_OUTPUT_CHARS
          end
        end
      end
    end
  end
end
