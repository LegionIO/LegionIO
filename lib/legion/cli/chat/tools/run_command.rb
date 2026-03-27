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
          description 'Execute a shell command and return its output. Use for running tests, builds, git commands, etc.'
          param :command, type: 'string', desc: 'The shell command to execute'
          param :timeout, type: 'integer', desc: 'Timeout in seconds (default: 120)', required: false
          param :working_directory, type: 'string', desc: 'Working directory (default: current dir)', required: false

          def execute(command:, timeout: 120, working_directory: nil)
            dir = working_directory ? File.expand_path(working_directory) : Dir.pwd

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

            output = String.new
            output << "$ #{command}\n"
            output << stdout unless stdout.empty?
            output << stderr unless stderr.empty?
            output << "\n[exit code: #{status.exitstatus}]"
            output
          rescue ::Timeout::Error
            "[command timed out after #{timeout}s]: #{command}"
          rescue StandardError => e
            "Error executing command: #{e.message}"
          end
        end
      end
    end
  end
end
