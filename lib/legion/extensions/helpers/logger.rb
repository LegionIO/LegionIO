# frozen_string_literal: true

module Legion
  module Extensions
    module Helpers
      module Logger
        def log
          return @log unless @log.nil?

          logger_hash = { lex: lex_filename || nil }
          logger_hash[:lex] = lex_filename.first if logger_hash[:lex].is_a? Array
          if respond_to?(:settings) && settings.key?(:logger)
            logger_hash[:level] = settings[:logger].key?(:level) ? settings[:logger][:level] : 'info'
            logger_hash[:log_file] = settings[:logger][:log_file] if settings[:logger].key? :log_file
            logger_hash[:trace] = settings[:logger][:trace] if settings[:logger].key? :trace
            logger_hash[:extended] = settings[:logger][:extended] if settings[:logger].key? :extended
          elsif respond_to?(:settings)
            Legion::Logging.warn Legion::Settings[:extensions][lex_filename.to_sym]
            Legion::Logging.warn "#{lex_name} has settings but no :logger key"
          end
          @log = Legion::Logging::Logger.new(**logger_hash)
        end

        def handle_exception(exception, task_id: nil, **opts)
          log.error exception.message + " for task_id: #{task_id} but was logged "
          log.error exception.backtrace[0..10]
          log.error opts

          unless task_id.nil?
            Legion::Transport::Messages::TaskLog.new(
              task_id:      task_id,
              runner_class: to_s,
              entry:        {
                exception: true,
                message:   exception.message,
                **opts
              }
            ).publish
          end

          raise Legion::Exception::HandledTask
        end
      end
    end
  end
end
