# frozen_string_literal: true

require 'thor'

module Legion
  module CLI
    class Payroll < Thor
      def self.exit_on_failure? = true

      desc 'summary', 'Show workforce payroll summary'
      option :period, type: :string, default: 'daily', desc: 'Period: daily, weekly, monthly'
      option :json, type: :boolean, default: false, desc: 'Output as JSON'
      def summary
        require 'legion/extensions/metering/helpers/economics'
        economics = Object.new.extend(Legion::Extensions::Metering::Helpers::Economics)
        result = economics.payroll_summary(period: options[:period].to_sym)

        if options[:json]
          say ::JSON.dump(result)
        else
          say 'Payroll Summary', :green
          say '-' * 40
          say "  Period:          #{result[:period]}"
          say format('  Total Cost:      $%.4f', result[:total_cost])
          say format('  Avg Productivity: %.1f tasks', result[:avg_productivity])
          if result[:workers].any?
            say ''
            say '  Worker                  Tasks       Cost   Autonomy'
            say "  #{'-' * 52}"
            result[:workers].each do |w|
              cost_str = format('$%.4f', w[:cost])
              say format('  %-20<worker>s %8<tasks>d %10<cost>s %10<autonomy>s',
                         worker: w[:worker_id], tasks: w[:task_count],
                         cost: cost_str, autonomy: w[:autonomy])
            end
          else
            say '  No worker data found for this period.', :yellow
          end
        end
      rescue LoadError => e
        Legion::Logging.warn("PayrollCommand#summary lex-metering not available: #{e.message}") if defined?(Legion::Logging)
        say "Error: lex-metering not available (#{e.message})", :red
      end
      default_task :summary

      desc 'report WORKER_ID', 'Detailed worker cost report'
      option :period, type: :string, default: 'daily'
      option :json, type: :boolean, default: false
      def report(worker_id)
        require 'legion/extensions/metering/helpers/economics'
        economics = Object.new.extend(Legion::Extensions::Metering::Helpers::Economics)
        result = economics.worker_report(worker_id: worker_id, period: options[:period].to_sym)

        if options[:json]
          say ::JSON.dump(result)
        else
          say "Worker Report: #{worker_id}", :green
          say '-' * 40
          result.each { |k, v| say "  #{k}: #{v}" }
        end
      rescue LoadError => e
        Legion::Logging.warn("PayrollCommand#report lex-metering not available: #{e.message}") if defined?(Legion::Logging)
        say "Error: lex-metering not available (#{e.message})", :red
      end

      desc 'forecast', 'Project costs for upcoming period'
      option :days, type: :numeric, default: 30, desc: 'Number of days to project'
      option :json, type: :boolean, default: false
      def forecast
        require 'legion/extensions/metering/helpers/economics'
        economics = Object.new.extend(Legion::Extensions::Metering::Helpers::Economics)
        result = economics.budget_forecast(days: options[:days])

        if options[:json]
          say ::JSON.dump(result)
        else
          say 'Cost Forecast', :green
          say '-' * 40
          say format("  Projected Cost (#{result[:days]}d): $%.4f", result[:projected_cost])
          say format('  Daily Average:              $%.4f', result[:daily_average])
          say "  Trend:                      #{result[:trend]}"
        end
      rescue LoadError => e
        Legion::Logging.warn("PayrollCommand#forecast lex-metering not available: #{e.message}") if defined?(Legion::Logging)
        say "Error: lex-metering not available (#{e.message})", :red
      end

      desc 'budget', 'Show or set daily budget threshold'
      option :set, type: :numeric, desc: 'Set daily budget threshold'
      def budget
        if options[:set]
          say "Daily budget set to $#{options[:set]}", :green
          say 'Budget enforcement requires alert rules (see legion alerts)', :yellow
        else
          say 'Budget', :green
          say '-' * 40
          say '  No budget threshold configured. Use --set to configure.', :yellow
        end
      end
    end
  end
end
