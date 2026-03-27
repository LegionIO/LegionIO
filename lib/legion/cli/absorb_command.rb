# frozen_string_literal: true

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
        Connection.ensure_settings
        out = formatter
        result = Legion::Extensions::Actors::AbsorberDispatch.dispatch(
          input:   input_url,
          context: { scope: options[:scope]&.to_sym }
        )

        if options[:json]
          out.json(result)
        elsif result[:success]
          out.success("Absorbed: #{input_url}")
          out.detail(absorber: result[:absorber], job_id: result[:job_id])
        else
          out.warn("Failed: #{result[:error]}")
        end
      end

      desc 'list', 'List registered absorber patterns'
      def list
        Connection.ensure_settings
        out = formatter
        patterns = Legion::Extensions::Absorbers::PatternMatcher.list

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
        Connection.ensure_settings
        out = formatter
        absorber = Legion::Extensions::Absorbers::PatternMatcher.resolve(input_url)

        if options[:json]
          out.json({ input: input_url, absorber: absorber&.name, match: !absorber.nil? })
        elsif absorber
          out.success("#{input_url} -> #{absorber.name}")
        else
          out.warn("No absorber registered for: #{input_url}")
        end
      end

      no_commands do
        def formatter
          @formatter ||= Output::Formatter.new(json: options[:json], color: !options[:no_color])
        end
      end
    end
  end
end
