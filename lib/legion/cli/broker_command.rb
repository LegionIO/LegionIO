# frozen_string_literal: true

require 'net/http'
require 'erb'
require 'json'

module Legion
  module CLI
    class Broker < Thor
      namespace 'broker'

      def self.exit_on_failure?
        true
      end

      class_option :json,     type: :boolean, default: false,    desc: 'Output as JSON'
      class_option :no_color, type: :boolean, default: false,    desc: 'Disable color output'
      class_option :host,     type: :string,  default: 'localhost', desc: 'RabbitMQ management host'
      class_option :port,     type: :numeric, default: 15_672,   desc: 'RabbitMQ management port'
      class_option :user,     type: :string,  default: 'guest',  desc: 'RabbitMQ management username'
      class_option :password, type: :string,  default: 'guest',  desc: 'RabbitMQ management password'
      class_option :vhost,    type: :string,  default: '/',      desc: 'RabbitMQ vhost'

      desc 'stats', 'Show RabbitMQ broker statistics (queues, exchanges, consumers, DLX)'
      def stats
        out = formatter
        data = fetch_stats

        if options[:json]
          out.json(data)
        else
          out.header('RabbitMQ Broker Stats')
          out.spacer
          out.detail({
                       queues:    data[:queues],
                       exchanges: data[:exchanges],
                       consumers: data[:consumers],
                       dlx:       data[:dlx]
                     })
        end
      rescue Legion::CLI::Error => e
        formatter.error(e.message)
        exit(1)
      end

      desc 'cleanup', 'Find (and optionally delete) orphaned queues with 0 consumers and 0 messages'
      option :execute, type: :boolean, default: false, desc: 'Actually delete orphaned queues (default: dry-run)'
      def cleanup
        out = formatter
        orphans = find_orphans

        if orphans.empty?
          out.success('No orphaned queues found')
          return
        end

        if options[:json]
          out.json({ orphaned_queues: orphans, deleted: options[:execute] })
          delete_orphans(orphans) if options[:execute]
          return
        end

        out.header("Orphaned Queues (#{orphans.size})")
        orphans.each { |q| out.warn(q) }
        out.spacer

        if options[:execute]
          delete_orphans(orphans)
          out.success("Deleted #{orphans.size} orphaned queue(s)")
        else
          out.warn('Dry-run mode — pass --execute to delete')
        end
      rescue Legion::CLI::Error => e
        formatter.error(e.message)
        exit(1)
      end

      no_commands do
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

          raise Legion::CLI::Error, "Management API error #{response.code}: #{response.body}" unless response.is_a?(Net::HTTPSuccess)

          ::JSON.parse(response.body, symbolize_names: true)
        rescue Errno::ECONNREFUSED
          raise Legion::CLI::Error, "Cannot connect to RabbitMQ management API at #{options[:host]}:#{options[:port]}"
        rescue Net::OpenTimeout, Net::ReadTimeout
          raise Legion::CLI::Error, "Timed out connecting to RabbitMQ management API at #{options[:host]}:#{options[:port]}"
        end

        def management_delete(path)
          uri = URI("http://#{options[:host]}:#{options[:port]}/api#{path}")
          req = Net::HTTP::Delete.new(uri)
          req.basic_auth(options[:user], options[:password])

          Net::HTTP.start(uri.host, uri.port, open_timeout: 5, read_timeout: 10) do |http|
            http.request(req)
          end
        rescue Errno::ECONNREFUSED
          raise Legion::CLI::Error, "Cannot connect to RabbitMQ management API at #{options[:host]}:#{options[:port]}"
        end

        def fetch_stats
          queues    = management_api("/queues/#{vhost_encoded}")
          exchanges = management_api("/exchanges/#{vhost_encoded}")

          total_consumers = queues.sum { |q| q[:consumers].to_i }
          dlx_count       = queues.count { |q| q.dig(:arguments, :'x-dead-letter-exchange') }

          {
            queues:    queues.size,
            exchanges: exchanges.size,
            consumers: total_consumers,
            dlx:       dlx_count
          }
        end

        def find_orphans
          queues = management_api("/queues/#{vhost_encoded}")
          queues
            .select { |q| q[:consumers].to_i.zero? && q[:messages].to_i.zero? }
            .map    { |q| q[:name].to_s }
        end

        def delete_orphans(orphans)
          orphans.each do |name|
            management_delete("/queues/#{vhost_encoded}/#{ERB::Util.url_encode(name)}")
          end
        end
      end
    end
  end
end
