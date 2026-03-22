# frozen_string_literal: true

require 'net/http'

module Legion
  module Region
    module_function

    def current
      setting = defined?(Legion::Settings) ? Legion::Settings.dig(:region, :current) : nil
      setting || detect_from_metadata
    rescue StandardError
      nil
    end

    def local?(target_region)
      target_region.nil? || target_region == current
    end

    def affinity_for(message_region, affinity)
      return :local if local?(message_region) || affinity == 'any'
      return :remote if affinity == 'prefer_local'
      return :reject if affinity == 'require_local'

      :local
    end

    def primary
      return nil unless defined?(Legion::Settings)

      Legion::Settings.dig(:region, :primary)
    rescue StandardError
      nil
    end

    def failover
      return nil unless defined?(Legion::Settings)

      Legion::Settings.dig(:region, :failover)
    rescue StandardError
      nil
    end

    def peers
      return [] unless defined?(Legion::Settings)

      Legion::Settings.dig(:region, :peers) || []
    rescue StandardError
      []
    end

    def detect_from_metadata
      detect_aws_region || detect_azure_region
    rescue StandardError
      nil
    end

    def detect_aws_region
      uri = URI('http://169.254.169.254/latest/meta-data/placement/region')
      token_uri = URI('http://169.254.169.254/latest/api/token')

      token = Net::HTTP.start(token_uri.host, token_uri.port, open_timeout: 1, read_timeout: 1) do |http|
        req = Net::HTTP::Put.new(token_uri)
        req['X-aws-ec2-metadata-token-ttl-seconds'] = '21600'
        http.request(req).body
      end

      Net::HTTP.start(uri.host, uri.port, open_timeout: 1, read_timeout: 1) do |http|
        req = Net::HTTP::Get.new(uri)
        req['X-aws-ec2-metadata-token'] = token
        response = http.request(req)
        response.is_a?(Net::HTTPSuccess) ? response.body.strip : nil
      end
    rescue StandardError
      nil
    end

    def detect_azure_region
      uri = URI('http://169.254.169.254/metadata/instance/compute/location?api-version=2021-02-01&format=text')

      Net::HTTP.start(uri.host, uri.port, open_timeout: 1, read_timeout: 1) do |http|
        req = Net::HTTP::Get.new(uri)
        req['Metadata'] = 'true'
        response = http.request(req)
        response.is_a?(Net::HTTPSuccess) ? response.body.strip : nil
      end
    rescue StandardError
      nil
    end
  end
end
