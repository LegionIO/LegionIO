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

      desc 'play NAME', 'Run a prompt through an LLM and display the response'
      option :variables, type: :string,  desc: 'Template variables as JSON'
      option :version,   type: :numeric, desc: 'Prompt version'
      option :model,     type: :string,  desc: 'LLM model override'
      option :provider,  type: :string,  desc: 'LLM provider override'
      option :compare,   type: :numeric, desc: 'Compare with this version'
      def play(name)
        out = formatter
        with_prompt_client do |client|
          unless defined?(Legion::LLM) && Legion::LLM.started?
            out.error('legion-llm is not available. Install legion-llm and configure a provider.')
            raise SystemExit, 1
          end

          vars = parse_variables(options[:variables], out)
          return if vars.nil?

          llm_kwargs = {}
          llm_kwargs[:model]    = options[:model]    if options[:model]
          llm_kwargs[:provider] = options[:provider] if options[:provider]

          base_ctx = { name: name, vars: vars, llm_kwargs: llm_kwargs, client: client, out: out }
          if options[:compare]
            run_compare(base_ctx.merge(ver_a: options[:version], ver_b: options[:compare]))
          else
            run_single(base_ctx.merge(version: options[:version]))
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
          Connection.ensure_llm

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

        def parse_variables(raw, out)
          return {} if raw.nil? || raw.empty?

          ::JSON.parse(raw)
        rescue ::JSON::ParserError => e
          out.error("Invalid JSON for --variables: #{e.message}")
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

        def run_single(ctx)
          name, version, vars, llm_kwargs, client, out = ctx.values_at(:name, :version, :vars, :llm_kwargs, :client, :out)
          prompt = fetch_prompt(name, version, client, out)
          return if prompt.nil?

          rendered = render_prompt(name, version, vars, client, out)
          return if rendered.nil?

          response = Legion::LLM.chat(
            messages: [{ role: 'user', content: rendered }],
            caller:   { source: 'cli', command: 'prompt' },
            **llm_kwargs
          )

          if options[:json]
            out.json({ name: name, version: prompt[:version], rendered: rendered,
                       response: response[:content], usage: response[:usage] })
          else
            out.header("Prompt: #{name} (v#{prompt[:version]})")
            out.spacer
            out.header('Rendered Template')
            puts rendered
            out.spacer
            out.header('LLM Response')
            puts response[:content]
            display_usage(response[:usage], out)
          end
        end

        def run_compare(ctx)
          name, ver_a, ver_b, vars, llm_kwargs, client, out =
            ctx.values_at(:name, :ver_a, :ver_b, :vars, :llm_kwargs, :client, :out)
          prompt_a = fetch_prompt(name, ver_a, client, out)
          return if prompt_a.nil?

          prompt_b = fetch_prompt(name, ver_b, client, out)
          return if prompt_b.nil?

          rendered_a = render_prompt(name, prompt_a[:version], vars, client, out)
          return if rendered_a.nil?

          rendered_b = render_prompt(name, prompt_b[:version], vars, client, out)
          return if rendered_b.nil?

          response_a = Legion::LLM.chat(messages: [{ role: 'user', content: rendered_a }],
                                        caller:   { source: 'cli', command: 'prompt' }, **llm_kwargs)
          response_b = Legion::LLM.chat(messages: [{ role: 'user', content: rendered_b }],
                                        caller:   { source: 'cli', command: 'prompt' }, **llm_kwargs)

          if options[:json]
            out.json({ name: name, version_a: prompt_a[:version], version_b: prompt_b[:version],
                       rendered_a: rendered_a, rendered_b: rendered_b,
                       response_a: response_a[:content], response_b: response_b[:content],
                       usage_a: response_a[:usage], usage_b: response_b[:usage] })
          else
            out.header("Version A (v#{prompt_a[:version]})")
            puts response_a[:content]
            out.spacer
            out.header("Version B (v#{prompt_b[:version]})")
            puts response_b[:content]
            content_a = response_a[:content].to_s
            content_b = response_b[:content].to_s
            if content_a != content_b
              out.spacer
              out.header('Diff (A vs B)')
              puts diff_lines(content_a, content_b)
            end
          end
        end

        def fetch_prompt(name, version, client, out)
          kwargs = { name: name }
          kwargs[:version] = version if version
          result = client.get_prompt(**kwargs)
          if result[:error]
            out.error("Prompt '#{name}': #{result[:error]}")
            raise SystemExit, 1
          end
          result
        end

        def render_prompt(name, version, vars, client, out)
          kwargs = { name: name, variables: vars }
          kwargs[:version] = version if version
          result = client.render_prompt(**kwargs)
          if result.is_a?(Hash) && result[:error]
            out.error("Render error for '#{name}': #{result[:error]}")
            raise SystemExit, 1
          end
          result.is_a?(Hash) ? result[:rendered] : result
        end

        def display_usage(usage, out)
          return unless usage && !usage.empty?

          out.spacer
          out.detail(usage)
        end
      end
    end
  end
end
