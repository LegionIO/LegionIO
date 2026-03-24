# frozen_string_literal: true

module Legion
  module CLI
    class Doctor
      class TlsCheck
        def name
          'TLS'
        end

        def run
          return Result.new(name: name, status: :skip, message: 'Legion::Settings not available') unless defined?(Legion::Settings)

          issues  = []
          any_tls = false

          check_transport_tls(issues) && (any_tls = true)
          check_data_tls(issues)      && (any_tls = true)
          check_api_tls(issues)       && (any_tls = true)

          build_result(issues, any_tls)
        rescue StandardError => e
          Result.new(
            name:         name,
            status:       :fail,
            message:      "TLS check error: #{e.message}",
            prescription: 'Review TLS settings configuration'
          )
        end

        private

        def check_transport_tls(issues)
          tls = safe_tls_settings(:transport)
          return false unless tls[:enabled]

          issues << 'transport.tls: verify is none — peer verification disabled' if tls[:verify].to_s == 'none'

          check_cert_file(tls[:cert], 'transport.tls.cert', issues)
          check_cert_file(tls[:key],  'transport.tls.key',  issues)
          check_cert_file(tls[:ca],   'transport.tls.ca',   issues)
          true
        end

        def check_data_tls(issues)
          tls = safe_tls_settings(:data)
          return false unless tls[:enabled]

          sslmode = tls[:sslmode].to_s
          issues << "data.tls: sslmode is '#{sslmode}' — use 'verify-full' to prevent MITM" unless sslmode.empty? || sslmode == 'verify-full'

          true
        end

        def check_api_tls(issues)
          tls = safe_tls_settings(:api)
          return false unless tls[:enabled]

          cert = tls[:cert]
          key  = tls[:key]

          if cert.nil? || cert.to_s.empty?
            issues << 'api.tls: enabled but api.tls.cert is not set'
            return true
          end

          if key.nil? || key.to_s.empty?
            issues << 'api.tls: enabled but api.tls.key is not set'
            return true
          end

          check_cert_file(cert, 'api.tls.cert', issues)
          check_cert_file(key,  'api.tls.key',  issues)
          true
        end

        def build_result(issues, any_tls)
          return Result.new(name: name, status: :pass, message: 'TLS not enabled on any component') unless any_tls

          if issues.any? { |i| i.include?('not set') }
            return Result.new(
              name:         name,
              status:       :fail,
              message:      issues.first,
              prescription: 'Set the missing TLS cert/key paths in settings'
            )
          end

          if issues.any?
            return Result.new(
              name:         name,
              status:       :warn,
              message:      issues.first,
              prescription: 'Review TLS configuration — see api.tls / transport.tls / data.tls in settings'
            )
          end

          Result.new(name: name, status: :pass, message: 'TLS configured correctly on enabled components')
        end

        def safe_tls_settings(component)
          raw = Legion::Settings[component] || {}
          tls = raw[:tls] || raw['tls'] || {}
          symbolize_keys(tls)
        rescue StandardError
          {}
        end

        def check_cert_file(path, label, issues)
          return if path.nil? || path.to_s.empty?
          return if path.to_s.start_with?('vault://', 'env://', 'lease://')
          return if ::File.exist?(path.to_s)

          issues << "#{label}: '#{path}' does not exist"
        end

        def symbolize_keys(hash)
          return {} unless hash.is_a?(Hash)

          hash.each_with_object({}) { |(k, v), h| h[k.to_sym] = v }
        end
      end
    end
  end
end
