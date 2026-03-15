# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'
require 'legion/cli/chat_command'

module Legion
  module CLI
    class Chat
      module Checkpoint
        Entry = Struct.new(:path, :content, :existed, :timestamp)

        @entries = []
        @max_depth = 10
        @mode = :per_edit
        @storage_dir = nil

        class << self
          attr_accessor :max_depth, :mode
          attr_reader :entries

          def configure(max_depth: 10, mode: :per_edit)
            @max_depth = max_depth
            @mode = mode
            @entries = []
            @storage_dir = nil
          end

          def save(path)
            expanded = File.expand_path(path)
            entry = Entry.new(
              path:      expanded,
              content:   File.exist?(expanded) ? File.read(expanded, encoding: 'utf-8') : nil,
              existed:   File.exist?(expanded),
              timestamp: Time.now
            )
            @entries.push(entry)
            @entries.shift while @entries.length > @max_depth
            persist_entry(entry)
            entry
          end

          def rewind(steps = 1)
            return [] if @entries.empty?

            steps = [steps, @entries.length].min
            restored = []
            steps.times do
              entry = @entries.pop
              restore_entry(entry)
              restored << entry
            end
            restored
          end

          def rewind_file(path)
            expanded = File.expand_path(path)
            idx = @entries.rindex { |e| e.path == expanded }
            return nil unless idx

            entry = @entries.delete_at(idx)
            restore_entry(entry)
            entry
          end

          def list
            @entries.map do |e|
              {
                path:      e.path,
                existed:   e.existed,
                timestamp: e.timestamp
              }
            end
          end

          def clear
            cleanup_storage
            @entries.clear
          end

          def count
            @entries.length
          end

          private

          def restore_entry(entry)
            if entry.existed
              FileUtils.mkdir_p(File.dirname(entry.path))
              File.write(entry.path, entry.content, encoding: 'utf-8')
            else
              FileUtils.rm_f(entry.path)
            end
          end

          def storage_dir
            @storage_dir ||= begin
              dir = File.join(Dir.tmpdir, "legion-checkpoint-#{::Process.pid}")
              FileUtils.mkdir_p(dir)
              dir
            end
          end

          def persist_entry(entry)
            return unless entry.existed

            safe_name = entry.path.gsub('/', '_').gsub('\\', '_')
            backup_path = File.join(storage_dir, "#{@entries.length}_#{safe_name}")
            File.write(backup_path, entry.content, encoding: 'utf-8')
          rescue StandardError
            # In-memory fallback is always available via @entries
            nil
          end

          def cleanup_storage
            return unless @storage_dir && Dir.exist?(@storage_dir)

            FileUtils.rm_rf(@storage_dir)
            @storage_dir = nil
          rescue StandardError
            nil
          end
        end
      end
    end
  end
end
