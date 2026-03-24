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
            formatter.error('No matching capability found')
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
          return nil unless defined?(Legion::Extensions::Catalog::Registry)

          matches = Legion::Extensions::Catalog::Registry.find_by_intent(intent)
          return nil if matches.empty?

          best = matches.first
          runner_class = build_runner_class(best.extension, best.runner)

          if defined?(Legion::Ingress)
            Legion::Ingress.run(
              payload:      { intent: intent },
              runner_class: runner_class,
              function:     best.function,
              source:       'cli:do'
            )
          else
            { matched: best.name, runner_class: runner_class, function: best.function,
              status: 'resolved', note: 'Daemon not running; cannot execute. Start with: legion start' }
          end
        end

        def try_llm_classify(intent)
          return nil unless defined?(Legion::Extensions::Catalog::Registry) && defined?(Legion::LLM)

          caps = Legion::Extensions::Catalog::Registry.capabilities
          return nil if caps.empty?

          catalog = caps.map { |c| "#{c.name}: #{c.description || "#{c.extension} #{c.runner}##{c.function}"}" }
          prompt = "Given these capabilities:\n#{catalog.join("\n")}\n\n" \
                   "Which capability best matches this intent: \"#{intent}\"?\n" \
                   'Reply with ONLY the capability name (e.g., lex-consul:health_check:run). ' \
                   'If none match, reply NONE.'

          response = Legion::LLM.ask(
            message: prompt,
            caller:  { extension: 'legionio', tool: 'do_command', tier: 'cli' }
          )
          chosen = response.is_a?(Hash) ? response[:response].to_s.strip : response.to_s.strip
          return nil if chosen.empty? || chosen.upcase == 'NONE'

          cap = Legion::Extensions::Catalog::Registry.find(name: chosen)
          return nil unless cap

          runner_class = build_runner_class(cap.extension, cap.runner)
          { matched: cap.name, runner_class: runner_class, function: cap.function,
            status: 'resolved', source: 'llm',
            note: 'Daemon not running; cannot execute. Start with: legion start' }
        rescue StandardError => e
          Legion::Logging.debug("DoCommand#try_llm_classify failed: #{e.message}") if defined?(Legion::Logging)
          nil
        end

        def resolve_runner_class(intent)
          return nil unless defined?(Legion::Extensions::Catalog::Registry)

          matches = Legion::Extensions::Catalog::Registry.find_by_intent(intent)
          return nil if matches.empty?

          build_runner_class(matches.first.extension, matches.first.runner)
        end

        def resolve_function(intent)
          return nil unless defined?(Legion::Extensions::Catalog::Registry)

          matches = Legion::Extensions::Catalog::Registry.find_by_intent(intent)
          return nil if matches.empty?

          matches.first.function
        end

        def build_runner_class(extension, runner)
          ext_part = extension.delete_prefix('lex-').split(/[-_]/).map(&:capitalize).join
          "Legion::Extensions::#{ext_part}::Runners::#{runner}"
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
