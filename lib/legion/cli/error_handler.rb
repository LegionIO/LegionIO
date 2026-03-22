# frozen_string_literal: true

module Legion
  module CLI
    module ErrorHandler
      PATTERNS = [
        {
          match:       /connection refused.*5672|ECONNREFUSED.*5672|bunny.*not connected/i,
          code:        :transport_unavailable,
          message:     'Cannot connect to RabbitMQ',
          suggestions: [
            "Run 'legion doctor' to diagnose connectivity",
            "Check transport settings: 'legion config show -s transport'",
            'Verify RabbitMQ is running: brew services list | grep rabbitmq'
          ]
        },
        {
          match:       /table.*not.*found|no such table|PG::UndefinedTable|Sequel::DatabaseError.*exist/i,
          code:        :database_missing,
          message:     'Database table not found',
          suggestions: [
            "Run 'legion start' to apply pending migrations",
            "Check database config: 'legion config show -s data'",
            "Verify database is running: 'legion doctor'"
          ]
        },
        {
          match:       /extension.*not.*found|no such extension|uninitialized constant.*Extensions/i,
          code:        :extension_missing,
          message:     'Extension not found',
          suggestions: [
            "Search available extensions: 'legion marketplace search <name>'",
            'Install with: gem install lex-<name>',
            "List installed: 'legion lex list'"
          ]
        },
        {
          match:       /permission denied|EACCES/i,
          code:        :permission_denied,
          message:     'Permission denied',
          suggestions: [
            'Try running with sudo for system directories',
            'Set custom config dir: LEGIONIO_CONFIG_DIR=~/.legionio',
            'Check file permissions: ls -la ~/.legionio/'
          ]
        },
        {
          match:       /legion-data.*not.*connected|data.*not.*available/i,
          code:        :data_unavailable,
          message:     'Database not connected',
          suggestions: [
            "Check database config: 'legion config show -s data'",
            "Run diagnostics: 'legion doctor'",
            'Some commands work without a database — try adding --no-data flag'
          ]
        },
        {
          match:       /vault.*not.*connected|vault.*sealed|VAULT_ADDR/i,
          code:        :vault_unavailable,
          message:     'Vault not connected',
          suggestions: [
            "Check Vault config: 'legion config show -s crypt'",
            'Verify VAULT_ADDR and VAULT_TOKEN environment variables',
            "Run diagnostics: 'legion doctor'"
          ]
        }
      ].freeze

      module_function

      def wrap(error)
        pattern = PATTERNS.find { |p| error.message.match?(p[:match]) }
        return error unless pattern

        Error.actionable(
          code:        pattern[:code],
          message:     "#{pattern[:message]}: #{error.message}",
          suggestions: pattern[:suggestions]
        )
      end

      def format_error(error, formatter)
        formatter.error(error.message)
        return unless error.is_a?(Error) && error.actionable?

        error.suggestions.each do |suggestion|
          puts "  #{formatter.colorize('>', :label)} #{suggestion}"
        end
      end
    end
  end
end
