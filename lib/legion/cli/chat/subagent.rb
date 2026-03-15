# frozen_string_literal: true

require 'open3'
require 'legion/cli/chat_command'

module Legion
  module CLI
    class Chat
      module Subagent
        MAX_CONCURRENCY = 3
        TIMEOUT         = 300 # 5 minutes

        @running = []
        @mutex = Mutex.new
        @max_concurrency = MAX_CONCURRENCY

        class << self
          attr_accessor :max_concurrency

          def configure(max_concurrency: MAX_CONCURRENCY)
            @max_concurrency = max_concurrency
            @running = []
          end

          def spawn(task:, model: nil, provider: nil, on_complete: nil)
            return { error: "Max concurrency reached (#{@max_concurrency}). Wait for a subagent to finish." } if at_capacity?

            agent_id = "agent-#{Time.now.strftime('%H%M%S')}-#{rand(1000)}"

            thread = Thread.new do
              result = run_headless(task: task, model: model, provider: provider)
              @mutex.synchronize { @running.delete_if { |a| a[:id] == agent_id } }
              on_complete&.call(agent_id, result)
            rescue StandardError => e
              @mutex.synchronize { @running.delete_if { |a| a[:id] == agent_id } }
              on_complete&.call(agent_id, { error: e.message })
            end

            entry = { id: agent_id, task: task, thread: thread, started_at: Time.now }
            @mutex.synchronize { @running << entry }

            { id: agent_id, status: 'running', task: task }
          end

          def running
            @mutex.synchronize { @running.map { |a| { id: a[:id], task: a[:task], elapsed: Time.now - a[:started_at] } } }
          end

          def running_count
            @mutex.synchronize { @running.length }
          end

          def at_capacity?
            @mutex.synchronize { @running.length >= @max_concurrency }
          end

          def wait_all(timeout: TIMEOUT)
            deadline = Time.now + timeout
            @running.each do |agent|
              remaining = deadline - Time.now
              break if remaining <= 0

              agent[:thread]&.join(remaining)
            end
          end

          private

          def run_headless(task:, model: nil, provider: nil)
            cmd = ['legion', 'chat', 'prompt', task]
            cmd += ['--model', model] if model
            cmd += ['--provider', provider] if provider
            cmd += ['--output-format', 'json']

            stdout, stderr, status = Open3.capture3(*cmd, chdir: Dir.pwd)

            {
              exit_code: status.exitstatus,
              output:    stdout.strip,
              error:     stderr.strip.empty? ? nil : stderr.strip
            }
          rescue StandardError => e
            { exit_code: 1, output: nil, error: e.message }
          end
        end
      end
    end
  end
end
