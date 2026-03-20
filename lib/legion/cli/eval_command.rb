# frozen_string_literal: true

require 'json'

module Legion
  module CLI
    class Eval < Thor
      def self.exit_on_failure?
        true
      end

      class_option :json,       type: :boolean, default: false, desc: 'Output as JSON'
      class_option :no_color,   type: :boolean, default: false, desc: 'Disable color output'
      class_option :verbose,    type: :boolean, default: false, aliases: ['-V'], desc: 'Verbose logging'
      class_option :config_dir, type: :string, desc: 'Config directory path'

      desc 'run', 'Run eval against a dataset and gate on a threshold'
      map 'run' => :execute
      option :dataset,   type: :string,  required: true,  aliases: '-d', desc: 'Dataset name'
      option :threshold, type: :numeric, default: 0.8,    aliases: '-t', desc: 'Pass/fail threshold (0.0-1.0)'
      option :evaluator, type: :string,  default: nil,    aliases: '-e', desc: 'Evaluator name'
      option :exit_code, type: :boolean, default: false,                 desc: 'Exit 1 if gate fails (for CI use)'
      def execute
        setup_connection
        require_eval!
        require_dataset!

        rows   = fetch_dataset_rows(options[:dataset])
        report = run_evaluations(rows)

        avg_score = report.dig(:summary, :avg_score) || 0.0
        passed    = avg_score >= options[:threshold]

        ci_report = build_ci_report(report, avg_score, passed)

        if options[:json]
          formatter.json(ci_report)
        else
          render_human_report(ci_report, avg_score, passed)
        end

        exit(1) if options[:exit_code] && !passed
      ensure
        Connection.shutdown
      end

      no_commands do # rubocop:disable Metrics/BlockLength
        def formatter
          @formatter ||= Output::Formatter.new(
            json:  options[:json],
            color: !options[:no_color]
          )
        end

        def setup_connection
          Connection.config_dir = options[:config_dir] if options[:config_dir]
          Connection.log_level  = options[:verbose] ? 'debug' : 'error'
          Connection.ensure_data
        end

        def require_eval!
          return if defined?(Legion::Extensions::Eval::Client)

          raise CLI::Error, 'lex-eval extension is not loaded. Install and enable it first.'
        end

        def require_dataset!
          return if defined?(Legion::Extensions::Dataset::Client)

          raise CLI::Error, 'lex-dataset extension is not loaded. Install and enable it first.'
        end

        def fetch_dataset_rows(name)
          client = Legion::Extensions::Dataset::Client.new
          result = client.get_dataset(name: name)
          raise CLI::Error, "Dataset '#{name}' not found" if result[:error]

          result[:rows].map do |r|
            { input: r[:input], output: r[:input], expected: r[:expected_output] }
          end
        end

        def run_evaluations(rows)
          Legion::Extensions::Eval::Client.new.run_evaluation(inputs: rows)
        end

        def build_ci_report(report, avg_score, passed)
          {
            dataset:   options[:dataset],
            evaluator: report[:evaluator],
            threshold: options[:threshold],
            avg_score: avg_score,
            passed:    passed,
            summary:   report[:summary],
            results:   report[:results],
            timestamp: Time.now.utc.iso8601
          }
        end

        def render_human_report(report, avg_score, passed)
          out = formatter
          out.header("Eval Gate: #{report[:dataset]}")
          out.spacer
          out.detail({
                       dataset:   report[:dataset],
                       evaluator: report[:evaluator],
                       total:     report.dig(:summary, :total),
                       passed:    report.dig(:summary, :passed),
                       failed:    report.dig(:summary, :failed),
                       avg_score: format('%.3f', avg_score),
                       threshold: report[:threshold],
                       gate:      passed ? 'PASSED' : 'FAILED'
                     })
          out.spacer

          if passed
            out.success("Gate PASSED (avg_score=#{format('%.3f', avg_score)} >= threshold=#{report[:threshold]})")
          else
            out.warn("Gate FAILED (avg_score=#{format('%.3f', avg_score)} < threshold=#{report[:threshold]})")
          end
        end
      end
    end
  end
end
