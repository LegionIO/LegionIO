# frozen_string_literal: true

require_relative 'api_client'

module Legion
  module CLI
    class AbsorbCommand < Thor
      def self.exit_on_failure?
        true
      end

      class_option :json,     type: :boolean, default: false, desc: 'Output as JSON'
      class_option :no_color, type: :boolean, default: false, desc: 'Disable color output'

      desc 'url URL', 'Absorb content from a URL'
      option :scope, type: :string, default: 'global', desc: 'Knowledge scope (global/local/all)'
      def url(input_url)
        out = formatter
        result = api_post('/api/absorbers/dispatch', url: input_url, context: { scope: options[:scope] })

        if options[:json]
          out.json(result)
        elsif result[:success]
          out.success("Dispatched: #{input_url}")
          puts "  absorber: #{result[:absorber]}"
          puts "  job_id:   #{result[:job_id]}"
          puts '  Processing in background. Check daemon logs for progress.'
        else
          out.warn("Failed: #{result[:error]}")
        end
      end

      desc 'list', 'List registered absorber patterns'
      def list
        out = formatter
        patterns = fetch_absorbers

        if options[:json]
          out.json(patterns.map { |p| { type: p[:type], value: p[:value], description: p[:description] } })
        elsif patterns.empty?
          out.warn('No absorbers registered')
        else
          headers = %w[Type Pattern Description]
          rows = patterns.map do |p|
            [p[:type].to_s, p[:value], p[:description] || '']
          end
          out.header('Registered Absorbers')
          out.table(headers, rows)
        end
      end

      desc 'resolve URL', 'Show which absorber would handle a URL (dry run)'
      def resolve(input_url)
        out = formatter
        result = fetch_resolve(input_url)

        if options[:json]
          out.json(result)
        elsif result[:match]
          out.success("#{input_url} -> #{result[:absorber]}")
        else
          out.warn("No absorber registered for: #{input_url}")
        end
      end

      no_commands do
        include ApiClient

        def formatter
          @formatter ||= Output::Formatter.new(json: options[:json], color: !options[:no_color])
        end

        def fetch_absorbers
          api_get('/api/absorbers')
        end

        def fetch_resolve(input_url)
          api_get("/api/absorbers/resolve?url=#{URI.encode_www_form_component(input_url)}")
        end
      end
    end
  end
end
