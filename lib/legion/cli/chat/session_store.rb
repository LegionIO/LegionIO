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

            data = {
              name:     name,
              model:    session.model_id,
              stats:    session.stats,
              saved_at: Time.now.iso8601,
              messages: session.chat.messages.map(&:to_h)
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
              { name: name, size: stat.size, modified: stat.mtime }
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
        end
      end
    end
  end
end
