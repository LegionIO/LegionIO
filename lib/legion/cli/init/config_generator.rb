# frozen_string_literal: true

require 'erb'
require 'fileutils'

module Legion
  module CLI
    module InitHelpers
      module ConfigGenerator
        TEMPLATE_DIR = File.expand_path('../templates', __dir__)
        CONFIG_DIR = File.expand_path('~/.legionio/settings')

        class << self
          def generate(options = {})
            FileUtils.mkdir_p(CONFIG_DIR)
            generated = []

            %w[core].each do |name|
              template_path = File.join(TEMPLATE_DIR, "#{name}.json.erb")
              next unless File.exist?(template_path)

              output_path = File.join(CONFIG_DIR, "#{name}.json")
              next if File.exist?(output_path) && !options[:force]

              content = render_template(template_path, options)
              File.write(output_path, content)
              generated << output_path
            end

            generated
          end

          def scaffold_workspace(dir = '.')
            workspace_dir = File.join(dir, '.legion')
            FileUtils.mkdir_p(File.join(workspace_dir, 'agents'))
            FileUtils.mkdir_p(File.join(workspace_dir, 'skills'))
            FileUtils.mkdir_p(File.join(workspace_dir, 'memory'))

            settings_path = File.join(workspace_dir, 'settings.json')
            File.write(settings_path, "{}\n") unless File.exist?(settings_path)

            workspace_dir
          end

          private

          def render_template(path, options)
            template = File.read(path)
            ERB.new(template, trim_mode: '-').result_with_hash(options: options)
          end
        end
      end
    end
  end
end
