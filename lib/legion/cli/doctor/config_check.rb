# frozen_string_literal: true

require 'json'

module Legion
  module CLI
    class Doctor
      class ConfigCheck
        CONFIG_PATHS = [
          File.expand_path('~/.legionio/settings'),
          '/etc/legionio',
          File.expand_path('./settings')
        ].freeze

        def name
          'Config files'
        end

        def run
          found_dirs = CONFIG_PATHS.select { |p| Dir.exist?(p) }

          if found_dirs.empty?
            return Result.new(
              name:         name,
              status:       :warn,
              message:      "No config directory found (checked: #{CONFIG_PATHS.join(', ')})",
              prescription: 'Run `legion config scaffold` to generate starter config',
              auto_fixable: true
            )
          end

          invalid_files = find_invalid_json_files(found_dirs)
          if invalid_files.any?
            messages = invalid_files.map { |f, err| "#{f}: #{err}" }
            return Result.new(
              name:         name,
              status:       :fail,
              message:      "Invalid JSON in config files: #{messages.join('; ')}",
              prescription: messages.map { |m| "Fix JSON syntax error in #{m}" }.join('; ')
            )
          end

          Result.new(
            name:    name,
            status:  :pass,
            message: "Config found in: #{found_dirs.join(', ')}"
          )
        end

        def fix
          system('legion config scaffold')
        end

        private

        def find_invalid_json_files(dirs)
          errors = {}
          dirs.each do |dir|
            Dir.glob("#{dir}/*.json").each do |file|
              content = File.read(file)
              ::JSON.parse(content)
            rescue ::JSON::ParserError => e
              errors[file] = e.message.split("\n").first
            rescue Errno::EACCES
              errors[file] = 'permission denied'
            end
          end
          errors
        end
      end
    end
  end
end
