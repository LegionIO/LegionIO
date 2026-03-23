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
        class GraphExplore < RubyLLM::Tool
          description 'Explore the Apollo knowledge graph topology: view domains, agent expertise, ' \
                      'relation types, and disputed entries. Use this to understand the structure ' \
                      'and health of the knowledge graph beyond basic stats.'

          param :action,
                type:     :string,
                desc:     'Action: "topology" (domain/agent/relation overview), ' \
                          '"expertise" (agent proficiency per domain), ' \
                          '"disputed" (show disputed entries)',
                required: false

          DEFAULT_PORT = 4567
          DEFAULT_HOST = '127.0.0.1'

          def execute(action: 'topology')
            case action.to_s
            when 'expertise' then format_expertise
            when 'disputed'  then format_disputed
            else format_topology
            end
          rescue Errno::ECONNREFUSED
            'Apollo unavailable (daemon not running).'
          rescue StandardError => e
            Legion::Logging.warn("GraphExplore#execute failed: #{e.message}") if defined?(Legion::Logging)
            "Error exploring knowledge graph: #{e.message}"
          end

          private

          def format_topology
            data = fetch_json('/api/apollo/graph')
            return "Apollo error: #{data[:error]}" if data[:error]

            lines = ["Apollo Knowledge Graph Topology:\n"]

            lines << '  Domains:'
            (data[:domains] || {}).sort_by { |_, c| -c }.each do |domain, count|
              lines << format('    %<d>-25s %<c>d entries', d: domain, c: count)
            end

            lines << ''
            lines << '  Contributing Agents:'
            (data[:agents] || {}).sort_by { |_, c| -c }.first(10).each do |agent, count|
              lines << format('    %<a>-25s %<c>d entries', a: agent, c: count)
            end

            lines << ''
            lines << '  Relation Types:'
            (data[:relation_types] || {}).sort_by { |_, c| -c }.each do |rtype, count|
              lines << format('    %<r>-20s %<c>d', r: rtype, c: count)
            end

            lines << ''
            lines << format('  Total Relations: %<v>d', v: data[:total_relations] || 0)
            lines << format('  Confirmed: %<v>d  Candidates: %<v2>d  Disputed: %<v3>d',
                            v: data[:confirmed] || 0, v2: data[:candidates] || 0, v3: data[:disputed_entries] || 0)

            lines.join("\n")
          end

          def format_expertise
            data = fetch_json('/api/apollo/expertise')
            return "Apollo error: #{data[:error]}" if data[:error]

            lines = ["Apollo Agent Expertise Map:\n"]
            lines << format('  Agents: %<a>d  Domains: %<d>d', a: data[:total_agents] || 0, d: data[:total_domains] || 0)

            (data[:domains] || {}).each do |domain, agents|
              lines << ''
              lines << "  #{domain}:"
              Array(agents).each do |agent|
                bar = proficiency_bar(agent[:proficiency] || 0.0)
                lines << format('    %<a>-20s %<bar>s %<p>5.1f%%  (%<c>d entries)',
                                a: agent[:agent_id], bar: bar, p: (agent[:proficiency] || 0.0) * 100,
                                c: agent[:entry_count] || 0)
              end
            end

            lines.join("\n")
          end

          def format_disputed
            data = fetch_json('/api/apollo/query', method: :post,
                                                   body:   { status: ['disputed'], limit: 20, query: '*',
                                                           min_confidence: 0.0 })
            return "Apollo error: #{data[:error]}" if data[:error]

            entries = data[:entries] || []
            return 'No disputed entries in the knowledge graph.' if entries.empty?

            lines = ["Disputed Knowledge Entries (#{entries.size}):\n"]
            entries.each_with_index do |entry, idx|
              conf = entry[:confidence] ? format(' (conf: %.2f)', entry[:confidence]) : ''
              tags = entry[:tags]&.any? ? " [#{Array(entry[:tags]).join(', ')}]" : ''
              lines << "  #{idx + 1}. ##{entry[:id]}#{conf}#{tags}"
              lines << "     #{truncate(entry[:content], 120)}"
              lines << "     source: #{entry[:source_agent] || 'unknown'}"
            end

            lines.join("\n")
          end

          def fetch_json(path, method: :get, body: nil)
            uri = URI("http://#{DEFAULT_HOST}:#{apollo_port}#{path}")
            http = Net::HTTP.new(uri.host, uri.port)
            http.open_timeout = 3
            http.read_timeout = 10

            response = if method == :post
                         req = Net::HTTP::Post.new(uri.path, 'Content-Type' => 'application/json')
                         req.body = ::JSON.dump(body) if body
                         http.request(req)
                       else
                         http.get(uri.request_uri)
                       end

            parsed = ::JSON.parse(response.body, symbolize_names: true)
            parsed[:data] || parsed
          end

          def apollo_port
            return DEFAULT_PORT unless defined?(Legion::Settings)

            Legion::Settings[:api]&.dig(:port) || DEFAULT_PORT
          rescue StandardError
            DEFAULT_PORT
          end

          def proficiency_bar(value)
            filled = (value * 10).round.clamp(0, 10)
            ('#' * filled) + ('-' * (10 - filled))
          end

          def truncate(text, max)
            return '' if text.nil?

            text.length > max ? "#{text[0...max]}..." : text
          end
        end
      end
    end
  end
end
