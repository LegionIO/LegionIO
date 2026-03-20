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

      desc 'experiments', 'List all tracked experiments'
      def experiments
        setup_connection
        require_dataset!

        client = Legion::Extensions::Dataset::Client.new
        rows   = client.list_experiments
        out    = formatter

        if rows.empty?
          out.warn('no experiments found')
          return
        end

        if options[:json]
          out.json(experiments: rows)
        else
          out.header('Experiments')
          out.spacer
          table_rows = rows.map do |r|
            [r[:id].to_s, r[:name].to_s, r[:status].to_s, r[:created_at].to_s, r[:summary].to_s[0, 60]]
          end
          out.table(%w[id name status created summary], table_rows)
        end
      ensure
        Connection.shutdown
      end

      desc 'promote', 'Tag a prompt version from a passing experiment for production'
      option :experiment, type: :string, required: true, aliases: '-e', desc: 'Experiment name'
      option :tag,        type: :string, required: true, aliases: '-t', desc: 'Tag to apply (e.g. production)'
      def promote
        setup_connection
        require_dataset!
        require_prompt!

        dataset_client = Legion::Extensions::Dataset::Client.new
        experiment     = dataset_client.get_experiment(name: options[:experiment])
        raise CLI::Error, "Experiment '#{options[:experiment]}' not found" if experiment.nil?
        raise CLI::Error, "Experiment '#{options[:experiment]}' has no prompt linked" if experiment[:prompt_name].nil?

        prompt_client = Legion::Extensions::Prompt::Client.new
        result = prompt_client.tag_prompt(
          name:    experiment[:prompt_name],
          tag:     options[:tag],
          version: experiment[:prompt_version]
        )

        out = formatter
        if options[:json]
          out.json(result)
        else
          out.success("Tagged prompt '#{experiment[:prompt_name]}' v#{experiment[:prompt_version]} as '#{options[:tag]}'")
        end
      ensure
        Connection.shutdown
      end

      desc 'compare', 'Compare two experiment runs side by side'
      option :run1, type: :string, required: true, desc: 'First experiment name'
      option :run2, type: :string, required: true, desc: 'Second experiment name'
      def compare
        setup_connection
        require_dataset!

        client = Legion::Extensions::Dataset::Client.new
        diff   = client.compare_experiments(exp1_name: options[:run1], exp2_name: options[:run2])
        raise CLI::Error, 'One or both experiments not found' if diff[:error]

        out = formatter
        if options[:json]
          out.json(diff)
        else
          out.header("Compare: #{diff[:exp1]} vs #{diff[:exp2]}")
          out.spacer
          table_rows = [
            ['Rows compared', diff[:rows_compared].to_s],
            ['Regressions',   diff[:regression_count].to_s],
            ['Improvements',  diff[:improvement_count].to_s]
          ]
          out.table(%w[metric value], table_rows)
        end
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

        def require_prompt!
          return if defined?(Legion::Extensions::Prompt::Client)

          raise CLI::Error, 'lex-prompt extension is not loaded. Install and enable it first.'
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
