# frozen_string_literal: true

require 'net/http'

module Legion
  module Region
    include Legion::Logging::Helper if defined?(Legion::Logging::Helper)

    module_function

    UNSET = Object.new.freeze
    EXPECTED_METADATA_ERRORS = [
      Net::OpenTimeout,
      Net::ReadTimeout,
      Errno::EHOSTUNREACH,
      Errno::ECONNREFUSED,
      Errno::ENETUNREACH,
      IOError,
      SocketError
    ].freeze

    def current
      setting = defined?(Legion::Settings) ? Legion::Settings.dig(:region, :current) : nil
      return setting unless blank_region?(setting)

      @detected_region = UNSET unless instance_variable_defined?(:@detected_region)
      return nil if @detected_region.equal?(UNSET) && @metadata_detection_complete == true
      return @detected_region unless @detected_region.equal?(UNSET)

      @detected_region = detect_from_metadata
      @metadata_detection_complete = true
      @detected_region
    rescue StandardError => e
      Legion::Logging.debug "Region#current failed: #{e.message}" if defined?(Legion::Logging)
      nil
    end

    def reset!
      remove_instance_variable(:@detected_region) if instance_variable_defined?(:@detected_region)
      remove_instance_variable(:@metadata_detection_complete) if instance_variable_defined?(:@metadata_detection_complete)
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
    rescue StandardError => e
      Legion::Logging.debug "Region#primary failed: #{e.message}" if defined?(Legion::Logging)
      nil
    end

    def failover
      return nil unless defined?(Legion::Settings)

      Legion::Settings.dig(:region, :failover)
    rescue StandardError => e
      Legion::Logging.debug "Region#failover failed: #{e.message}" if defined?(Legion::Logging)
      nil
    end

    def peers
      return [] unless defined?(Legion::Settings)

      Legion::Settings.dig(:region, :peers) || []
    rescue StandardError => e
      Legion::Logging.debug "Region#peers failed: #{e.message}" if defined?(Legion::Logging)
      []
    end

    def detect_from_metadata
      detect_aws_region || detect_azure_region
    rescue StandardError => e
      Legion::Logging.debug "Region#detect_from_metadata failed: #{e.message}" if defined?(Legion::Logging)
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
    rescue *EXPECTED_METADATA_ERRORS
      nil
    rescue StandardError => e
      Legion::Logging.debug "Region#detect_aws_region failed: #{e.message}" if defined?(Legion::Logging)
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
    rescue *EXPECTED_METADATA_ERRORS
      nil
    rescue StandardError => e
      Legion::Logging.debug "Region#detect_azure_region failed: #{e.message}" if defined?(Legion::Logging)
      nil
    end

    def blank_region?(value)
      value.nil? || (value.respond_to?(:empty?) && value.empty?)
    end
    private_class_method :blank_region?
  end
end
