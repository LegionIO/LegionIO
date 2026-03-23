# frozen_string_literal: true

require 'ruby_llm'
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
        class SearchTraces < RubyLLM::Tool
          description 'Search cognitive memory traces for information from Teams messages, conversations, ' \
                      'meetings, people, and other ingested data. Use this when the user asks about what ' \
                      'someone said, conversation topics, meeting details, or any previously observed context.'
          param :query, type: 'string', desc: 'Natural language search query (e.g., "what did Bob say about deployment")'
          param :person, type: 'string', desc: 'Filter by person name (matches peer:Name domain tags)', required: false
          param :domain, type: 'string', desc: 'Filter by domain tag (e.g., "teams", "meeting", "conversation")', required: false
          param :trace_type, type: 'string', desc: 'Filter by trace type: episodic, semantic, sensory, identity', required: false
          param :limit, type: 'integer', desc: 'Max results to return (default: 20)', required: false

          STRUCTURED_FIELDS = [
            ['Person', 'displayName', :displayName, 'peer', :peer],
            ['Summary', 'summary', :summary],
            ['Subject', 'subject', :subject],
            ['Team', 'team', :team],
            ['Job', 'jobTitle', :jobTitle]
          ].freeze

          def execute(query:, person: nil, domain: nil, trace_type: nil, limit: nil)
            return 'Memory trace system not available (lex-agentic-memory not loaded).' unless trace_store_available?

            limit = (limit || 20).clamp(1, 50)
            traces = collect_traces(person: person, domain: domain, trace_type: trace_type, limit: limit * 3)
            return 'No memory traces found matching those filters.' if traces.empty?

            ranked = rank_by_query(traces: traces, query: query)
            results = ranked.first(limit)
            return 'No traces matched your query.' if results.empty?

            format_results(results)
          rescue StandardError => e
            Legion::Logging.warn("SearchTraces#execute failed: #{e.message}") if defined?(Legion::Logging)
            "Error searching traces: #{e.message}"
          end

          private

          def trace_store_available?
            load_trace_gem unless defined?(Legion::Extensions::Agentic::Memory::Trace)
            defined?(Legion::Extensions::Agentic::Memory::Trace) &&
              Legion::Extensions::Agentic::Memory::Trace.respond_to?(:shared_store)
          end

          def load_trace_gem
            require 'legion/extensions/agentic/memory/trace'
          rescue LoadError
            nil
          end

          def store
            Legion::Extensions::Agentic::Memory::Trace.shared_store
          end

          def collect_traces(person:, domain:, trace_type:, limit:)
            if person
              candidates = []
              %W[peer:#{person} sender:#{person}].each do |tag|
                candidates += store.retrieve_by_domain(tag, min_strength: 0.01, limit: limit)
              end
              candidates += store.retrieve_by_domain('teams', min_strength: 0.01, limit: limit) if candidates.size < 5
              return candidates.uniq { |t| t[:trace_id] }
            end

            return store.retrieve_by_domain(domain, min_strength: 0.01, limit: limit) if domain

            if trace_type
              sym = trace_type.to_sym
              return store.retrieve_by_type(sym, min_strength: 0.01, limit: limit)
            end

            store.all_traces(min_strength: 0.01).sort_by { |t| -t[:strength] }.first(limit)
          end

          def rank_by_query(traces:, query:)
            keywords = query.downcase.split(/\s+/).reject { |w| w.length < 3 }
            return traces if keywords.empty?

            scored = traces.filter_map do |trace|
              text = extract_searchable_text(trace)
              next nil if text.empty?

              score = compute_score(text: text, keywords: keywords, trace: trace)
              next nil if score.zero?

              { trace: trace, score: score }
            end

            scored.sort_by { |s| -s[:score] }.map { |s| s[:trace] }
          end

          def extract_searchable_text(trace)
            payload = trace[:content_payload] || trace[:content]
            text = case payload
                   when String
                     begin
                       parsed = ::JSON.parse(payload)
                       flatten_to_text(parsed)
                     rescue ::JSON::ParserError
                       payload
                     end
                   when Hash
                     flatten_to_text(payload)
                   else
                     payload.to_s
                   end
            text.downcase
          end

          def flatten_to_text(obj)
            case obj
            when Hash
              obj.values.map { |v| flatten_to_text(v) }.join(' ')
            when Array
              obj.map { |v| flatten_to_text(v) }.join(' ')
            else
              obj.to_s
            end
          end

          def compute_score(text:, keywords:, trace:)
            keyword_hits = keywords.count { |kw| text.include?(kw) }
            return 0.0 if keyword_hits.zero?

            keyword_ratio = keyword_hits.to_f / keywords.size
            strength_bonus = trace[:strength] || 0.0
            recency_bonus = recency_score(trace[:created_at])

            (keyword_ratio * 10.0) + (strength_bonus * 2.0) + (recency_bonus * 3.0)
          end

          def recency_score(created_at)
            return 0.0 unless created_at.is_a?(Time)

            age_hours = (Time.now.utc - created_at) / 3600.0
            1.0 / (1.0 + (age_hours / 24.0))
          end

          def format_results(traces)
            parts = traces.map.with_index(1) do |trace, idx|
              payload = trace[:content_payload] || trace[:content]
              content = format_payload(payload)
              tags = (trace[:domain_tags] || []).join(', ')
              age = format_age(trace[:created_at])

              "#{idx}. [#{trace[:trace_type]}] #{content}\n   tags: #{tags} | strength: #{(trace[:strength] || 0).round(2)} | #{age}"
            end

            "Found #{traces.size} matching traces:\n\n#{parts.join("\n\n")}"
          end

          def format_payload(payload)
            data = parse_payload(payload)
            return truncate(data, 300) if data.is_a?(String)

            format_structured(data)
          end

          def parse_payload(payload)
            case payload
            when String
              ::JSON.parse(payload)
            when Hash
              payload
            else
              payload.to_s
            end
          rescue ::JSON::ParserError
            payload
          end

          def format_structured(data)
            parts = STRUCTURED_FIELDS.filter_map do |label, *keys|
              val = keys.lazy.filter_map { |k| data[k] }.first
              "#{label}: #{val}" if val
            end

            return parts.join(' | ') unless parts.empty?

            truncate(flatten_to_text(data), 300)
          end

          def truncate(text, max)
            text.length > max ? "#{text[0..(max - 3)]}..." : text
          end

          def format_age(created_at)
            return 'age unknown' unless created_at.is_a?(Time)

            seconds = Time.now.utc - created_at
            if seconds < 3600
              "#{(seconds / 60).to_i}m ago"
            elsif seconds < 86_400
              "#{(seconds / 3600).to_i}h ago"
            else
              "#{(seconds / 86_400).to_i}d ago"
            end
          end
        end
      end
    end
  end
end
