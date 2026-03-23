# frozen_string_literal: true

require 'net/http'
require 'json'

module Legion
  module CLI
    class Apollo < Thor
      def self.exit_on_failure?
        true
      end

      class_option :json,     type: :boolean, default: false, desc: 'Output as JSON'
      class_option :no_color, type: :boolean, default: false, desc: 'Disable color output'
      class_option :port,     type: :numeric, default: 4567, desc: 'API port'
      class_option :host,     type: :string,  default: '127.0.0.1', desc: 'API host'

      desc 'status', 'Check Apollo knowledge graph availability'
      def status
        data = api_get('/api/apollo/status')
        if options[:json]
          formatter.json(data)
        else
          formatter.header('Apollo Status')
          formatter.detail({
                             'Available'      => (data[:available] || false).to_s,
                             'Data Connected' => (data[:data_connected] || false).to_s
                           })
        end
      end
      default_task :status

      desc 'stats', 'Show knowledge graph statistics'
      def stats
        data = api_get('/api/apollo/stats')
        if options[:json]
          formatter.json(data)
        else
          formatter.header('Apollo Knowledge Graph')
          formatter.detail({
                             'Total Entries'  => (data[:total_entries] || 0).to_s,
                             'Recent (24h)'   => (data[:recent_24h] || 0).to_s,
                             'Avg Confidence' => (data[:avg_confidence] || 0.0).to_s
                           })

          show_breakdown('By Status', data[:by_status]) if data[:by_status]
          show_breakdown('By Content Type', data[:by_content_type]) if data[:by_content_type]
        end
      end

      desc 'query QUERY', 'Search the knowledge graph'
      option :limit, type: :numeric, default: 10, desc: 'Max results'
      option :domain, type: :string, desc: 'Filter by knowledge domain'
      def query(search_query)
        body = { query: search_query, limit: options[:limit], domain: options[:domain] }
        data = api_post('/api/apollo/query', body)
        if options[:json]
          formatter.json(data)
        else
          entries = data[:entries] || []
          formatter.header("Apollo Query (#{entries.size} results)")
          entries.each_with_index do |entry, idx|
            puts "  #{idx + 1}. [#{entry[:content_type]}] #{truncate(entry[:content].to_s, 120)}"
            puts "     confidence: #{entry[:confidence]} | status: #{entry[:status]}"
          end
          puts '  No results found.' if entries.empty?
        end
      end

      desc 'ingest CONTENT', 'Ingest knowledge into the graph'
      option :content_type, type: :string, default: 'observation', desc: 'Content type (fact/concept/procedure/association/observation)'
      option :tags, type: :string, desc: 'Comma-separated tags'
      option :domain, type: :string, desc: 'Knowledge domain'
      def ingest(content)
        body = {
          content:          content,
          content_type:     options[:content_type],
          tags:             options[:tags]&.split(',') || [],
          source_agent:     'cli',
          source_channel:   'cli',
          knowledge_domain: options[:domain]
        }
        data = api_post('/api/apollo/ingest', body)
        if options[:json]
          formatter.json(data)
        else
          formatter.header('Apollo Ingest')
          if data[:success]
            formatter.success("Entry created (id: #{data[:id]})")
          else
            formatter.warn("Ingest failed: #{data[:error]}")
          end
        end
      end

      desc 'maintain ACTION', 'Run maintenance (decay_cycle or corroboration)'
      def maintain(action)
        data = api_post('/api/apollo/maintenance', { action: action })
        if options[:json]
          formatter.json(data)
        else
          formatter.header("Apollo Maintenance: #{action}")
          formatter.detail(data.transform_values(&:to_s))
        end
      end

      no_commands do
        def formatter
          @formatter ||= Output::Formatter.new(json: options[:json], color: !options[:no_color])
        end

        private

        def api_get(path)
          uri = URI("http://#{options[:host]}:#{options[:port]}#{path}")
          http = Net::HTTP.new(uri.host, uri.port)
          http.open_timeout = 3
          http.read_timeout = 10
          response = http.get(uri.path)
          parsed = ::JSON.parse(response.body, symbolize_names: true)
          parsed[:data] || parsed
        rescue StandardError => e
          { error: e.message }
        end

        def api_post(path, body)
          uri = URI("http://#{options[:host]}:#{options[:port]}#{path}")
          http = Net::HTTP.new(uri.host, uri.port)
          http.open_timeout = 3
          http.read_timeout = 30
          req = Net::HTTP::Post.new(uri.path, 'Content-Type' => 'application/json')
          req.body = ::JSON.dump(body)
          response = http.request(req)
          parsed = ::JSON.parse(response.body, symbolize_names: true)
          parsed[:data] || parsed
        rescue StandardError => e
          { error: e.message }
        end

        def show_breakdown(title, hash)
          return if hash.nil? || hash.empty?

          formatter.spacer
          formatter.header(title)
          hash.each { |key, count| puts "  #{key}: #{count}" }
        end

        def truncate(text, max)
          text.length > max ? "#{text[0..(max - 3)]}..." : text
        end
      end
    end
  end
end
