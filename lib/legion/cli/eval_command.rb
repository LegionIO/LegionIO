# frozen_string_literal: true

module Legion
  module CLI
    class Eval < Thor
      def self.exit_on_failure? = true

      class_option :json, type: :boolean, default: false, desc: 'Output as JSON'
      class_option :no_color, type: :boolean, default: false, desc: 'Disable color output'
      class_option :verbose, type: :boolean, default: false, aliases: ['-V'], desc: 'Verbose logging'
      class_option :config_dir, type: :string, desc: 'Config directory path'

      desc 'list', 'List available evaluators'
      def list
        with_eval_client do |client|
          result = client.list_evaluators
          if options[:json]
            formatter.json(result)
          else
            render_evaluator_list(result)
          end
        end
      end
      default_task :list

      desc 'check', 'Quick single-pair evaluation'
      option :evaluator, type: :string, required: true, aliases: ['-e'], desc: 'Evaluator name'
      option :input, type: :string, required: true, aliases: ['-i'], desc: 'Input text'
      option :output, type: :string, required: true, aliases: ['-o'], desc: 'Output text'
      option :expected, type: :string, aliases: ['-x'], desc: 'Expected output (if required)'
      def check
        with_eval_client do |client|
          evaluator = client.build_evaluator(options[:evaluator].to_sym)
          result = evaluator.evaluate(input: options[:input], output: options[:output],
                                      expected: options[:expected])
          render_check_result(result)
          raise SystemExit, 1 unless result[:passed]
        end
      end

      desc 'execute', 'Run evaluators against a dataset with threshold gating'
      map 'run' => :execute
      option :dataset, type: :string, required: true, aliases: ['-d'], desc: 'Dataset name'
      option :evaluators, type: :string, required: true, aliases: ['-e'], desc: 'Comma-separated evaluators'
      option :threshold, type: :numeric, default: 0.8, aliases: ['-t'], desc: 'Pass threshold'
      option :exit_code, type: :boolean, default: false, desc: 'Exit with code 1 on failure'
      option :format, type: :string, default: 'text', desc: 'Output format (text or json)'
      def execute
        with_data do
          dataset = load_dataset
          results, duration_ms = run_evaluations(dataset)
          output = build_run_output(dataset, results, duration_ms)
          render_run_output(output)
          raise SystemExit, 1 if options[:exit_code] && !output[:overall_passed]
        end
      end

      no_commands do # rubocop:disable Metrics/BlockLength
        def formatter
          @formatter ||= Output::Formatter.new(json: options[:json], color: !options[:no_color])
        end

        def with_eval_client
          require 'legion/extensions/eval'
          yield Legion::Extensions::Eval::Client.new
        rescue LoadError => e
          formatter.error("lex-eval not available: #{e.message}")
          raise SystemExit, 2
        end

        def with_data
          Connection.ensure_data
          yield
        rescue CLI::Error => e
          formatter.error(e.message)
          raise SystemExit, 2
        ensure
          Connection.shutdown
        end

        def load_dataset
          dataset_client = build_dataset_client
          dataset = dataset_client.get_dataset(name: options[:dataset])
          return dataset unless dataset[:error]

          formatter.error("Dataset '#{options[:dataset]}' not found")
          raise SystemExit, 2
        end

        def run_evaluations(dataset)
          eval_client = build_eval_client
          names = options[:evaluators].split(',').map(&:strip)
          start_time = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
          results = {}

          names.each do |name|
            eval_result = eval_client.run_evaluation(
              evaluator_name: name, evaluator_config: {},
              inputs: dataset[:rows].map { |r| { input: r[:input], output: r[:expected_output] || '', expected: nil } }
            )
            avg = eval_result[:summary][:avg_score]
            results[name] = { avg_score: avg, passed: avg >= options[:threshold], threshold: options[:threshold] }
          end

          duration = ((::Process.clock_gettime(::Process::CLOCK_MONOTONIC) - start_time) * 1000).round
          [results, duration]
        end

        def build_run_output(dataset, results, duration_ms)
          { dataset: options[:dataset], evaluators: results,
            overall_passed: results.values.all? { |r| r[:passed] },
            rows_evaluated: dataset[:rows]&.size || 0, duration_ms: duration_ms }
        end

        def render_evaluator_list(result)
          formatter.heading('Available Evaluators')
          result[:evaluators].each do |tmpl|
            formatter.detail({ name: tmpl[:name], category: tmpl[:category],
                               type: tmpl[:type], threshold: tmpl[:threshold] })
            formatter.spacer
          end
          formatter.info("#{result[:evaluators].size} evaluators available")
        end

        def render_check_result(result)
          if options[:json]
            formatter.json(result)
          else
            status = result[:passed] ? 'PASS' : 'FAIL'
            formatter.heading("Evaluation: #{options[:evaluator]} — #{status}")
            formatter.detail({ score: result[:score], passed: result[:passed],
                               explanation: result[:explanation] })
          end
        end

        def render_run_output(output)
          if options[:format] == 'json' || options[:json]
            formatter.json(output)
          else
            formatter.heading("Eval Run: #{output[:dataset]}")
            output[:evaluators].each do |name, r|
              formatter.detail({ evaluator: name, avg_score: r[:avg_score],
                                 threshold: r[:threshold], status: r[:passed] ? 'PASS' : 'FAIL' })
            end
            formatter.spacer
            formatter.info("Overall: #{output[:overall_passed] ? 'ALL PASSED' : 'FAILED'} (#{output[:duration_ms]}ms)")
          end
        end

        def build_eval_client
          require 'legion/extensions/eval'
          Legion::Extensions::Eval::Client.new
        end

        def build_dataset_client
          require 'legion/extensions/dataset'
          db = Legion::Data::Connection.default if defined?(Legion::Data::Connection)
          Legion::Extensions::Dataset::Client.new(db: db)
        end
      end
    end
  end
end
