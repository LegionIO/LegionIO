# frozen_string_literal: true

require 'thor'

module Legion
  module CLI
    class Prompt < Thor
      def self.exit_on_failure?
        true
      end

      class_option :json,       type: :boolean, default: false, desc: 'Output as JSON'
      class_option :no_color,   type: :boolean, default: false, desc: 'Disable color output'
      class_option :verbose,    type: :boolean, default: false, aliases: ['-V'], desc: 'Verbose logging'
      class_option :config_dir, type: :string,                  desc: 'Config directory path'

      desc 'list', 'List all prompts'
      def list
        out = formatter
        with_prompt_client do |client|
          prompts = client.list_prompts
          if options[:json]
            out.json(prompts)
          elsif prompts.empty?
            out.warn('No prompts found')
          else
            rows = prompts.map do |p|
              [p[:name].to_s, (p[:description] || '').to_s,
               (p[:latest_version] || '-').to_s, (p[:updated_at] || '-').to_s]
            end
            out.table(%w[name description version updated_at], rows)
          end
        end
      end
      default_task :list

      desc 'show NAME', 'Show a prompt template and parameters'
      option :version, type: :numeric, desc: 'Specific version number'
      option :tag,     type: :string,  desc: 'Tag name to resolve'
      def show(name)
        out = formatter
        with_prompt_client do |client|
          kwargs = { name: name }
          kwargs[:version] = options[:version] if options[:version]
          kwargs[:tag]     = options[:tag]     if options[:tag]
          result = client.get_prompt(**kwargs)
          if result[:error]
            out.error("Prompt '#{name}': #{result[:error]}")
            raise SystemExit, 1
          end

          if options[:json]
            out.json(result)
          else
            out.header("Prompt: #{result[:name]}")
            out.spacer
            out.detail({ version: result[:version], content_hash: result[:content_hash],
                         created_at: result[:created_at] })
            unless result[:model_params].nil? || result[:model_params].empty?
              out.spacer
              out.header('Model Params')
              out.detail(result[:model_params])
            end
            out.spacer
            puts result[:template]
          end
        end
      end

      desc 'create NAME', 'Create a new prompt'
      option :template,     type: :string, required: true, desc: 'Prompt template text'
      option :description,  type: :string,                  desc: 'Short description'
      option :model_params, type: :string,                  desc: 'Model parameters as JSON'
      def create(name)
        out = formatter
        with_prompt_client do |client|
          params = parse_model_params(options[:model_params], out)
          return if params.nil?

          result = client.create_prompt(
            name:         name,
            template:     options[:template],
            description:  options[:description],
            model_params: params
          )
          if options[:json]
            out.json(result)
          else
            out.success("Created prompt '#{result[:name]}' (version #{result[:version]})")
          end
        end
      end

      desc 'tag NAME TAG', 'Tag a prompt version'
      option :version, type: :numeric, desc: 'Version to tag (defaults to latest)'
      def tag(name, tag_name)
        out = formatter
        with_prompt_client do |client|
          kwargs = { name: name, tag: tag_name }
          kwargs[:version] = options[:version] if options[:version]
          result = client.tag_prompt(**kwargs)
          if result[:error]
            out.error("Prompt '#{name}': #{result[:error]}")
            raise SystemExit, 1
          end

          if options[:json]
            out.json(result)
          else
            out.success("Tagged '#{result[:name]}' v#{result[:version]} as '#{result[:tag]}'")
          end
        end
      end

      desc 'diff NAME V1 V2', 'Show text diff between two versions of a prompt'
      def diff(name, ver1, ver2)
        out = formatter
        with_prompt_client do |client|
          r1 = client.get_prompt(name: name, version: ver1.to_i)
          r2 = client.get_prompt(name: name, version: ver2.to_i)

          if r1[:error]
            out.error("Version #{ver1}: #{r1[:error]}")
            raise SystemExit, 1
          end
          if r2[:error]
            out.error("Version #{ver2}: #{r2[:error]}")
            raise SystemExit, 1
          end

          if options[:json]
            out.json({ name: name, v1: ver1.to_i, v2: ver2.to_i,
                       template_v1: r1[:template], template_v2: r2[:template] })
          else
            require 'diff/lcs' if defined?(Diff::LCS)
            puts "--- v#{ver1}"
            puts "+++ v#{ver2}"
            puts diff_lines(r1[:template].to_s, r2[:template].to_s)
          end
        end
      end

      no_commands do
        def formatter
          @formatter ||= Output::Formatter.new(
            json:  options[:json],
            color: !options[:no_color]
          )
        end

        def with_prompt_client
          Connection.config_dir = options[:config_dir] if options[:config_dir]
          Connection.log_level  = options[:verbose] ? 'debug' : 'error'
          Connection.ensure_data

          begin
            require 'legion/extensions/prompt'
            require 'legion/extensions/prompt/runners/prompt'
            require 'legion/extensions/prompt/client'
          rescue LoadError
            formatter.error('lex-prompt gem is not installed (gem install lex-prompt)')
            raise SystemExit, 1
          end

          db = Legion::Data.db
          client = Legion::Extensions::Prompt::Client.new(db: db)
          yield client
        rescue CLI::Error => e
          formatter.error(e.message)
          raise SystemExit, 1
        ensure
          Connection.shutdown
        end

        def parse_model_params(raw, out)
          return {} if raw.nil? || raw.empty?

          ::JSON.parse(raw)
        rescue ::JSON::ParserError => e
          out.error("Invalid JSON for --model-params: #{e.message}")
          nil
        end

        def diff_lines(old_text, new_text)
          old_lines = old_text.split("\n")
          new_lines = new_text.split("\n")
          result    = []
          old_set   = old_lines.to_set
          new_set   = new_lines.to_set
          old_lines.each { |l| result << "- #{l}" unless new_set.include?(l) }
          new_lines.each { |l| result << "+ #{l}" unless old_set.include?(l) }
          result.join("\n")
        end
      end
    end
  end
end
