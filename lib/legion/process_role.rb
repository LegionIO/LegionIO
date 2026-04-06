# frozen_string_literal: true

module Legion
  module ProcessRole
    ROLES = {
      full:   { transport: true,  cache: true, data: true,  extensions: true,  api: true,  llm: true,  gaia: true,  crypt: true, supervision: true  },
      agent:  { transport: true,  cache: true, data: true,  extensions: true,  api: true,  llm: true,  gaia: true,  crypt: true, supervision: true  },
      api:    { transport: true,  cache: true, data: true,  extensions: false, api: true,  llm: false, gaia: false, crypt: true, supervision: false },
      worker: { transport: true,  cache: true, data: true,  extensions: true,  api: false, llm: true,  gaia: true,  crypt: true, supervision: true  },
      router: { transport: true,  cache: true, data: false, extensions: true,  api: false, llm: false, gaia: false, crypt: true, supervision: false },
      lite:   { transport: true,  cache: true, data: true,  extensions: true,  api: true,  llm: true,  gaia: true,  crypt: false, supervision: true  },
      infra:  { transport: true,  cache: true, data: true,  extensions: true,  api: true,  llm: true,  gaia: true,  crypt: true, supervision: true  }
    }.freeze

    def self.resolve(role_name)
      key = role_name.to_sym
      unless ROLES.key?(key)
        warn_unrecognized(key)
        key = :full
      end
      ROLES[key]
    end

    def self.current
      return Legion::Mode.current if defined?(Legion::Mode)

      settings = begin
        Legion::Settings[:process]
      rescue StandardError => e
        Legion::Logging.debug "ProcessRole#current failed to read process settings: #{e.message}" if defined?(Legion::Logging)
        nil
      end
      return :full unless settings.is_a?(Hash)

      role = settings[:role]
      return :full if role.nil?

      role.to_sym
    end

    def self.role?(name)
      current == name.to_sym
    end

    def self.warn_unrecognized(key)
      message = "ProcessRole: unrecognized role '#{key}', falling back to :full"
      if defined?(Legion::Logging) && Legion::Logging.respond_to?(:warn)
        Legion::Logging.warn(message)
      else
        warn "[Legion] #{message}"
      end
    end
    private_class_method :warn_unrecognized
  end
end
