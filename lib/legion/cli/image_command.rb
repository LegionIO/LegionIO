# frozen_string_literal: true

require 'thor'
require 'base64'

module Legion
  module CLI
    class Image < Thor
      def self.exit_on_failure?
        true
      end

      SUPPORTED_TYPES = %w[png jpg jpeg gif webp].freeze

      MIME_TYPES = {
        'png'  => 'image/png',
        'jpg'  => 'image/jpeg',
        'jpeg' => 'image/jpeg',
        'gif'  => 'image/gif',
        'webp' => 'image/webp'
      }.freeze

      class_option :json,       type: :boolean, default: false, desc: 'Output as JSON'
      class_option :no_color,   type: :boolean, default: false, desc: 'Disable color output'
      class_option :verbose,    type: :boolean, default: false, aliases: ['-V'], desc: 'Verbose logging'
      class_option :config_dir, type: :string,                  desc: 'Config directory path'

      desc 'analyze PATH', 'Analyze an image file using an LLM'
      option :prompt,    type: :string, aliases: ['-p'],
                         desc: 'Custom question to ask about the image',
                         default: 'Describe this image in detail'
      option :model,     type: :string, aliases: ['-m'], desc: 'LLM model override'
      option :provider,  type: :string,                  desc: 'LLM provider override'
      option :format,    type: :string, default: 'text', desc: 'Output format: text or json'
      def analyze(path)
        out = formatter
        setup_connection(out)

        image_data = load_image(path, out)
        return unless image_data

        messages = [build_image_message([image_data], options[:prompt])]
        response = call_llm(messages, out)
        return unless response

        render_response(out, response, { path: path, prompt: options[:prompt] })
      rescue CLI::Error => e
        formatter.error(e.message)
        raise SystemExit, 1
      ensure
        Connection.shutdown
      end

      desc 'compare PATH1 PATH2', 'Compare two images side by side using an LLM'
      option :prompt,    type: :string, aliases: ['-p'],
                         desc: 'Custom comparison question',
                         default: 'Compare these two images and describe the differences'
      option :model,     type: :string, aliases: ['-m'], desc: 'LLM model override'
      option :provider,  type: :string,                  desc: 'LLM provider override'
      option :format,    type: :string, default: 'text', desc: 'Output format: text or json'
      def compare(path1, path2)
        out = formatter
        setup_connection(out)

        image1 = load_image(path1, out)
        return unless image1

        image2 = load_image(path2, out)
        return unless image2

        messages = [build_image_message([image1, image2], options[:prompt])]
        response = call_llm(messages, out)
        return unless response

        render_response(out, response, { path1: path1, path2: path2, prompt: options[:prompt] })
      rescue CLI::Error => e
        formatter.error(e.message)
        raise SystemExit, 1
      ensure
        Connection.shutdown
      end

      no_commands do
        def formatter
          @formatter ||= Output::Formatter.new(
            json:  options[:json],
            color: !options[:no_color]
          )
        end

        def setup_connection(out)
          Connection.config_dir = options[:config_dir] if options[:config_dir]
          Connection.log_level  = options[:verbose] ? 'debug' : 'error'
          Connection.ensure_llm
        rescue CLI::Error => e
          out.error(e.message)
          raise SystemExit, 1
        end

        def load_image(path, out)
          unless File.exist?(path)
            out.error("File not found: #{path}")
            raise SystemExit, 1
          end

          ext = File.extname(path).delete_prefix('.').downcase
          unless SUPPORTED_TYPES.include?(ext)
            out.error("Unsupported image type '.#{ext}'. Supported: #{SUPPORTED_TYPES.join(', ')}")
            raise SystemExit, 1
          end

          {
            path:      path,
            mime_type: MIME_TYPES[ext],
            data:      Base64.strict_encode64(File.binread(path))
          }
        end

        def build_image_message(images, prompt_text)
          content = images.map do |img|
            {
              type:   'image',
              source: {
                type:       'base64',
                media_type: img[:mime_type],
                data:       img[:data]
              }
            }
          end
          content << { type: 'text', text: prompt_text }
          { role: 'user', content: content }
        end

        def call_llm(messages, out)
          llm_kwargs = {}
          llm_kwargs[:model]    = options[:model]           if options[:model]
          llm_kwargs[:provider] = options[:provider].to_sym if options[:provider]

          Legion::LLM.chat(messages: messages, **llm_kwargs)
        rescue StandardError => e
          out.error("LLM call failed: #{e.message}")
          raise SystemExit, 1
        end

        def render_response(out, response, meta)
          content = response[:content].to_s
          usage   = response[:usage] || {}

          if options[:format] == 'json' || options[:json]
            out.json(meta.merge(response: content, usage: usage))
          else
            out.header('Analysis')
            out.spacer
            puts content
            return if usage.nil? || usage.empty?

            out.spacer
            out.detail(usage)
          end
        end
      end
    end
  end
end
