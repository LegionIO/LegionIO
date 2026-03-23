# frozen_string_literal: true

require 'ruby_llm'
require 'net/http'
require 'json'

begin
  require 'legion/cli/chat_command'
rescue LoadError
  nil
end

module Legion
  module CLI
    class Chat
      module Tools
        class TriggerDream < RubyLLM::Tool
          description 'Trigger or view dream cycles on the running Legion daemon. Dream cycles consolidate ' \
                      'memory traces, detect contradictions, walk associations, and promote knowledge to Apollo. ' \
                      'Use action "trigger" to start a new cycle, or "journal" to view the most recent dream report.'
          param :action, type:     'string',
                         desc:     'Action: "trigger" (default) to run dream cycle, "journal" to view latest dream report',
                         required: false

          DEFAULT_PORT = 4567
          DEFAULT_HOST = '127.0.0.1'

          DREAM_RUNNER = 'Legion::Extensions::Agentic::Imagination::Dream::Runners::DreamCycle'
          DREAM_FUNCTION = 'execute_dream_cycle'

          def execute(action: 'trigger')
            case action.to_s
            when 'journal' then handle_journal
            else handle_trigger
            end
          rescue Errno::ECONNREFUSED
            'Legion daemon not running (cannot reach API).'
          rescue StandardError => e
            Legion::Logging.warn("TriggerDream#execute failed: #{e.message}") if defined?(Legion::Logging)
            "Error: #{e.message}"
          end

          private

          def handle_trigger
            body = ::JSON.generate({
                                     runner_class:  DREAM_RUNNER,
                                     function:      DREAM_FUNCTION,
                                     async:         true,
                                     check_subtask: false,
                                     generate_task: false
                                   })
            response = api_post('/api/tasks', body)
            return "Dream cycle triggered. #{format_task_id(response)}" if response[:data]

            "Dream trigger failed: #{response.dig(:error, :message) || 'unknown error'}"
          end

          def handle_journal
            journal_path = find_latest_journal
            return 'No dream journal entries found.' unless journal_path

            content = File.read(journal_path, encoding: 'utf-8')
            truncate(content, 2000)
          end

          def find_latest_journal
            paths = dream_log_dirs.flat_map { |dir| Dir.glob(File.join(dir, 'dream-*.md')) }
            paths.last
          end

          def dream_log_dirs
            dirs = []
            dirs << File.expand_path('logs/dreams', gem_path) if gem_path
            dirs << File.expand_path('.legion/dreams', Dir.pwd)
            dirs << File.expand_path('~/.legionio/dreams')
            dirs.select { |d| Dir.exist?(d) }
          end

          def gem_path
            spec = Gem::Specification.find_by_name('lex-agentic-imagination')
            spec&.gem_dir
          rescue Gem::MissingSpecError
            nil
          end

          def format_task_id(response)
            task_id = response.dig(:data, :task_id) || response.dig(:data, :id)
            task_id ? "Task ID: #{task_id}" : ''
          end

          def truncate(text, max)
            text.length > max ? "#{text[0..(max - 4)]}..." : text
          end

          def api_post(path, body)
            uri = URI("http://#{DEFAULT_HOST}:#{api_port}#{path}")
            http = Net::HTTP.new(uri.host, uri.port)
            http.open_timeout = 5
            http.read_timeout = 10
            request = Net::HTTP::Post.new(uri.path, 'Content-Type' => 'application/json')
            request.body = body
            response = http.request(request)
            ::JSON.parse(response.body, symbolize_names: true)
          end

          def api_port
            return DEFAULT_PORT unless defined?(Legion::Settings)

            Legion::Settings[:api]&.dig(:port) || DEFAULT_PORT
          rescue StandardError
            DEFAULT_PORT
          end
        end
      end
    end
  end
end
