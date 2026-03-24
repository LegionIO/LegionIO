# frozen_string_literal: true

require 'fileutils'
require 'legion/cli/chat_command'

module Legion
  module CLI
    class Chat
      module SessionStore
        SESSIONS_DIR = File.expand_path('~/.legion/sessions')

        class << self
          def save(session, name)
            FileUtils.mkdir_p(SESSIONS_DIR)

            messages = session.chat.messages.map(&:to_h)
            data = {
              name:          name,
              model:         session.model_id,
              stats:         session.stats,
              saved_at:      Time.now.iso8601,
              message_count: messages.size,
              summary:       generate_summary(messages),
              messages:      messages
            }

            path = session_path(name)
            File.write(path, Legion::JSON.dump(data))
            path
          end

          def load(name)
            path = session_path(name)
            raise CLI::Error, "Session not found: #{name}" unless File.exist?(path)

            Legion::JSON.load(File.read(path))
          end

          def restore(session, data)
            session.chat.reset_messages!
            data[:messages].each do |msg|
              session.chat.add_message(msg)
            end
            data
          end

          def list
            return [] unless Dir.exist?(SESSIONS_DIR)

            sessions = Dir.glob(File.join(SESSIONS_DIR, '*.json')).map do |path|
              name = File.basename(path, '.json')
              stat = File.stat(path)
              meta = read_session_meta(path)
              {
                name:          name,
                size:          stat.size,
                modified:      stat.mtime,
                message_count: meta[:message_count],
                summary:       meta[:summary],
                model:         meta[:model]
              }
            end
            sessions.sort_by { |s| s[:modified] }.reverse
          end

          def latest
            sessions = list
            raise CLI::Error, 'No saved sessions found.' if sessions.empty?

            sessions.first[:name]
          end

          def delete(name)
            path = session_path(name)
            raise CLI::Error, "Session not found: #{name}" unless File.exist?(path)

            File.delete(path)
          end

          def session_path(name)
            File.join(SESSIONS_DIR, "#{name}.json")
          end

          private

          def generate_summary(messages)
            user_messages = messages.select { |m| m[:role]&.to_s == 'user' }
            return nil if user_messages.empty?

            first_msg = user_messages.first[:content].to_s.strip
            first_msg = "#{first_msg[0..120]}..." if first_msg.length > 120
            first_msg
          rescue StandardError => e
            Legion::Logging.debug("SessionStore#generate_summary failed: #{e.message}") if defined?(Legion::Logging)
            nil
          end

          def read_session_meta(path)
            raw = File.read(path, encoding: 'utf-8')
            data = Legion::JSON.load(raw)
            {
              message_count: data[:message_count] || data[:messages]&.size,
              summary:       data[:summary],
              model:         data[:model]
            }
          rescue StandardError => e
            Legion::Logging.debug("SessionStore#read_session_meta failed: #{e.message}") if defined?(Legion::Logging)
            { message_count: nil, summary: nil, model: nil }
          end
        end
      end
    end
  end
end
