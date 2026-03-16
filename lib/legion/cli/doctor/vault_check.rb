# frozen_string_literal: true

require 'socket'
require 'net/http'
require 'uri'
require 'json'

module Legion
  module CLI
    class Doctor
      class VaultCheck
        DEFAULT_HOST = 'localhost'
        DEFAULT_PORT = 8200

        def name
          'Vault'
        end

        def run
          host, port = read_vault_config
          return Result.new(name: name, status: :skip, message: 'Vault not configured') if host.nil?

          check_vault(host, port)
        end

        private

        def read_vault_config
          return [nil, nil] unless defined?(Legion::Settings)

          crypt = Legion::Settings[:crypt]
          return [nil, nil] unless crypt.is_a?(Hash) && crypt[:vault_enabled]

          addr = crypt[:vault_address] || crypt[:vault_addr] || "http://#{DEFAULT_HOST}:#{DEFAULT_PORT}"
          uri = URI.parse(addr)
          [uri.host || DEFAULT_HOST, uri.port || DEFAULT_PORT]
        rescue StandardError
          [nil, nil]
        end

        def check_vault(host, port)
          uri = URI("http://#{host}:#{port}/v1/sys/health")
          http = Net::HTTP.new(uri.host, uri.port)
          http.open_timeout = 3
          http.read_timeout = 3
          response = http.get(uri.path)
          body = ::JSON.parse(response.body)

          if body['sealed']
            Result.new(
              name:         name,
              status:       :warn,
              message:      "Vault is sealed at #{host}:#{port}",
              prescription: 'Unseal Vault: `vault operator unseal`'
            )
          else
            Result.new(name: name, status: :pass, message: "Vault #{host}:#{port} reachable and unsealed")
          end
        rescue Errno::ECONNREFUSED, Errno::ETIMEDOUT, SocketError, Net::OpenTimeout
          Result.new(
            name:         name,
            status:       :fail,
            message:      "Cannot connect to Vault at #{host}:#{port}",
            prescription: 'Check Vault address and token in settings'
          )
        rescue ::JSON::ParserError
          Result.new(
            name:    name,
            status:  :warn,
            message: "Vault responded but returned unexpected body at #{host}:#{port}"
          )
        end
      end
    end
  end
end
