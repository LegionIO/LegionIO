# frozen_string_literal: true

require 'fileutils'

module Legion
  module Helpers
    module Context
      class << self
        def write(agent_id:, filename:, content:)
          path = agent_path(agent_id, filename)
          FileUtils.mkdir_p(File.dirname(path))
          File.write(path, content)
          { success: true, path: path }
        end

        def read(agent_id:, filename:)
          path = agent_path(agent_id, filename)
          return { success: false, reason: :not_found } unless File.exist?(path)

          { success: true, content: File.read(path), path: path }
        end

        def list(agent_id: nil)
          base = agent_id ? File.join(context_dir, agent_id.to_s) : context_dir
          return { success: true, files: [] } unless Dir.exist?(base)

          files = Dir.glob(File.join(base, '**', '*')).select { |f| File.file?(f) }
                                                      .map do |f|
            f.sub("#{context_dir}/",
                  '')
          end
          { success: true, files: files }
        end

        def cleanup(max_age: 86_400)
          return { success: true, removed: 0 } unless Dir.exist?(context_dir)

          cutoff = Time.now.utc - max_age
          removed = 0
          Dir.glob(File.join(context_dir, '**', '*')).select { |f| File.file?(f) }.each do |f|
            next unless File.mtime(f) < cutoff

            File.delete(f)
            removed += 1
          end
          { success: true, removed: removed }
        end

        def context_dir
          dir = Legion::Settings.dig(:context, :directory) if defined?(Legion::Settings)
          dir || File.join(Dir.pwd, '.legion-context')
        end

        private

        def agent_path(agent_id, filename)
          File.join(context_dir, agent_id.to_s, filename.to_s)
        end
      end
    end
  end
end
