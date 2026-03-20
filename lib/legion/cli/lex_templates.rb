# frozen_string_literal: true

require 'erb'
require 'fileutils'

module Legion
  module CLI
    module LexTemplates
      TEMPLATES_DIR = File.join(File.dirname(__FILE__), 'lex', 'templates').freeze

      REGISTRY = {
        'basic'               => {
          runners:      ['default'],
          actors:       ['subscription'],
          tools:        [],
          client:       false,
          dependencies: [],
          description:  'Basic extension with subscription actor'
        },
        'llm-agent'           => {
          runners:      %w[processor analyzer],
          actors:       %w[subscription polling],
          tools:        %w[process analyze],
          client:       true,
          dependencies: ['legion-llm'],
          description:  'LLM-powered agent extension',
          template_dir: 'llm_agent'
        },
        'service-integration' => {
          runners:      ['operations'],
          actors:       ['subscription'],
          tools:        [],
          client:       true,
          dependencies: [],
          description:  'External service integration with standalone client',
          template_dir: 'service_integration'
        },
        'data-pipeline'       => {
          runners:      ['transform'],
          actors:       ['ingest'],
          tools:        [],
          client:       false,
          dependencies: [],
          description:  'Event-driven data processing pipeline',
          template_dir: 'data_pipeline'
        },
        'scheduled-task'      => {
          runners:      ['executor'],
          actors:       ['interval'],
          tools:        [],
          client:       false,
          dependencies: [],
          description:  'Scheduled task with interval actor'
        },
        'webhook-handler'     => {
          runners:      %w[handler validator],
          actors:       ['subscription'],
          tools:        [],
          client:       false,
          dependencies: [],
          description:  'Inbound webhook processing'
        }
      }.freeze

      class << self
        def list
          REGISTRY.map { |name, config| { name: name, description: config[:description] } }
        end

        def get(name)
          REGISTRY[name.to_s]
        end

        def valid?(name)
          REGISTRY.key?(name.to_s)
        end

        def template_dir(name)
          config = REGISTRY[name.to_s]
          return nil unless config

          dir_key = config[:template_dir]
          return nil unless dir_key

          File.join(TEMPLATES_DIR, dir_key)
        end
      end

      # Renders and writes template-specific overlay files into the target extension directory.
      class TemplateOverlay
        PLACEHOLDER = '%name%'

        # vars: { gem_name:, lex_name:, lex_class:, name_class: }
        def initialize(template_name, target_dir, vars)
          @template_name = template_name
          @target_dir    = target_dir
          @vars          = vars
        end

        def apply(out = nil)
          src = LexTemplates.template_dir(@template_name)
          return unless src && Dir.exist?(src)

          each_template_file(src) do |abs_src, rel_path|
            dest_rel = rel_path.gsub(PLACEHOLDER, @vars[:lex_name])
            dest_rel = dest_rel.sub(/\.erb$/, '')
            dest_abs = File.join(@target_dir, dest_rel)

            FileUtils.mkdir_p(File.dirname(dest_abs))
            rendered = render_erb(File.read(abs_src))
            File.write(dest_abs, rendered)
            out&.success("  [#{@template_name}] #{dest_rel}")
          end
        end

        private

        def each_template_file(src_dir, &block)
          Dir.glob("#{src_dir}/**/*.erb").each do |abs_src|
            rel_path = abs_src.sub("#{src_dir}/", '')
            block.call(abs_src, rel_path)
          end
        end

        def render_erb(template_text)
          lex_class  = @vars[:lex_class]
          lex_name   = @vars[:lex_name]
          name_class = @vars[:name_class]
          gem_name   = @vars[:gem_name]

          ERB.new(template_text, trim_mode: '-').result(binding)
        end
      end
    end
  end
end
