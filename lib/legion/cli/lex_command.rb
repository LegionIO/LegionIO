# frozen_string_literal: true

require 'fileutils'

module Legion
  module CLI
    class Lex < Thor
      def self.exit_on_failure?
        true
      end

      class_option :json, type: :boolean, default: false, desc: 'Output as JSON'
      class_option :no_color, type: :boolean, default: false, desc: 'Disable color output'

      desc 'list', 'List all installed extensions'
      option :all, type: :boolean, default: false, aliases: ['-a'], desc: 'Include disabled extensions'
      def list
        out = formatter
        lexs = discover_all

        rows = if options[:all]
                 lexs
               else
                 lexs.reject { |l| l[:status] == 'disabled' }
               end

        table_rows = rows.map do |l|
          [
            l[:name],
            l[:version],
            out.status(l[:status]),
            l[:runners].to_s,
            l[:actors].to_s
          ]
        end

        out.table(
          %w[name version status runners actors],
          table_rows
        )
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
        out.detail(
          name:    lex[:name],
          version: lex[:version],
          status:  lex[:status],
          gem_dir: lex[:gem_dir],
          class:   lex[:extension_class]
        )

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
      option :rspec, type: :boolean, default: true, desc: 'Include RSpec setup'
      option :github_ci, type: :boolean, default: true, desc: 'Include GitHub Actions CI'
      option :git_init, type: :boolean, default: true, desc: 'Initialize git repository'
      option :bundle_install, type: :boolean, default: true, desc: 'Run bundle install'
      def create(name)
        out = formatter
        target_dir = "lex-#{name}"

        if Dir.exist?(target_dir)
          out.error("Directory #{target_dir} already exists")
          raise SystemExit, 1
        end

        if Dir.pwd.include?('lex-')
          out.error('Already inside a LEX directory. Move to a parent directory first.')
          raise SystemExit, 1
        end

        out.success("Creating lex-#{name}...")

        vars = { filename: target_dir, class_name: name.split('_').map(&:capitalize).join, lex: name }

        generator = LexGenerator.new(name, vars, options)
        generator.generate(out)

        out.spacer
        out.success("Extension lex-#{name} created in ./#{target_dir}")
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

      no_commands do # rubocop:disable Metrics/BlockLength
        def formatter
          @formatter ||= Output::Formatter.new(
            json:  options[:json],
            color: !options[:no_color]
          )
        end

        def discover_all
          installed = Gem::Specification.select { |s| s.name.start_with?('lex-') }

          # Load settings to check enabled/disabled state
          begin
            Connection.ensure_settings
            ext_settings = Legion::Settings[:extensions] || {}
          rescue StandardError
            ext_settings = {}
          end

          result = installed.map do |spec|
            short_name = spec.name.sub('lex-', '')
            class_name = short_name.split('_').map(&:capitalize).join
            extension_class = "Legion::Extensions::#{class_name}"

            setting = ext_settings[short_name.to_sym] || {}
            status = if setting[:enabled] == false
                       'disabled'
                     else
                       'installed'
                     end

            runner_info = extract_runners(spec)
            actor_info = extract_actors(spec)

            {
              name:            short_name,
              version:         spec.version.to_s,
              status:          status,
              gem_dir:         spec.gem_dir,
              extension_class: extension_class,
              runners:         runner_info,
              actors:          actor_info,
              dependencies:    spec.runtime_dependencies.map(&:to_s)
            }
          end
          result.sort_by { |l| l[:name] }
        end

        def find_lex(name)
          name = name.sub(/^lex-/, '')
          discover_all.find { |l| l[:name] == name }
        end

        def extract_runners(spec)
          runner_dir = File.join(spec.gem_dir, 'lib', 'legion', 'extensions', spec.name.sub('lex-', ''), 'runners')
          return [] unless Dir.exist?(runner_dir)

          Dir.glob("#{runner_dir}/*.rb").map { |f| File.basename(f, '.rb') }
        rescue StandardError
          []
        end

        def extract_actors(spec)
          actor_dir = File.join(spec.gem_dir, 'lib', 'legion', 'extensions', spec.name.sub('lex-', ''), 'actors')
          return [] unless Dir.exist?(actor_dir)

          Dir.glob("#{actor_dir}/*.rb").map do |f|
            basename = File.basename(f, '.rb')
            { name: basename, type: guess_actor_type(f) }
          end
        rescue StandardError
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
        rescue StandardError
          'unknown'
        end
      end
    end

    # Thin generator class that wraps the template logic
    class LexGenerator
      def initialize(name, vars, options)
        @name = name
        @vars = vars
        @options = options
        @target = "lex-#{name}"
      end

      def generate(out)
        create_structure(out)
        init_git(out) if @options[:git_init]
        run_bundle(out) if @options[:bundle_install]
      end

      private

      def create_structure(out)
        dirs = [
          @target,
          "#{@target}/lib",
          "#{@target}/lib/legion",
          "#{@target}/lib/legion/extensions",
          "#{@target}/lib/legion/extensions/#{@name}",
          "#{@target}/lib/legion/extensions/#{@name}/runners",
          "#{@target}/lib/legion/extensions/#{@name}/actors",
          "#{@target}/spec",
          "#{@target}/spec/legion"
        ]

        dirs << "#{@target}/.github/workflows" if @options[:github_ci]

        dirs.each { |d| FileUtils.mkdir_p(d) }

        write_template("#{@target}/#{@target}.gemspec", gemspec_content)
        write_template("#{@target}/Gemfile", gemfile_content)
        write_template("#{@target}/.gitignore", gitignore_content)
        write_template("#{@target}/.rubocop.yml", rubocop_content)
        write_template("#{@target}/LICENSE", license_content)
        write_template("#{@target}/README.md", readme_content)
        write_template("#{@target}/lib/legion/extensions/#{@name}.rb", extension_entry_content)
        write_template("#{@target}/lib/legion/extensions/#{@name}/version.rb", version_content)

        if @options[:rspec]
          write_template("#{@target}/spec/spec_helper.rb", spec_helper_content)
          write_template("#{@target}/spec/legion/#{@name}_spec.rb", spec_content)
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

          require_relative 'lib/legion/extensions/#{@name}/version'

          Gem::Specification.new do |spec|
            spec.name          = '#{@target}'
            spec.version       = Legion::Extensions::#{@vars[:class_name]}::VERSION
            spec.authors       = ['Esity']
            spec.email         = ['matthewdiverson@gmail.com']
            spec.summary       = 'A LegionIO Extension for #{@vars[:class_name]}'
            spec.description   = 'A LegionIO Extension (LEX) for #{@vars[:class_name]}'
            spec.homepage      = 'https://github.com/LegionIO/#{@target}'
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
          # lex-#{@name}

          A [LegionIO](https://github.com/LegionIO) extension for #{@vars[:class_name]}.

          ## Installation

          ```ruby
          gem 'lex-#{@name}'
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
        <<~RUBY
          # frozen_string_literal: true

          require_relative '#{@name}/version'

          module Legion
            module Extensions
              module #{@vars[:class_name]}
              end
            end
          end
        RUBY
      end

      def version_content
        <<~RUBY
          # frozen_string_literal: true

          module Legion
            module Extensions
              module #{@vars[:class_name]}
                VERSION = '0.1.0'
              end
            end
          end
        RUBY
      end

      def spec_helper_content
        <<~RUBY
          # frozen_string_literal: true

          require 'legion/extensions/#{@name}'

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

          RSpec.describe Legion::Extensions::#{@vars[:class_name]} do
            it 'has a version number' do
              expect(Legion::Extensions::#{@vars[:class_name]}::VERSION).not_to be_nil
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
