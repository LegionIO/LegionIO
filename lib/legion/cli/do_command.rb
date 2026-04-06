# frozen_string_literal: true

module Legion
  module CLI
    module DoCommand
      class << self
        def run(intent, formatter, options)
          if intent.strip.empty?
            formatter.error('Usage: legion do "describe what you want"')
            raise SystemExit, 1
          end

          formatter.detail("Routing intent: #{intent}")

          result = try_daemon(intent, options) || try_in_process(intent) || try_llm_classify(intent)

          if result.nil?
            formatter.error('No matching tool found')
            formatter.detail('Try: legion lex list  (to see available extensions)')
            raise SystemExit, 1
          end

          display_result(result, formatter, options)
        end

        private

        def try_daemon(intent, options)
          require 'net/http'
          require 'json'

          port = daemon_port(options)
          uri = URI("http://localhost:#{port}/api/tasks")
          body = ::JSON.generate({
                                   runner_class:  resolve_runner_class(intent) || return,
                                   function:      resolve_function(intent) || return,
                                   payload:       { intent: intent },
                                   source:        'cli:do',
                                   check_subtask: false,
                                   generate_task: true
                                 })

          http = Net::HTTP.new(uri.host, uri.port)
          http.open_timeout = 3
          http.read_timeout = 30
          request = Net::HTTP::Post.new(uri.path, 'Content-Type' => 'application/json')
          request.body = body

          response = http.request(request)
          ::JSON.parse(response.body, symbolize_names: true)
        rescue Errno::ECONNREFUSED, Net::OpenTimeout
          nil
        end

        def try_in_process(intent)
          return nil unless defined?(Legion::Tools::Registry)

          matched = Legion::Tools::Registry.all_tools.find do |t|
            t.tool_name.include?(intent.downcase.tr(' ', '_')) ||
              t.description.downcase.include?(intent.downcase)
          end
          return nil unless matched

          begin
            result = matched.call
            result.is_a?(Hash) ? result.merge(matched: matched.tool_name) : { matched: matched.tool_name, result: result }
          rescue ArgumentError
            { matched: matched.tool_name, status: 'requires_daemon',
              note: 'Tool requires arguments; start the daemon and retry: legion start' }
          end
        end

        def try_llm_classify(intent)
          return nil unless defined?(Legion::Tools::Registry) && defined?(Legion::LLM)

          tools = Legion::Tools::Registry.all_tools
          return nil if tools.empty?

          catalog = tools.map { |t| "#{t.tool_name}: #{t.description}" }
          prompt = "Given these tools:\n#{catalog.join("\n")}\n\n" \
                   "Which tool best matches this intent: \"#{intent}\"?\n" \
                   'Reply with ONLY the tool name (e.g., legion.do). ' \
                   'If none match, reply NONE.'

          response = Legion::LLM.ask(
            message: prompt,
            caller:  { extension: 'legionio', tool: 'do_command', tier: 'cli' }
          )
          chosen = response.is_a?(Hash) ? response[:response].to_s.strip : response.to_s.strip
          return nil if chosen.empty? || chosen.upcase == 'NONE'

          tool = Legion::Tools::Registry.find(chosen)
          return nil unless tool

          { matched: tool.tool_name, status: 'resolved', source: 'llm',
            note: 'Daemon not running; cannot execute. Start with: legion start' }
        rescue StandardError => e
          Legion::Logging.debug("DoCommand#try_llm_classify failed: #{e.message}") if defined?(Legion::Logging)
          nil
        end

        def resolve_runner_class(intent)
          return nil unless defined?(Legion::Tools::Registry)

          matched = Legion::Tools::Registry.all_tools.find do |t|
            t.description.downcase.include?(intent.downcase)
          end
          return nil unless matched.respond_to?(:extension) && matched.respond_to?(:runner)

          build_runner_class(matched.extension, matched.runner)
        end

        def resolve_function(intent)
          return nil unless defined?(Legion::Tools::Registry)

          matched = Legion::Tools::Registry.all_tools.find do |t|
            t.description.downcase.include?(intent.downcase)
          end
          return nil unless matched

          matched.tool_name.split('.').last
        end

        def build_runner_class(extension, runner)
          ext_part = extension.to_s.delete_prefix('lex-').split(/[-_]/).map(&:capitalize).join
          runner_part = runner.to_s.split('_').map(&:capitalize).join
          "Legion::Extensions::#{ext_part}::Runners::#{runner_part}"
        end

        def daemon_port(options)
          options[:http_port] || begin
            require 'legion/settings'
            Legion::Settings.load unless Legion::Settings.loaded?
            Legion::Settings.dig(:api, :port) || 4567
          rescue StandardError
            4567
          end
        end

        def display_result(result, formatter, options)
          if options[:json]
            formatter.json(result)
          elsif result.is_a?(Hash) && result[:error]
            formatter.error(result.dig(:error, :message) || result[:error].to_s)
          elsif result.is_a?(Hash) && result[:data]
            formatter.success('Task dispatched')
            formatter.detail(result[:data])
          elsif result.is_a?(Hash) && result[:matched]
            formatter.success("Matched: #{result[:matched]}")
            formatter.detail(result.except(:matched))
          else
            formatter.success('Done')
            formatter.detail(result)
          end
        end
      end
    end
  end
end
