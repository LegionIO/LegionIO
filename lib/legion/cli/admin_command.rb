# frozen_string_literal: true

require 'net/http'
require 'uri'

module Legion
  module CLI
    class AdminCommand < Thor
      namespace :admin

      desc 'purge-topology', 'Remove old v2.0 AMQP exchanges (legion.* that have lex.* counterparts)'
      method_option :dry_run,  type: :boolean, default: true,        desc: 'List without deleting'
      method_option :execute,  type: :boolean, default: false,       desc: 'Actually delete exchanges'
      method_option :host,     type: :string,  default: 'localhost', desc: 'RabbitMQ management host'
      method_option :port,     type: :numeric, default: 15_672,      desc: 'RabbitMQ management port'
      method_option :user,     type: :string,  default: 'guest',     desc: 'RabbitMQ management user'
      method_option :password, type: :string,  default: 'guest',     desc: 'RabbitMQ management password'
      method_option :vhost,    type: :string,  default: '/',         desc: 'RabbitMQ vhost'
      def purge_topology
        exchanges  = fetch_exchanges
        candidates = self.class.detect_old_exchanges(exchanges)

        if candidates.empty?
          say 'No old v2.0 topology exchanges found.', :green
          return
        end

        say "Found #{candidates.size} old v2.0 exchange(s):", :yellow
        candidates.each { |e| say "  #{e[:name]} (#{e[:type]})" }

        if options[:execute] && !options[:dry_run]
          candidates.each do |exchange|
            delete_exchange(exchange[:name])
            say "  Deleted: #{exchange[:name]}", :red
          end
          say "Purged #{candidates.size} exchange(s).", :green
        else
          say "\nDry run. Use --execute --no-dry-run to delete.", :cyan
        end
      end

      def self.detect_old_exchanges(exchanges)
        lex_names = exchanges.select { |e| e[:name].to_s.start_with?('lex.') }
                             .to_set { |e| e[:name].to_s.sub('lex.', '') }

        exchanges.select do |e|
          next false unless e[:name].to_s.start_with?('legion.')

          suffix = e[:name].to_s.sub('legion.', '')
          lex_names.include?(suffix)
        end
      end

      private

      def management_uri(path)
        vhost = URI.encode_www_form_component(options[:vhost])
        URI("http://#{options[:host]}:#{options[:port]}/api#{path}?vhost=#{vhost}")
      end

      def fetch_exchanges
        uri      = management_uri('/exchanges')
        response = management_get(uri)
        Legion::JSON.load(response.body).map { |e| { name: e[:name], type: e[:type] } }
      end

      def delete_exchange(name)
        vhost        = URI.encode_www_form_component(options[:vhost])
        encoded_name = URI.encode_www_form_component(name)
        uri          = URI("http://#{options[:host]}:#{options[:port]}/api/exchanges/#{vhost}/#{encoded_name}")
        management_request(uri, Net::HTTP::Delete)
      end

      def management_get(uri)
        management_request(uri, Net::HTTP::Get)
      end

      def management_request(uri, method_class)
        Net::HTTP.start(uri.host, uri.port) do |http|
          req = method_class.new(uri)
          req.basic_auth(options[:user], options[:password])
          http.request(req)
        end
      end
    end
  end
end
