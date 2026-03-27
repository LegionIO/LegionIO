# frozen_string_literal: true

require 'thor'

module Legion
  module CLI
    class Doctor < Thor
      autoload :Result,           'legion/cli/doctor/result'
      autoload :RubyVersionCheck, 'legion/cli/doctor/ruby_version_check'
      autoload :BundleCheck,      'legion/cli/doctor/bundle_check'
      autoload :ConfigCheck,      'legion/cli/doctor/config_check'
      autoload :RabbitmqCheck,    'legion/cli/doctor/rabbitmq_check'
      autoload :DatabaseCheck,    'legion/cli/doctor/database_check'
      autoload :CacheCheck,       'legion/cli/doctor/cache_check'
      autoload :VaultCheck,       'legion/cli/doctor/vault_check'
      autoload :ExtensionsCheck,  'legion/cli/doctor/extensions_check'
      autoload :PidCheck,         'legion/cli/doctor/pid_check'
      autoload :PermissionsCheck, 'legion/cli/doctor/permissions_check'
      autoload :TlsCheck,         'legion/cli/doctor/tls_check'

      def self.exit_on_failure?
        true
      end

      class_option :json,     type: :boolean, default: false, desc: 'Output as JSON'
      class_option :no_color, type: :boolean, default: false, desc: 'Disable color output'

      CHECKS = %i[
        RubyVersionCheck
        BundleCheck
        ConfigCheck
        RabbitmqCheck
        DatabaseCheck
        CacheCheck
        VaultCheck
        ExtensionsCheck
        PidCheck
        PermissionsCheck
        TlsCheck
      ].freeze

      desc 'diagnose', 'Check environment health and suggest fixes'
      method_option :fix, type: :boolean, default: false, desc: 'Auto-fix issues where possible'
      def diagnose
        out = formatter
        begin
          Connection.ensure_settings
        rescue StandardError => e
          Legion::Logging.debug("Doctor#diagnose settings load failed: #{e.message}") if defined?(Legion::Logging)
        end
        results = run_all_checks

        if options[:json]
          output_json(out, results)
        else
          output_text(out, results)
        end

        auto_fix(results) if options[:fix]

        exit(1) if results.any?(&:fail?)
      ensure
        Connection.shutdown
      end

      default_task :diagnose

      no_commands do
        def formatter
          @formatter ||= Output::Formatter.new(
            json:  options[:json],
            color: !options[:no_color]
          )
        end
      end

      private

      def check_classes
        CHECKS.map { |name| Doctor.const_get(name) }
      end

      def run_all_checks
        check_classes.map do |check_class|
          check_class.new.run
        rescue StandardError => e
          Legion::Logging.error("DoctorCommand#run_all_checks unexpected error in #{check_class}: #{e.message}") if defined?(Legion::Logging)
          Doctor::Result.new(
            name:    check_class.new.name,
            status:  :fail,
            message: "Unexpected error: #{e.message}"
          )
        end
      end

      def output_text(out, results)
        out.header('Legion Environment Diagnosis')
        out.spacer

        results.each { |r| print_result(out, r) }

        out.spacer
        print_summary(out, results)
      end

      def print_result(out, result)
        label = result.name.ljust(24)
        case result.status
        when :pass
          puts "  #{out.colorize('pass', :green)} #{label} #{out.colorize(result.message.to_s, :muted)}"
        when :fail
          puts "  #{out.colorize('FAIL', :red)} #{label} #{out.colorize(result.message.to_s, :critical)}"
          puts "    #{out.colorize('->', :yellow)} #{result.prescription}" if result.prescription
        when :warn
          puts "  #{out.colorize('WARN', :yellow)} #{label} #{out.colorize(result.message.to_s, :caution)}"
          puts "    #{out.colorize('->', :yellow)} #{result.prescription}" if result.prescription
        when :skip
          puts "  #{out.colorize('skip', :muted)} #{label} #{out.colorize(result.message.to_s, :disabled)}"
        end
      end

      def print_summary(out, results)
        passed       = results.count(&:pass?)
        failed       = results.count(&:fail?)
        warned       = results.count(&:warn?)
        skipped      = results.count(&:skip?)
        auto_fixable = results.count { |r| (r.fail? || r.warn?) && r.auto_fixable }

        msg = build_summary_message(passed, failed, warned, skipped, auto_fixable)

        if failed.positive?
          out.error(msg)
        elsif warned.positive?
          out.warn(msg)
        else
          out.success(msg)
        end
      end

      def build_summary_message(passed, failed, warned, skipped, auto_fixable)
        msg = "#{passed} passed"
        msg += ", #{failed} failed" if failed.positive?
        msg += ", #{warned} warnings" if warned.positive?
        msg += ", #{skipped} skipped" if skipped.positive?
        msg += " (#{auto_fixable} auto-fixable, run with --fix)" if auto_fixable.positive? && !options[:fix]
        msg
      end

      def output_json(out, results)
        passed       = results.count(&:pass?)
        failed       = results.count(&:fail?)
        warned       = results.count(&:warn?)
        skipped      = results.count(&:skip?)
        auto_fixable = results.count { |r| (r.fail? || r.warn?) && r.auto_fixable }

        out.json({
                   results: results.map(&:to_h),
                   summary: {
                     passed:       passed,
                     failed:       failed,
                     warnings:     warned,
                     skipped:      skipped,
                     auto_fixable: auto_fixable
                   }
                 })
      end

      def auto_fix(results)
        fixable = results.select { |r| (r.fail? || r.warn?) && r.auto_fixable }
        return if fixable.empty?

        out = formatter
        out.spacer
        out.header('Auto-fixing issues...')

        check_classes.each do |check_class|
          instance = check_class.new
          result   = results.find { |r| r.name == instance.name }
          next unless result && (result.fail? || result.warn?) && result.auto_fixable
          next unless instance.respond_to?(:fix)

          out.success("Fixing: #{result.name}")
          instance.fix
        rescue StandardError => e
          out.error("Fix failed for #{check_class}: #{e.message}")
        end
      end
    end
  end
end
