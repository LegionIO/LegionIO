# frozen_string_literal: true

require 'fileutils'
require 'legion/extensions/helpers/segments'
require 'legion/cli/lex_cli_manifest'
require 'legion/cli/lex_templates'

module Legion
  module CLI
    class Lex < Thor
      DEFAULT_CATEGORIES = {
        core:    { type: :list, tier: 1 },
        ai:      { type: :list, tier: 2 },
        gaia:    { type: :list, tier: 3 },
        agentic: { type: :prefix, tier: 4 }
      }.freeze

      def self.exit_on_failure?
        true
      end

      class_option :json, type: :boolean, default: false, desc: 'Output as JSON'
      class_option :no_color, type: :boolean, default: false, desc: 'Disable color output'

      desc 'list [CATEGORY]', 'List all installed extensions, optionally filtered by category'
      option :all,  type: :boolean, default: false, aliases: ['-a'], desc: 'Include disabled extensions'
      option :flat, type: :boolean, default: false, desc: 'Show all extensions in a flat list without category grouping'
      def list(category = nil)
        out  = formatter
        lexs = discover_all

        rows = options[:all] ? lexs : lexs.reject { |l| l[:status] == 'disabled' }
        rows = rows.select { |l| l[:category] == category } if category

        if options[:flat] || category
          render_flat_table(out, rows)
        else
          render_grouped_table(out, rows)
        end
      end
      default_task :list

      desc 'info NAME', 'Show detailed extension information'
      def info(name)
        out = formatter
        lex = find_lex(name)

        unless lex
          out.error("Extension '#{name}' not found. Run `legion lex list` to see installed extensions.")
          raise SystemExit, 1
        end

        if options[:json]
          out.json(lex)
          return
        end

        out.header("lex-#{lex[:name]} v#{lex[:version]}")
        out.spacer
        out.detail({
                     name:    lex[:name],
                     version: lex[:version],
                     status:  lex[:status],
                     gem_dir: lex[:gem_dir],
                     class:   lex[:extension_class]
                   })

        if lex[:runners].is_a?(Array) && lex[:runners].any?
          out.spacer
          out.header('Runners')
          lex[:runners].each do |runner|
            puts "  #{out.colorize(runner, :cyan)}"
          end
        end

        if lex[:actors].is_a?(Array) && lex[:actors].any?
          out.spacer
          out.header('Actors')
          lex[:actors].each do |actor|
            puts "  #{out.colorize(actor[:name], :cyan)}  #{out.colorize(actor[:type], :gray)}"
          end
        end

        return unless lex[:dependencies].is_a?(Array) && lex[:dependencies].any?

        out.spacer
        out.header('Dependencies')
        lex[:dependencies].each do |dep|
          puts "  #{dep}"
        end
      end

      desc 'create NAME', 'Scaffold a new Legion extension'
      method_option :rspec, type: :boolean, default: true, desc: 'Include RSpec setup'
      method_option :github_ci, type: :boolean, default: true, desc: 'Include GitHub Actions CI'
      method_option :git_init, type: :boolean, default: true, desc: 'Initialize git repository'
      method_option :bundle_install, type: :boolean, default: true, desc: 'Run bundle install'
      method_option :category, type: :string, default: nil,
                               desc: 'Extension category (agentic, ai, gaia). Determines namespace nesting and gem prefix.'
      method_option :template, type: :string, default: 'basic',
                               desc: 'Scaffold template: basic, llm-agent, service-integration, data-pipeline'
      method_option :list_templates, type: :boolean, default: false,
                                     desc: 'List available scaffold templates and exit'
      def create(name = nil)
        out = formatter

        if options[:list_templates]
          render_template_list(out)
          return
        end

        unless name
          out.error('NAME is required. Usage: legion lex create NAME [--template TEMPLATE]')
          return
        end

        if options[:category] && options[:category] !~ /\A[a-z][a-z0-9_-]*\z/
          out.error('--category must be lowercase letters, numbers, underscores, or hyphens')
          return
        end

        template_name = options[:template] || 'basic'
        unless LexTemplates.valid?(template_name)
          out.warn("Unknown template '#{template_name}', falling back to 'basic'. Run `legion lex create --list-templates` to see available templates.")
          template_name = 'basic'
        end

        gem_name = options[:category] ? "lex-#{options[:category]}-#{name}" : "lex-#{name}"
        target_dir = gem_name

        if Dir.exist?(target_dir)
          out.error("Directory #{target_dir} already exists")
          raise SystemExit, 1
        end

        if Dir.pwd.include?('lex-')
          out.error('Already inside a LEX directory. Move to a parent directory first.')
          raise SystemExit, 1
        end

        Legion::Extensions.check_reserved_words(gem_name, known_org: false)

        out.success("Creating #{gem_name} (template: #{template_name})...")

        vars = { filename: target_dir, class_name: name.split('_').map(&:capitalize).join, lex: name }

        generator = LexGenerator.new(name, vars, options, gem_name: gem_name, template: template_name)
        generator.generate(out)

        out.spacer
        out.success("Extension #{gem_name} created in ./#{target_dir}")
        out.spacer
        puts '  Next steps:'
        puts "    cd #{target_dir}"
        puts '    bundle install' unless options[:bundle_install]
        puts '    # Add runners:  legion generate runner my_runner'
        puts '    # Add actors:   legion generate actor my_actor'
      end

      desc 'enable NAME', 'Enable an extension in settings'
      def enable(name)
        out = formatter
        Connection.ensure_settings

        extensions = Legion::Settings[:extensions] || {}
        if extensions.key?(name.to_sym)
          extensions[name.to_sym][:enabled] = true
        else
          extensions[name.to_sym] = { enabled: true }
        end

        out.success("Extension '#{name}' enabled")
        out.warn('Restart Legion for changes to take effect') unless options[:json]
      end

      desc 'disable NAME', 'Disable an extension in settings'
      def disable(name)
        out = formatter
        Connection.ensure_settings

        extensions = Legion::Settings[:extensions] || {}
        if extensions.key?(name.to_sym)
          extensions[name.to_sym][:enabled] = false
          out.success("Extension '#{name}' disabled")
        else
          out.warn("Extension '#{name}' not found in settings (may not be configured)")
        end
        out.warn('Restart Legion for changes to take effect') unless options[:json]
      end

      desc 'invoke_ext EXTENSION COMMAND [METHOD]', 'Run a LEX CLI command'
      map 'exec' => :invoke_ext
      def invoke_ext(ext_name, command = nil, method_name = nil)
        out = formatter
        manifest = LexCliManifest.new
        gem_name = manifest.resolve_alias(ext_name) || "lex-#{ext_name}"
        gem_manifest = manifest.read_manifest(gem_name)

        unless gem_manifest
          out.error("Unknown extension: #{ext_name}. Run `legion lex list` to see installed extensions.")
          return
        end

        unless command && gem_manifest.dig('commands', command)
          out.header("Available commands for #{ext_name}:")
          gem_manifest['commands'].each do |cmd, info|
            methods = info['methods'].map { |m, d| "#{m} - #{d['desc']}" }.join(', ')
            puts "  #{out.colorize(cmd, :cyan)}: #{methods}"
          end
          return
        end

        unless method_name && gem_manifest.dig('commands', command, 'methods', method_name)
          methods = gem_manifest.dig('commands', command, 'methods')
          out.header("Available methods for #{command}:")
          methods.each do |m, d|
            puts "  #{out.colorize(m, :cyan)} - #{d['desc']}"
          end
          return
        end

        require gem_name.tr('-', '/').tr('_', '/')
        klass = Object.const_get(gem_manifest.dig('commands', command, 'class'))
        instance = klass.new
        instance.public_send(method_name.to_sym)
      rescue LoadError => e
        out.error("Failed to load #{gem_name}: #{e.message}")
      rescue StandardError => e
        out.error("Error running #{ext_name} #{command} #{method_name}: #{e.message}")
      end

      desc 'fixes', 'List pending auto-fix patches'
      option :status, type: :string, desc: 'Filter by status: pending, approved, rejected'
      def fixes
        out = formatter
        with_data do
          require 'legion/extensions/codegen/runners/auto_fix'
          result = Legion::Extensions::Codegen::Runners::AutoFix.list_fixes(status: options[:status])
          if options[:json]
            out.json(result)
          elsif result[:fixes].empty?
            out.warn('No fixes found')
          else
            rows = result[:fixes].map do |f|
              [f[:fix_id][0..7], f[:gem_name], f[:status], f[:specs_passed] ? 'PASS' : 'FAIL',
               f[:branch], f[:created_at]]
            end
            out.table(%w[ID Gem Status Specs Branch Created], rows)
          end
        end
      end

      desc 'approve-fix FIX_ID', 'Approve an auto-generated fix'
      def approve_fix(fix_id)
        out = formatter
        with_data do
          require 'legion/extensions/codegen/runners/auto_fix'
          result = Legion::Extensions::Codegen::Runners::AutoFix.approve_fix(fix_id: fix_id)
          if result[:success]
            out.success("Fix #{fix_id} approved. Merge the branch manually.")
          else
            out.error("Failed to approve: #{result[:reason]}")
          end
        end
      end
      map 'approve_fix' => :approve_fix

      desc 'reject-fix FIX_ID', 'Reject an auto-generated fix'
      def reject_fix(fix_id)
        out = formatter
        with_data do
          require 'legion/extensions/codegen/runners/auto_fix'
          result = Legion::Extensions::Codegen::Runners::AutoFix.reject_fix(fix_id: fix_id)
          if result[:success]
            out.success("Fix #{fix_id} rejected.")
          else
            out.error("Failed to reject: #{result[:reason]}")
          end
        end
      end
      map 'reject_fix' => :reject_fix

      no_commands do # rubocop:disable Metrics/BlockLength
        def formatter
          @formatter ||= Output::Formatter.new(
            json:  options[:json],
            color: !options[:no_color]
          )
        end

        def render_template_list(out)
          templates = LexTemplates.list
          if options[:json]
            out.json(templates)
          else
            out.header('Available scaffold templates')
            rows = templates.map { |t| [t[:name], t[:description]] }
            out.table(%w[template description], rows)
          end
        end

        def format_runners(runners)
          return '-' unless runners.is_a?(Array) && runners.any?

          runners.length <= 3 ? runners.join(', ') : "#{runners.length} runners"
        end

        def format_actors(actors)
          return '-' unless actors.is_a?(Array) && actors.any?

          names = actors.map { |a| a.is_a?(Hash) ? a[:name] : a.to_s }
          names.length <= 3 ? names.join(', ') : "#{names.length} actors"
        end

        def render_flat_table(out, rows)
          if options[:json]
            out.json(rows)
            return
          end

          table_rows = rows.sort_by { |l| l[:name] }.map do |l|
            [l[:name], l[:version], l[:category].to_s, out.status(l[:status]),
             format_runners(l[:runners]), format_actors(l[:actors])]
          end
          out.table(%w[name version category status runners actors], table_rows)
        end

        def render_grouped_table(out, rows)
          if options[:json]
            out.json(rows)
            return
          end

          grouped = rows.group_by { |l| [l[:tier], l[:category]] }
          grouped.keys.sort_by { |tier, cat| [tier, cat.to_s] }.each do |key|
            tier, cat = key
            out.spacer
            out.header("#{cat} (tier #{tier})")
            group_rows = grouped[key].sort_by { |l| l[:name] }.map do |l|
              [l[:name], l[:version], out.status(l[:status]),
               format_runners(l[:runners]), format_actors(l[:actors])]
            end
            out.table(%w[name version status runners actors], group_rows)
          end
        end

        def discover_all
          installed = Gem::Specification.select { |s| s.name.start_with?('lex-') }

          # Load settings to check enabled/disabled state
          begin
            Connection.ensure_settings
            ext_settings = Legion::Settings[:extensions] || {}
          rescue StandardError => e
            Legion::Logging.warn("LexCommand#discover_all settings load failed: #{e.message}") if defined?(Legion::Logging)
            ext_settings = {}
          end

          categories = resolve_categories
          cat_lists  = resolve_cat_lists

          result = installed.map do |spec|
            short_name = spec.name.sub('lex-', '')
            extension_class = Legion::Extensions::Helpers::Segments.derive_const_path(spec.name)

            setting = ext_settings[short_name.to_sym] || {}
            status  = setting[:enabled] == false ? 'disabled' : 'installed'

            runner_info = extract_runners(spec)
            actor_info  = extract_actors(spec)
            cat_info    = Legion::Extensions::Helpers::Segments.categorize_gem(spec.name, categories: categories, lists: cat_lists)

            {
              name:            short_name,
              version:         spec.version.to_s,
              status:          status,
              gem_dir:         spec.gem_dir,
              extension_class: extension_class,
              runners:         runner_info,
              actors:          actor_info,
              dependencies:    spec.runtime_dependencies.map(&:to_s),
              category:        cat_info[:category].to_s,
              tier:            cat_info[:tier]
            }
          end
          result.sort_by { |l| [l[:tier], l[:name]] }
        end

        def resolve_categories
          raw = Legion::Settings.dig(:extensions, :categories)
          raw.nil? || raw.empty? ? DEFAULT_CATEGORIES : raw
        end

        def resolve_cat_lists
          {
            core: Array(Legion::Settings.dig(:extensions, :core)),
            ai:   Array(Legion::Settings.dig(:extensions, :ai)),
            gaia: Array(Legion::Settings.dig(:extensions, :gaia))
          }
        end

        def find_lex(name)
          name = name.sub(/^lex-/, '')
          discover_all.find { |l| l[:name] == name }
        end

        def extract_runners(spec)
          runner_dir = File.join(spec.gem_dir, 'lib', 'legion', 'extensions',
                                 Legion::Extensions::Helpers::Segments.derive_segments(spec.name).join('/'), 'runners')
          return [] unless Dir.exist?(runner_dir)

          Dir.glob("#{runner_dir}/*.rb").map { |f| File.basename(f, '.rb') }
        rescue StandardError => e
          Legion::Logging.warn("LexCommand#extract_runners failed for #{spec.name}: #{e.message}") if defined?(Legion::Logging)
          []
        end

        def extract_actors(spec)
          actor_dir = File.join(spec.gem_dir, 'lib', 'legion', 'extensions',
                                Legion::Extensions::Helpers::Segments.derive_segments(spec.name).join('/'), 'actors')
          return [] unless Dir.exist?(actor_dir)

          Dir.glob("#{actor_dir}/*.rb").map do |f|
            basename = File.basename(f, '.rb')
            { name: basename, type: guess_actor_type(f) }
          end
        rescue StandardError => e
          Legion::Logging.warn("LexCommand#extract_actors failed for #{spec.name}: #{e.message}") if defined?(Legion::Logging)
          []
        end

        def guess_actor_type(file_path)
          content = File.read(file_path, encoding: 'utf-8')
          if content.include?('Subscription')
            'subscription'
          elsif content.include?('Every')
            'interval'
          elsif content.include?('Poll')
            'poll'
          elsif content.include?('Once')
            'once'
          elsif content.include?('Loop')
            'loop'
          else
            'unknown'
          end
        rescue StandardError => e
          Legion::Logging.debug("LexCommand#guess_actor_type failed for #{file_path}: #{e.message}") if defined?(Legion::Logging)
          'unknown'
        end

        def with_data
          Connection.ensure_data
          yield
        rescue CLI::Error => e
          formatter.error(e.message)
          raise SystemExit, 1
        end
      end
    end

    # Thin generator class that wraps the template logic
    class LexGenerator
      def initialize(name, vars, options, gem_name: nil, template: 'basic')
        @name      = name
        @vars      = vars
        @options   = options
        @gem_name  = gem_name || "lex-#{name}"
        @target    = @gem_name
        @template  = template || 'basic'
      end

      def generate(out)
        create_structure(out)
        apply_template_overlay(out) unless @template == 'basic'
        init_git(out) if @options[:git_init]
        run_bundle(out) if @options[:bundle_install]
      end

      private

      attr_reader :gem_name

      def target_dir
        @target
      end

      def namespace_segments
        @namespace_segments ||= Legion::Extensions::Helpers::Segments.derive_namespace(@gem_name)
      end

      def const_path
        @const_path ||= Legion::Extensions::Helpers::Segments.derive_const_path(@gem_name)
      end

      def require_path
        @require_path ||= Legion::Extensions::Helpers::Segments.derive_require_path(@gem_name)
      end

      def extension_dirs
        base = "#{@target}/lib/legion/extensions"
        segs = Legion::Extensions::Helpers::Segments.derive_segments(@gem_name)
        dirs = [
          @target,
          "#{@target}/lib",
          "#{@target}/lib/legion",
          base
        ]
        segs.each_with_index do |_, i|
          dirs << "#{base}/#{segs[0..i].join('/')}"
        end
        dirs += [
          "#{base}/#{segs.join('/')}/runners",
          "#{base}/#{segs.join('/')}/actors",
          "#{base}/#{segs.join('/')}/tools",
          "#{@target}/spec",
          "#{@target}/spec/legion"
        ]
        dirs
      end

      def module_open_lines
        indent = '  '
        lines = ["module Legion\n", "#{indent}module Extensions\n"]
        namespace_segments.each_with_index do |seg, i|
          lines << "#{indent * (i + 2)}module #{seg}\n"
        end
        lines
      end

      def module_close_lines
        depth = namespace_segments.length + 2
        (1..depth).map { |i| "#{'  ' * (depth - i)}end\n" }
      end

      def nested_module_wrap(inner_lines)
        opens  = module_open_lines
        closes = module_close_lines
        (opens + inner_lines + closes).join
      end

      def create_structure(out)
        dirs = extension_dirs
        dirs << "#{@target}/.github/workflows" if @options[:github_ci]

        dirs.each { |d| FileUtils.mkdir_p(d) }

        ext_base = "lib/legion/extensions/#{Legion::Extensions::Helpers::Segments.derive_segments(@gem_name).join('/')}"
        FileUtils.touch("#{@target}/#{ext_base}/tools/.gitkeep")

        entry_file = "lib/legion/extensions/#{require_path.split('legion/extensions/').last}"

        write_template("#{@target}/#{@target}.gemspec", gemspec_content)
        write_template("#{@target}/Gemfile", gemfile_content)
        write_template("#{@target}/.gitignore", gitignore_content)
        write_template("#{@target}/.rubocop.yml", rubocop_content)
        write_template("#{@target}/LICENSE", license_content)
        write_template("#{@target}/README.md", readme_content)
        write_template("#{@target}/lib/#{entry_file}.rb", extension_entry_content)
        write_template("#{@target}/#{ext_base}/version.rb", version_content)
        write_template("#{@target}/#{ext_base}/client.rb", client_content)

        if @options[:rspec]
          spec_relative = Legion::Extensions::Helpers::Segments.derive_segments(@gem_name).join('/')
          FileUtils.mkdir_p("#{@target}/spec/legion/extensions/#{File.dirname(spec_relative)}")
          write_template("#{@target}/spec/spec_helper.rb", spec_helper_content)
          write_template("#{@target}/spec/legion/extensions/#{spec_relative}_spec.rb", spec_content)
        end

        if @options[:github_ci]
          write_template("#{@target}/.github/workflows/rspec.yml", github_rspec_content)
          write_template("#{@target}/.github/workflows/rubocop.yml", github_rubocop_content)
        end

        out.success('Files generated')
      end

      def write_template(path, content)
        File.write(path, content)
      end

      def apply_template_overlay(out)
        segs       = Legion::Extensions::Helpers::Segments.derive_segments(@gem_name)
        lex_class  = segs.map(&:capitalize).join('::')
        lex_name   = @name
        name_class = @name.split(/[_-]/).map(&:capitalize).join
        gem_name   = @gem_name

        vars = { lex_class: lex_class, lex_name: lex_name, name_class: name_class, gem_name: gem_name }
        overlay = LexTemplates::TemplateOverlay.new(@template, @target, vars)
        overlay.apply(out)
      end

      def init_git(out)
        Dir.chdir(@target) do
          system('git init -q')
          system('git add .')
          system("git commit -q -m 'initial commit'")
        end
        out.success('Git initialized')
      end

      def run_bundle(out)
        Dir.chdir(@target) do
          system('bundle install --quiet')
        end
        out.success('Bundle installed')
      end

      def gemspec_content
        <<~RUBY
          # frozen_string_literal: true

          require_relative 'lib/#{require_path}/version'

          Gem::Specification.new do |spec|
            spec.name          = '#{@gem_name}'
            spec.version       = #{const_path}::VERSION
            spec.authors       = ['Esity']
            spec.email         = ['matthewdiverson@gmail.com']
            spec.summary       = 'A LegionIO Extension for #{namespace_segments.last}'
            spec.description   = 'A LegionIO Extension (LEX) for #{namespace_segments.last}'
            spec.homepage      = 'https://github.com/LegionIO/#{@gem_name}'
            spec.license       = 'MIT'
            spec.required_ruby_version = '>= 3.4'

            spec.metadata = {
              'homepage_uri'          => spec.homepage,
              'source_code_uri'       => spec.homepage,
              'rubygems_mfa_required' => 'true'
            }

            spec.files = Dir['lib/**/*', 'LICENSE', 'README.md']
            spec.require_paths = ['lib']

            spec.add_dependency 'legionio', '>= 1.2'
          end
        RUBY
      end

      def gemfile_content
        <<~RUBY
          # frozen_string_literal: true

          source 'https://rubygems.org'
          gemspec

          group :development, :test do
            gem 'rspec', '~> 3.12'
            gem 'rubocop', '~> 1.50'
            gem 'rubocop-rspec', '~> 2.20'
          end
        RUBY
      end

      def gitignore_content
        <<~TEXT
          /.bundle/
          /.yardoc
          /_yardoc/
          /coverage/
          /doc/
          /pkg/
          /spec/reports/
          /tmp/
          *.gem
          Gemfile.lock
        TEXT
      end

      def rubocop_content
        <<~YAML
          inherit_gem:
            rubocop: config/default.yml

          AllCops:
            NewCops: enable
            TargetRubyVersion: 3.4
        YAML
      end

      def license_content
        <<~TEXT
          MIT License

          Copyright (c) #{Time.now.year} LegionIO

          Permission is hereby granted, free of charge, to any person obtaining a copy
          of this software and associated documentation files (the "Software"), to deal
          in the Software without restriction, including without limitation the rights
          to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
          copies of the Software, and to permit persons to whom the Software is
          furnished to do so, subject to the following conditions:

          The above copyright notice and this permission notice shall be included in all
          copies or substantial portions of the Software.

          THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
          IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
          FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
          AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
          LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
          OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
          SOFTWARE.
        TEXT
      end

      def readme_content
        <<~MD
          # #{@gem_name}

          A [LegionIO](https://github.com/LegionIO) extension for #{namespace_segments.last}.

          ## Installation

          ```ruby
          gem '#{@gem_name}'
          ```

          ## Usage

          This extension is auto-discovered by LegionIO when installed.

          ## Development

          ```bash
          bundle install
          bundle exec rspec
          bundle exec rubocop
          ```

          ## License

          MIT
        MD
      end

      def extension_entry_content
        segs     = Legion::Extensions::Helpers::Segments.derive_segments(@gem_name)
        last_seg = segs.last
        inner    = ["  require_relative '#{last_seg}/version'\n",
                    "  require_relative '#{last_seg}/client'\n",
                    "\n"]
        "# frozen_string_literal: true\n\n#{nested_module_wrap(inner)}"
      end

      def version_content
        depth  = namespace_segments.length + 2
        inner  = ["#{'  ' * depth}VERSION = '0.1.0'\n"]
        "# frozen_string_literal: true\n\n#{nested_module_wrap(inner)}"
      end

      def client_content
        depth = namespace_segments.length + 2
        pad   = '  ' * depth
        inner = [
          "#{pad}class Client\n",
          "#{pad}  attr_reader :opts\n",
          "\n",
          "#{pad}  def initialize(**kwargs)\n",
          "#{pad}    @opts = kwargs\n",
          "#{pad}  end\n",
          "\n",
          "#{pad}  def connection(**override)\n",
          "#{pad}    Helpers::Client.connection(**@opts, **override)\n",
          "#{pad}  end\n",
          "#{pad}end\n"
        ]
        "# frozen_string_literal: true\n\n#{nested_module_wrap(inner)}"
      end

      def spec_helper_content
        <<~RUBY
          # frozen_string_literal: true

          require '#{require_path}'

          RSpec.configure do |config|
            config.expect_with :rspec do |expectations|
              expectations.include_chain_clauses_in_custom_matcher_descriptions = true
            end
          end
        RUBY
      end

      def spec_content
        <<~RUBY
          # frozen_string_literal: true

          RSpec.describe #{const_path} do
            it 'has a version number' do
              expect(#{const_path}::VERSION).not_to be_nil
            end
          end
        RUBY
      end

      def github_rspec_content
        <<~YAML
          name: RSpec
          on: [push, pull_request]
          jobs:
            test:
              runs-on: ubuntu-latest
              steps:
                - uses: actions/checkout@v4
                - uses: ruby/setup-ruby@v1
                  with:
                    ruby-version: '3.4'
                    bundler-cache: true
                - run: bundle exec rspec
        YAML
      end

      def github_rubocop_content
        <<~YAML
          name: RuboCop
          on: [push, pull_request]
          jobs:
            lint:
              runs-on: ubuntu-latest
              steps:
                - uses: actions/checkout@v4
                - uses: ruby/setup-ruby@v1
                  with:
                    ruby-version: '3.4'
                    bundler-cache: true
                - run: bundle exec rubocop
        YAML
      end
    end
  end
end
