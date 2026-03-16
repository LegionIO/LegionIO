# frozen_string_literal: true

require 'json'
require 'fileutils'
require 'net/http'

module Legion
  module CLI
    module ConfigScaffold
      SUBSYSTEMS = %w[transport data cache crypt logging llm].freeze

      ENV_DETECTIONS = {
        'AWS_BEARER_TOKEN_BEDROCK' => { subsystem: 'llm', provider: :bedrock, field: :bearer_token },
        'ANTHROPIC_API_KEY'        => { subsystem: 'llm', provider: :anthropic, field: :api_key },
        'OPENAI_API_KEY'           => { subsystem: 'llm', provider: :openai, field: :api_key },
        'GEMINI_API_KEY'           => { subsystem: 'llm', provider: :gemini, field: :api_key },
        'VAULT_TOKEN'              => { subsystem: 'crypt', field: :token },
        'RABBITMQ_USER'            => { subsystem: 'transport', field: :user },
        'RABBITMQ_PASSWORD'        => { subsystem: 'transport', field: :password }
      }.freeze

      module_function

      def run(formatter, options) # rubocop:disable Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity
        dir       = options[:dir] || "#{Dir.home}/.legionio/settings"
        only      = options[:only] ? options[:only].split(',').map(&:strip) : SUBSYSTEMS
        full_mode = options[:full]
        force     = options[:force]

        invalid = only - SUBSYSTEMS
        if invalid.any?
          formatter.error("Unknown subsystem(s): #{invalid.join(', ')}. Valid: #{SUBSYSTEMS.join(', ')}")
          return 1
        end

        FileUtils.mkdir_p(dir)

        detected = detect_environment
        created = []
        skipped = []

        only.each do |name|
          path = File.join(dir, "#{name}.json")

          if File.exist?(path) && !force
            skipped << path
            next
          end

          content = full_mode ? full_template(name) : minimal_template(name)
          apply_detections!(content, name, detected)
          File.write(path, "#{::JSON.pretty_generate(content)}\n")
          created << path
        end

        if options[:json]
          formatter.json(created: created, skipped: skipped, detected: detected.map { |d| d[:label] })
        else
          if created.any?
            formatter.success("Created #{created.size} config file(s) in #{dir}/")
            created.each { |f| puts "    #{f}" }
          end
          if skipped.any?
            formatter.warn("Skipped #{skipped.size} existing file(s) (use --force to overwrite)")
            skipped.each { |f| puts "    #{f}" }
          end
          if detected.any? && created.any?
            formatter.spacer
            puts '  Auto-detected:'
            detected.each { |d| puts "    #{d[:label]}" }
          end
          formatter.spacer
          formatter.success('Edit these files then run: legion config validate') if created.any?
        end

        0
      end

      def detect_environment
        detected = []

        ENV_DETECTIONS.each do |env_var, meta|
          next unless ENV[env_var] && !ENV[env_var].empty?

          label = meta[:provider] ? "#{meta[:provider]} enabled (#{env_var} found)" : "#{meta[:field]} set (#{env_var} found)"
          detected << { env_var: env_var, label: label, **meta }
        end

        if ollama_running?
          detected << { subsystem: 'llm', provider: :ollama, field: :enabled, env_var: nil,
                        label: 'ollama enabled (responding on localhost:11434)' }
        end

        detected
      end

      def ollama_running?
        uri = URI('http://localhost:11434/')
        http = Net::HTTP.new(uri.host, uri.port)
        http.open_timeout = 1
        http.read_timeout = 1
        response = http.get(uri.path)
        response.is_a?(Net::HTTPSuccess)
      rescue StandardError
        false
      end

      def apply_detections!(content, subsystem, detected)
        relevant = detected.select { |d| d[:subsystem] == subsystem }
        return if relevant.empty?

        case subsystem
        when 'llm'   then apply_llm_detections!(content[:llm], relevant)
        when 'crypt' then apply_crypt_detections!(content[:crypt], relevant)
        when 'transport' then apply_transport_detections!(content[:transport][:connection], relevant)
        end
      end

      def apply_llm_detections!(llm, detections)
        first_provider = nil
        detections.each do |det|
          provider = det[:provider]
          next unless provider && llm[:providers][provider]

          llm[:providers][provider][:enabled] = true
          llm[:providers][provider][det[:field]] = "env://#{det[:env_var]}" if det[:env_var]
          first_provider ||= provider
        end
        return unless first_provider

        llm[:enabled] = true
        llm[:default_provider] = first_provider.to_s
      end

      def apply_crypt_detections!(crypt, detections)
        vault_det = detections.find { |d| d[:field] == :token }
        return unless vault_det

        crypt[:vault][:enabled] = true
        crypt[:vault][:token] = "env://#{vault_det[:env_var]}"
      end

      def apply_transport_detections!(connection, detections)
        detections.each do |det|
          connection[det[:field]] = "env://#{det[:env_var]}"
        end
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
              block:       false,
              auto_delete: false,
              arguments:   { 'x-queue-type': 'quorum' }
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
