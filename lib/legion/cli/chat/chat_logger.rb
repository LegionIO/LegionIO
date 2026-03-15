# frozen_string_literal: true

require 'logger'
require 'fileutils'

module Legion
  module CLI
    class Chat
      module ChatLogger
        LOG_DIR  = File.expand_path('~/.legion')
        LOG_FILE = File.join(LOG_DIR, 'legion-chat.log')

        class << self
          attr_reader :logger

          def setup(level: 'info')
            FileUtils.mkdir_p(LOG_DIR)
            @logger = ::Logger.new(LOG_FILE, 5, 1_048_576) # 5 rotated files, 1MB each
            @logger.level = parse_level(level)
            @logger.formatter = method(:format_entry)
            @logger
          end

          def debug(msg)  = logger&.debug(msg)
          def info(msg)   = logger&.info(msg)
          def warn(msg)   = logger&.warn(msg)
          def error(msg)  = logger&.error(msg)

          private

          def parse_level(level)
            case level.to_s
            when 'debug' then ::Logger::DEBUG
            when 'warn'  then ::Logger::WARN
            when 'error' then ::Logger::ERROR
            else ::Logger::INFO
            end
          end

          def format_entry(severity, datetime, _progname, msg)
            "[#{datetime.strftime('%Y-%m-%d %H:%M:%S.%L')}] #{severity.ljust(5)} #{msg}\n"
          end
        end
      end
    end
  end
end
