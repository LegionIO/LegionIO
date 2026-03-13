# frozen_string_literal: true

require 'json'
require 'fileutils'

module Legion
  module CLI
    module ConfigScaffold
      SUBSYSTEMS = %w[transport data cache crypt logging llm].freeze

      module_function

      def run(formatter, options)
        dir       = options[:dir] || './settings'
        only      = options[:only] ? options[:only].split(',').map(&:strip) : SUBSYSTEMS
        full_mode = options[:full]
        force     = options[:force]

        invalid = only - SUBSYSTEMS
        if invalid.any?
          formatter.error("Unknown subsystem(s): #{invalid.join(', ')}. Valid: #{SUBSYSTEMS.join(', ')}")
          return 1
        end

        FileUtils.mkdir_p(dir)

        created = []
        skipped = []

        only.each do |name|
          path = File.join(dir, "#{name}.json")

          if File.exist?(path) && !force
            skipped << path
            next
          end

          content = full_mode ? full_template(name) : minimal_template(name)
          File.write(path, "#{::JSON.pretty_generate(content)}\n")
          created << path
        end

        if options[:json]
          formatter.json(created: created, skipped: skipped)
        else
          if created.any?
            formatter.success("Created #{created.size} config file(s) in #{dir}/")
            created.each { |f| puts "    #{f}" }
          end
          if skipped.any?
            formatter.warn("Skipped #{skipped.size} existing file(s) (use --force to overwrite)")
            skipped.each { |f| puts "    #{f}" }
          end
          formatter.spacer
          formatter.success('Edit these files then run: legion config validate') if created.any?
        end

        0
      end

      def minimal_template(name) # rubocop:disable Metrics/MethodLength
        case name # rubocop:disable Style/HashLikeCase
        when 'transport'
          { transport: {
            connection: {
              host:     '127.0.0.1',
              port:     5672,
              user:     'guest',
              password: 'guest',
              vhost:    '/'
            }
          } }
        when 'data'
          { data: {
            adapter: 'sqlite',
            creds:   { database: 'legionio.db' }
          } }
        when 'cache'
          { cache: {
            driver:  'dalli',
            servers: ['127.0.0.1:11211'],
            enabled: true
          } }
        when 'crypt'
          { crypt: {
            vault: {
              enabled: false,
              address: 'localhost',
              port:    8200,
              token:   nil
            },
            jwt:   {
              enabled:           true,
              default_algorithm: 'HS256',
              default_ttl:       3600
            }
          } }
        when 'logging'
          { logging: {
            level:    'info',
            location: 'stdout',
            trace:    true
          } }
        when 'llm'
          { llm: {
            enabled:          false,
            default_provider: nil,
            default_model:    nil,
            providers:        {
              anthropic: { enabled: false, api_key: nil },
              openai:    { enabled: false, api_key: nil },
              gemini:    { enabled: false, api_key: nil },
              bedrock:   { enabled: false, region: 'us-east-2' },
              ollama:    { enabled: false, base_url: 'http://localhost:11434' }
            }
          } }
        end
      end

      def full_template(name) # rubocop:disable Metrics/MethodLength
        case name # rubocop:disable Style/HashLikeCase
        when 'transport'
          { transport: {
            type:         'rabbitmq',
            logger_level: 'info',
            prefetch:     0,
            messages:     {
              encrypt:    false,
              ttl:        nil,
              priority:   0,
              persistent: false
            },
            exchanges:    {
              type:        'topic',
              arguments:   {},
              auto_delete: false,
              durable:     true,
              internal:    false
            },
            queues:       {
              manual_ack:  true,
              durable:     true,
              exclusive:   false,
              block:       false,
              auto_delete: false,
              arguments:   { 'x-max-priority': 255, 'x-overflow': 'reject-publish' }
            },
            connection:   {
              host:                      '127.0.0.1',
              port:                      5672,
              user:                      'guest',
              password:                  'guest',
              vhost:                     '/',
              read_timeout:              1,
              heartbeat:                 30,
              automatically_recover:     true,
              continuation_timeout:      4000,
              network_recovery_interval: 1,
              connection_timeout:        1,
              frame_max:                 65_536,
              recovery_attempts:         100,
              logger_level:              'info'
            },
            channel:      {
              default_worker_pool_size: 1,
              session_worker_pool_size: 8
            }
          } }
        when 'data'
          { data: {
            adapter:          'sqlite',
            connect_on_start: true,
            cache:            {
              auto_enable: false,
              ttl:         60
            },
            connection:       {
              log:                 false,
              log_connection_info: false,
              log_warn_duration:   1,
              sql_log_level:       'debug',
              max_connections:     10,
              preconnect:          false
            },
            creds:            {
              database: 'legionio.db'
            },
            migrations:       {
              continue_on_fail: false,
              auto_migrate:     true
            },
            models:           {
              continue_on_load_fail: false,
              autoload:              true
            }
          } }
        when 'cache'
          { cache: {
            driver:     'dalli',
            servers:    ['127.0.0.1:11211'],
            enabled:    true,
            namespace:  'legion',
            compress:   false,
            failover:   true,
            threadsafe: true,
            expires_in: 0,
            cache_nils: false,
            pool_size:  10,
            timeout:    5
          } }
        when 'crypt'
          { crypt: {
            cluster_secret:         nil,
            cluster_secret_timeout: 5,
            dynamic_keys:           true,
            save_private_key:       true,
            read_private_key:       true,
            jwt:                    {
              enabled:           true,
              default_algorithm: 'HS256',
              default_ttl:       3600,
              issuer:            'legion',
              verify_expiration: true,
              verify_issuer:     true
            },
            vault:                  {
              enabled:             false,
              protocol:            'http',
              address:             'localhost',
              port:                8200,
              token:               nil,
              renewer_time:        5,
              renewer:             true,
              push_cluster_secret: true,
              read_cluster_secret: true,
              kv_path:             'legion'
            }
          } }
        when 'logging'
          { logging: {
            level:             'info',
            location:          'stdout',
            trace:             true,
            backtrace_logging: true
          } }
        when 'llm'
          { llm: {
            enabled:          false,
            default_provider: nil,
            default_model:    nil,
            providers:        {
              bedrock:   { enabled: false, api_key: nil, secret_key: nil, session_token: nil,
                           region: 'us-east-2', vault_path: nil },
              anthropic: { enabled: false, api_key: nil, vault_path: nil },
              openai:    { enabled: false, api_key: nil, vault_path: nil },
              gemini:    { enabled: false, api_key: nil, vault_path: nil },
              ollama:    { enabled: false, base_url: 'http://localhost:11434' }
            }
          } }
        end
      end
    end
  end
end
