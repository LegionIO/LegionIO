# frozen_string_literal: true

module Legion
  module CLI
    class Doctor
      class ExtensionsCheck
        LOADER_CONFIG_KEYS = %w[
          agentic ai auto_install blocked categories core gaia identity
          parallel_pool_size reserved_prefixes reserved_words
        ].freeze

        def name
          'Extensions'
        end

        def run
          configured = configured_extensions
          return Result.new(name: name, status: :skip, message: 'No extensions configured') if configured.empty?

          missing = []
          load_errors = []

          configured.each do |ext_name|
            gem_name = ext_name.start_with?('lex-') ? ext_name : "lex-#{ext_name}"
            Gem::Specification.find_by_name(gem_name)
            begin
              require gem_name.tr('-', '/')
            rescue LoadError => e
              load_errors << "#{gem_name}: #{e.message}"
            end
          rescue Gem::MissingSpecError
            missing << gem_name
          end

          build_result(configured, missing, load_errors)
        end

        private

        def configured_extensions
          return [] unless defined?(Legion::Settings)

          exts = Legion::Settings[:extensions]
          return [] unless exts.is_a?(Hash) || exts.is_a?(Array)

          if exts.is_a?(Array)
            exts.map(&:to_s)
          else
            exts.keys.map(&:to_s).reject { |key| LOADER_CONFIG_KEYS.include?(key) }
          end
        rescue StandardError => e
          Legion::Logging.warn("ExtensionsCheck#configured_extensions failed: #{e.message}") if defined?(Legion::Logging)
          []
        end

        def build_result(configured, missing, load_errors)
          issues = []
          prescriptions = []

          missing.each do |gem_name|
            issues << "#{gem_name} not installed"
            prescriptions << "Install with `gem install #{gem_name}`"
          end

          load_errors.each do |err|
            issues << "Load error: #{err}"
          end

          if issues.empty?
            Result.new(
              name:    name,
              status:  :pass,
              message: "#{configured.size} extension(s) installed and loadable"
            )
          else
            Result.new(
              name:         name,
              status:       :fail,
              message:      issues.join('; '),
              prescription: prescriptions.join('; ')
            )
          end
        end
      end
    end
  end
end
