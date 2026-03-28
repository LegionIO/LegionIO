# frozen_string_literal: true

require 'json'
require 'net/http'
require 'erb'

module Legion
  module CLI
    module Admin
      class PurgeTopology < Thor
        namespace 'admin:purge_topology'

        def self.exit_on_failure?
          true
        end

        class_option :json,      type: :boolean, default: false,       desc: 'Output as JSON'
        class_option :no_color,  type: :boolean, default: false,       desc: 'Disable color output'
        class_option :host,      type: :string,  default: 'localhost', desc: 'RabbitMQ management host'
        class_option :port,      type: :numeric, default: 15_672,      desc: 'RabbitMQ management port'
        class_option :user,      type: :string,  default: 'guest',     desc: 'RabbitMQ management username'
        class_option :password,  type: :string,  default: 'guest',     desc: 'RabbitMQ management password'
        class_option :vhost,     type: :string,  default: '/',         desc: 'RabbitMQ vhost'
        class_option :execute,   type: :boolean, default: false,       desc: 'Actually delete (default: dry-run)'

        desc 'purge', 'Enumerate and optionally delete legacy v2.0 topology (legion.{lex} exchanges/queues)'
        def purge
          out = formatter
          out.header('Legion AMQP Topology Migration: v2.0 → v3.0')
          out.spacer

          legacy = find_legacy_topology
          if legacy[:exchanges].empty? && legacy[:queues].empty?
            out.success('No legacy topology found. Already on v3.0 or never had v2.0 topology.')
            return
          end

          if options[:json]
            out.json({ legacy: legacy, deleted: options[:execute] })
            perform_deletion(legacy) if options[:execute]
            return
          end

          report_legacy(out, legacy)

          if options[:execute]
            perform_deletion(legacy)
            out.success("Deleted #{legacy[:exchanges].size} exchange(s) and #{legacy[:queues].size} queue(s)")
          else
            out.warn('Dry-run mode — pass --execute to delete legacy topology')
          end
        rescue Legion::CLI::Error => e
          formatter.error(e.message)
          exit(1)
        end

        no_commands do # rubocop:disable Metrics/BlockLength
          def formatter
            @formatter ||= Output::Formatter.new(
              json:  options[:json],
              color: !options[:no_color]
            )
          end

          private

          def vhost_encoded
            ERB::Util.url_encode(options[:vhost])
          end

          def management_api(path)
            uri = URI("http://#{options[:host]}:#{options[:port]}/api#{path}")
            req = Net::HTTP::Get.new(uri)
            req.basic_auth(options[:user], options[:password])
            response = Net::HTTP.start(uri.host, uri.port, open_timeout: 5, read_timeout: 10) do |http|
              http.request(req)
            end
            raise Legion::CLI::Error, "Management API #{response.code}: #{response.body}" unless response.is_a?(Net::HTTPSuccess)

            ::JSON.parse(response.body, symbolize_names: true)
          rescue Errno::ECONNREFUSED
            raise Legion::CLI::Error, "Cannot connect to RabbitMQ management API at #{options[:host]}:#{options[:port]}"
          rescue Net::OpenTimeout, Net::ReadTimeout
            raise Legion::CLI::Error, 'Timed out connecting to RabbitMQ management API'
          end

          def management_delete(path)
            uri = URI("http://#{options[:host]}:#{options[:port]}/api#{path}")
            req = Net::HTTP::Delete.new(uri)
            req.basic_auth(options[:user], options[:password])
            Net::HTTP.start(uri.host, uri.port, open_timeout: 5, read_timeout: 10) { |http| http.request(req) }
          rescue Errno::ECONNREFUSED
            raise Legion::CLI::Error, "Cannot connect to RabbitMQ management API at #{options[:host]}:#{options[:port]}"
          end

          # Find exchanges and queues matching legacy v2.0 pattern: legion.{lex_name}.*
          # but NOT matching v3.0 pattern (lex.{lex_name}.*) or infrastructure (task, node, etc.)
          def find_legacy_topology
            all_exchanges = management_api("/exchanges/#{vhost_encoded}")
            all_queues    = management_api("/queues/#{vhost_encoded}")

            legacy_exchanges = all_exchanges
                               .map { |e| e[:name].to_s }
                               .select do |name|
              name.match?(/\Alegion\.[a-z]/) && !name.start_with?('legion.task', 'legion.node', 'legion.crypt', 'legion.extensions',
                                                                  'legion.logging')
            end

            legacy_queues = all_queues
                            .map { |q| q[:name].to_s }
                            .select { |name| name.match?(/\Alegion\.[a-z]/) && !name.match?(/\Alegion\.(task|node|crypt|extensions|logging)/) }

            { exchanges: legacy_exchanges, queues: legacy_queues }
          end

          def report_legacy(out, legacy)
            unless legacy[:exchanges].empty?
              out.detail_header("Legacy Exchanges (#{legacy[:exchanges].size})")
              legacy[:exchanges].each { |name| out.detail({ name: name }) }
              out.spacer
            end

            unless legacy[:queues].empty? # rubocop:disable Style/GuardClause
              out.detail_header("Legacy Queues (#{legacy[:queues].size})")
              legacy[:queues].each { |name| out.detail({ name: name }) }
              out.spacer
            end
          end

          def perform_deletion(legacy)
            legacy[:queues].each do |name|
              management_delete("/queues/#{vhost_encoded}/#{ERB::Util.url_encode(name)}")
            end
            legacy[:exchanges].each do |name|
              management_delete("/exchanges/#{vhost_encoded}/#{ERB::Util.url_encode(name)}")
            end
          end
        end
      end
    end
  end
end
