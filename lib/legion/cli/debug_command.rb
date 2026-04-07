# frozen_string_literal: true

require 'fileutils'
require 'net/http'
require 'json'
require 'socket'
require 'thor'

module Legion
  module CLI
    class Debug < Thor
      namespace 'debug'

      def self.exit_on_failure?
        true
      end

      class_option :json, type: :boolean, default: false, desc: 'Output as JSON'
      class_option :no_color, type: :boolean, default: false, desc: 'Disable color output'
      class_option :port, type: :numeric, default: 4567, desc: 'API port'
      class_option :host, type: :string, default: '127.0.0.1', desc: 'API host'
      class_option :config_dir, type: :string, desc: 'Config directory path'

      desc 'dump', 'Full diagnostic dump (markdown, suitable for piping to LLM)'
      default_task :dump
      def dump
        sections = collect_all_sections

        output = if options[:json]
                   ::JSON.pretty_generate(sections)
                 else
                   build_markdown(sections)
                 end

        puts output

        path = write_dump_file(output)
        warn "Saved to #{path}" if path
      end

      DEBUG_DIR = File.expand_path('~/.legionio/debug')

      no_commands do # rubocop:disable Metrics/BlockLength
        private

        def collect_all_sections
          sections = {}
          sections[:versions]     = section_versions
          sections[:doctor]       = section_doctor
          sections[:config]       = section_config
          sections[:gems]         = section_gems
          sections[:extensions]   = section_extensions
          sections[:rbac]         = section_rbac
          sections[:llm]          = section_llm
          sections[:gaia]         = section_gaia
          sections[:transport]    = section_transport
          sections[:events]       = section_events
          sections[:apollo]       = section_apollo
          sections[:remote_redis] = section_remote_redis
          sections[:local_redis]  = section_local_redis
          sections[:postgresql]   = section_postgresql
          sections[:rabbitmq]     = section_rabbitmq
          sections[:api_health]   = section_api_health
          sections
        end

        def write_dump_file(output)
          FileUtils.mkdir_p(DEBUG_DIR)
          ext = options[:json] ? 'json' : 'md'
          filename = "#{Time.now.utc.strftime('%Y-%m-%d_%H%M%S')}.#{ext}"
          path = File.join(DEBUG_DIR, filename)
          File.write(path, output)
          path
        rescue StandardError => e
          warn "Warning: could not write debug file: #{e.message}"
          nil
        end

        def api_host
          options[:host] || '127.0.0.1'
        end

        def api_port_number
          options[:port] || 4567
        end

        def api_get(path)
          uri  = URI("http://#{api_host}:#{api_port_number}#{path}")
          http = Net::HTTP.new(uri.host, uri.port)
          http.open_timeout = 3
          http.read_timeout = 5
          response = http.get(uri.request_uri)
          ::JSON.parse(response.body, symbolize_names: true)
        rescue StandardError => e
          { error: e.message }
        end

        def load_settings
          Connection.config_dir = options[:config_dir] if options[:config_dir]
          Connection.log_level = 'error'
          Connection.ensure_settings(resolve_secrets: false)
        rescue StandardError
          nil
        end

        def section_versions
          components = {}
          components[:legionio] = defined?(Legion::VERSION) ? Legion::VERSION : 'unknown'
          components[:ruby] = RUBY_VERSION
          components[:platform] = RUBY_PLATFORM
          components[:yjit] = defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?

          %w[legion-transport legion-cache legion-crypt legion-data
             legion-json legion-logging legion-settings
             legion-llm legion-gaia legion-mcp legion-rbac legion-tty].each do |gem_name|
            spec = Gem::Specification.find_by_name(gem_name)
            components[gem_name.to_sym] = spec.version.to_s
          rescue Gem::MissingSpecError
            components[gem_name.to_sym] = 'not installed'
          end

          components
        rescue StandardError => e
          { error: e.message }
        end

        def section_doctor
          load_settings
          require 'legion/cli/doctor_command'
          Doctor::CHECKS.map do |name|
            check = Doctor.const_get(name).new
            result = check.run
            { name: result.name, status: result.status, message: result.message }
          rescue StandardError => e
            { name: name.to_s, status: :error, message: e.message }
          end
        rescue StandardError => e
          { error: e.message }
        end

        def section_config
          load_settings
          settings_hash = Legion::Settings.loader.to_hash
          redact_deep(settings_hash)
        rescue StandardError => e
          { error: e.message }
        end

        def section_gems
          gems = {}
          duplicates = []
          Gem::Specification.each do |spec|
            next unless spec.name.start_with?('legion-', 'lex-', 'legionio')

            gems[spec.name] ||= []
            gems[spec.name] << spec.version.to_s
          end

          gems.each do |name, versions|
            duplicates << { name: name, versions: versions } if versions.size > 1
          end

          { total: gems.size, duplicates: duplicates,
            versions: gems.transform_values { |v| v.max_by { |ver| Gem::Version.new(ver) } } }
        rescue StandardError => e
          { error: e.message }
        end

        def section_extensions
          data = api_get('/api/extensions')
          return data if data[:error]

          exts = data[:data] || data[:extensions] || data
          { count: exts.is_a?(Array) ? exts.size : nil, extensions: exts }
        end

        def section_rbac
          api_get('/api/rbac/roles')
        end

        def section_llm
          load_settings
          require 'legion/llm'
          Legion::Settings.merge_settings(:llm, Legion::LLM::Settings.default)
          settings = Legion::LLM.settings
          providers = settings[:providers] || {}
          {
            started:          defined?(Legion::LLM) && Legion::LLM.started?,
            default_provider: settings[:default_provider],
            default_model:    settings[:default_model],
            providers:        providers.map { |name, cfg| { name: name, enabled: cfg[:enabled] } }
          }
        rescue StandardError => e
          { error: e.message }
        end

        def section_gaia
          status = api_get('/api/gaia/status')
          channels = api_get('/api/gaia/channels')
          buffer = api_get('/api/gaia/buffer')
          sessions = api_get('/api/gaia/sessions')
          { status: status[:data] || status, channels: channels[:data] || channels,
            buffer: buffer[:data] || buffer, sessions: sessions[:data] || sessions }
        end

        def section_transport
          api_get('/api/transport/status')
        end

        def section_events
          api_get('/api/events/recent?count=20')
        end

        def section_apollo
          api_get('/api/apollo/stats')
        end

        def section_remote_redis
          load_settings
          cache_cfg = Legion::Settings[:cache]
          return { error: 'no cache config' } unless cache_cfg.is_a?(Hash) && cache_cfg[:servers]

          server = cache_cfg[:servers].first
          host, port = server.to_s.split(':')
          password = cache_cfg[:password]

          redis_info(host, port.to_i, password)
        rescue StandardError => e
          { error: e.message }
        end

        def section_local_redis
          load_settings
          local_cfg = Legion::Settings[:cache_local]
          return { error: 'no cache_local config' } unless local_cfg.is_a?(Hash) && local_cfg[:servers]

          server = local_cfg[:servers].first
          host, port = server.to_s.split(':')
          password = local_cfg[:password]

          redis_info(host, port.to_i, password)
        rescue StandardError => e
          { error: e.message }
        end

        def section_postgresql
          load_settings
          data_cfg = Legion::Settings[:data]
          return { error: 'no data config' } unless data_cfg.is_a?(Hash) && data_cfg[:creds]

          creds = data_cfg[:creds]
          require 'pg'
          conn = PG.connect(
            host: creds[:host], port: creds[:port] || 5432,
            dbname: creds[:database], user: creds[:user], password: creds[:password],
            connect_timeout: 5
          )

          db_size = conn.exec_params(
            'SELECT pg_size_pretty(pg_database_size(current_database())) AS size'
          ).first['size']
          migration = conn.exec_params(
            'SELECT version FROM schema_info ORDER BY version DESC LIMIT 1'
          ).first
          migration_version = migration ? migration['version'] : 'unknown'

          tables = conn.exec_params(<<~SQL).to_a
            SELECT tablename AS name,
                   pg_size_pretty(pg_total_relation_size(quote_ident(tablename))) AS size,
                   (SELECT n_live_tup FROM pg_stat_user_tables WHERE relname = tablename) AS rows
            FROM pg_tables WHERE schemaname = 'public'
            ORDER BY pg_total_relation_size(quote_ident(tablename)) DESC LIMIT 20
          SQL

          conn.close
          { db_size: db_size, migration_version: migration_version, tables: tables }
        rescue LoadError
          { error: 'pg gem not available' }
        rescue StandardError => e
          { error: e.message }
        end

        def section_rabbitmq
          load_settings
          transport_cfg = Legion::Settings[:transport] || {}
          host = transport_cfg[:host] || 'localhost'
          mgmt_port = transport_cfg[:management_port] || 15_672
          user = transport_cfg[:user] || 'guest'
          pass = transport_cfg[:password] || 'guest'
          vhost = transport_cfg[:vhost] || '/'

          uri = URI("http://#{host}:#{mgmt_port}/api/overview")
          http = Net::HTTP.new(uri.host, uri.port)
          http.open_timeout = 3
          http.read_timeout = 5
          req = Net::HTTP::Get.new(uri)
          req.basic_auth(user, pass)
          resp = http.request(req)
          overview = ::JSON.parse(resp.body, symbolize_names: true)

          encoded_vhost = URI.encode_www_form_component(vhost)
          queues_uri = URI("http://#{host}:#{mgmt_port}/api/queues/#{encoded_vhost}")
          req2 = Net::HTTP::Get.new("#{queues_uri.path}?page=1&page_size=15&sort=messages&sort_reverse=true")
          req2.basic_auth(user, pass)
          resp2 = http.request(req2)
          queues = ::JSON.parse(resp2.body, symbolize_names: true)

          queue_list = queues.is_a?(Array) ? queues : (queues[:items] || [])

          {
            cluster_name:     overview[:cluster_name],
            rabbitmq_version: overview[:rabbitmq_version],
            erlang_version:   overview[:erlang_version],
            message_stats:    overview[:message_stats],
            queue_totals:     overview[:queue_totals],
            object_totals:    overview[:object_totals],
            top_queues:       queue_list.first(15).map do |q|
              { name: q[:name], messages: q[:messages], consumers: q[:consumers] }
            end
          }
        rescue StandardError => e
          { error: e.message }
        end

        def section_api_health
          ready = api_get('/api/ready')
          health = api_get('/api/health')
          capacity = api_get('/api/capacity')
          cost = api_get('/api/cost/summary')
          { ready: ready, health: health, capacity: capacity, cost: cost }
        end

        def redis_info(host, port, password)
          socket = TCPSocket.new(host, port)
          socket.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)

          if password && !password.empty?
            socket.write("AUTH #{password}\r\n")
            auth_resp = socket.gets
            return { error: "AUTH failed: #{auth_resp&.strip}" } unless auth_resp&.start_with?('+OK')
          end

          info = redis_command(socket, 'INFO memory')
          dbsize_raw = redis_command(socket, 'DBSIZE')

          socket.close

          memory_lines = info.lines.select { |l| l.include?(':') }.to_h { |l| l.strip.split(':', 2) }
          dbsize = dbsize_raw.to_s.scan(/\d+/).first

          {
            used_memory_human:       memory_lines['used_memory_human'],
            used_memory_peak_human:  memory_lines['used_memory_peak_human'],
            maxmemory_human:         memory_lines['maxmemory_human'],
            mem_fragmentation_ratio: memory_lines['mem_fragmentation_ratio'],
            dbsize:                  dbsize
          }
        rescue StandardError => e
          { error: e.message }
        end

        def redis_command(socket, cmd)
          parts = cmd.split
          socket.write("*#{parts.size}\r\n")
          parts.each { |p| socket.write("$#{p.bytesize}\r\n#{p}\r\n") }

          first = socket.gets
          return '' unless first

          case first[0]
          when '+', ':' then first[1..].strip
          when '-' then "ERROR: #{first[1..].strip}"
          when '$'
            len = first[1..].to_i
            return '' if len.negative?

            data = socket.read(len + 2)
            data&.strip || ''
          when '*'
            count = first[1..].to_i
            return '' if count.negative?

            count.times.map { redis_read_bulk(socket) }.join("\n")
          else
            first.strip
          end
        end

        def redis_read_bulk(socket)
          header = socket.gets
          return '' unless header&.start_with?('$')

          len = header[1..].to_i
          return '' if len.negative?

          data = socket.read(len + 2)
          data&.strip || ''
        end

        def redact_deep(obj)
          case obj
          when Hash
            obj.each_with_object({}) do |(k, v), h|
              h[k] = if k.to_s.match?(/password|secret|token|key|credential/i) && v.is_a?(String)
                       '[REDACTED]'
                     else
                       redact_deep(v)
                     end
            end
          when Array
            obj.map { |v| redact_deep(v) }
          else
            obj
          end
        end

        def build_markdown(sections)
          lines = []
          lines << '# LegionIO Diagnostic Dump'
          lines << ''
          lines << "Generated: #{Time.now.utc.iso8601}"
          lines << ''

          { 'Versions'                 => :versions,
            'Doctor Checks'            => :doctor,
            'Configuration (redacted)' => :config,
            'Installed Gems'           => :gems,
            'Loaded Extensions'        => :extensions,
            'RBAC Roles'               => :rbac,
            'LLM Status'               => :llm,
            'GAIA Status'              => :gaia,
            'Transport Status'         => :transport,
            'Recent Events (last 20)'  => :events,
            'Apollo Stats'             => :apollo,
            'Remote Redis'             => :remote_redis,
            'Local Redis'              => :local_redis,
            'PostgreSQL'               => :postgresql,
            'RabbitMQ'                 => :rabbitmq,
            'API Health'               => :api_health }.each do |title, key|
            lines << "## #{title}"
            lines << ''
            lines << '```json'
            lines << ::JSON.pretty_generate(sections[key])
            lines << '```'
            lines << ''
          end

          lines.join("\n")
        end
      end
    end
  end
end
