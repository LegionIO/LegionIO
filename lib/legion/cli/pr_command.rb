# frozen_string_literal: true

require 'thor'
require 'legion/cli/output'
require 'legion/cli/connection'
require 'legion/cli/error'
require 'open3'

module Legion
  module CLI
    class Pr < Thor
      def self.exit_on_failure?
        true
      end

      class_option :json,       type: :boolean, default: false, desc: 'Output as JSON'
      class_option :no_color,   type: :boolean, default: false, desc: 'Disable color output'
      class_option :verbose,    type: :boolean, default: false, aliases: ['-V'], desc: 'Verbose logging'
      class_option :config_dir, type: :string,  desc: 'Config directory path'
      class_option :model,      type: :string,  aliases: ['-m'], desc: 'Model ID'
      class_option :provider,   type: :string,  desc: 'LLM provider'

      desc 'create', 'Create a pull request with AI-generated title and description'
      option :base,  type: :string, default: 'main', aliases: ['-b'], desc: 'Base branch'
      option :draft, type: :boolean, default: false, desc: 'Create as draft PR'
      option :yes,   type: :boolean, default: false, aliases: ['-y'], desc: 'Auto-approve (skip confirmation)'
      option :push,  type: :boolean, default: true, desc: 'Push branch before creating PR'
      option :token, type: :string, desc: 'GitHub token (default: GITHUB_TOKEN env var)'
      def create
        out = formatter
        validate_branch!(out)

        diff, stat, log = gather_changes(options[:base])
        validate_diff!(diff, out)
        setup_connection

        out.header('Generating PR title and description...')
        title, body = generate_pr_content(diff, stat, log, current_branch)

        return out.json(pr_json(title, body)) if options[:json]

        display_pr_preview(out, title, body)
        title, body = confirm_or_edit(out, title, body) unless options[:yes]
        return unless title

        push_branch(current_branch) if options[:push]
        pr_url = submit_pull_request(title, body)
        out.success("PR created: #{pr_url}")
      rescue CLI::Error => e
        out.error(e.message)
        raise SystemExit, 1
      ensure
        Connection.shutdown if Connection.respond_to?(:shutdown)
      end
      default_task :create

      no_commands do # rubocop:disable Metrics/BlockLength
        def formatter
          @formatter ||= Output::Formatter.new(
            json:  options[:json],
            color: !options[:no_color]
          )
        end

        def setup_connection
          Connection.config_dir = options[:config_dir] if options[:config_dir]
          Connection.log_level = options[:verbose] ? 'debug' : 'error'
          Connection.ensure_llm
        end

        def validate_branch!(out)
          return unless current_branch == options[:base]

          out.error("Already on #{options[:base]}. Switch to a feature branch first.")
          raise SystemExit, 1
        end

        def validate_diff!(diff, out)
          return unless diff.strip.empty?

          out.error("No changes between #{current_branch} and #{options[:base]}.")
          raise SystemExit, 1
        end

        def gather_changes(base)
          [branch_diff(base), branch_stat(base), branch_log(base)]
        end

        def display_pr_preview(out, title, body)
          puts
          puts out.colorize(title, :green)
          puts
          puts body
          puts
        end

        def confirm_or_edit(out, title, body)
          $stderr.print "#{out.colorize('Create PR with this content?', :yellow)} [Y/n/e(dit)] "
          response = $stdin.gets&.strip&.downcase
          case response
          when 'n', 'no'
            out.warn('PR creation aborted.')
            return [nil, nil]
          when 'e', 'edit'
            title, body = edit_pr_content(title, body)
            if title.strip.empty?
              out.warn('PR creation aborted (empty title).')
              return [nil, nil]
            end
          end
          [title, body]
        end

        def pr_json(title, body)
          { title: title, body: body, branch: current_branch, base: options[:base] }
        end

        def current_branch
          stdout, _stderr, _status = Open3.capture3('git', 'rev-parse', '--abbrev-ref', 'HEAD')
          stdout.strip
        end

        def branch_diff(base)
          stdout, _stderr, _status = Open3.capture3('git', 'diff', "#{base}...HEAD")
          stdout
        end

        def branch_stat(base)
          stdout, _stderr, _status = Open3.capture3('git', 'diff', "#{base}...HEAD", '--stat')
          stdout.strip
        end

        def branch_log(base)
          stdout, _stderr, _status = Open3.capture3('git', 'log', "#{base}..HEAD", '--oneline', '--no-decorate')
          stdout.strip
        end

        def push_branch(branch)
          _stdout, stderr, status = Open3.capture3('git', 'push', '-u', 'origin', branch)
          return if status.success?

          raise CLI::Error, "git push failed: #{stderr.strip}"
        end

        def detect_remote
          stdout, _stderr, _status = Open3.capture3('git', 'remote', 'get-url', 'origin')
          url = stdout.strip
          match = url.match(%r{[:/]([^/]+)/([^/.]+?)(?:\.git)?$})
          raise CLI::Error, "Cannot parse GitHub owner/repo from remote: #{url}" unless match

          [match[1], match[2]]
        end

        def resolve_token
          token = options[:token] || ENV.fetch('GITHUB_TOKEN', nil) || ENV.fetch('GH_TOKEN', nil)
          raise CLI::Error, 'No GitHub token found. Set GITHUB_TOKEN env var or pass --token.' unless token

          token
        end

        def generate_pr_content(diff, stat, log, branch)
          opts = {}
          opts[:model]    = options[:model] if options[:model]
          opts[:provider] = options[:provider]&.to_sym if options[:provider]

          chat = Legion::LLM.chat(**opts)
          prompt = build_prompt(diff, stat, log, branch)
          response = chat.ask(prompt)
          parse_pr_response(response.content)
        end

        def build_prompt(diff, stat, log, branch)
          <<~PROMPT
            Generate a pull request title and description for the following changes.

            Rules:
            - Title: concise, under 70 characters, describes the change
            - Description: use markdown with ## Summary section (2-4 bullet points) and ## Changes section
            - Be specific about what changed and why
            - Output format: first line is the title, then a blank line, then the description body
            - Output ONLY the title and description, nothing else

            Branch: #{branch}
            Commits:
            #{log}

            Diffstat:
            #{stat}

            Full diff (truncated):
            #{diff[0, 8000]}
          PROMPT
        end

        def parse_pr_response(content)
          lines = content.strip.lines
          title = lines.first&.strip || 'Update'
          body = lines.length > 2 ? lines[2..].join.strip : ''
          [title, body]
        end

        def edit_pr_content(title, body)
          require 'tempfile'
          file = Tempfile.new(['legion-pr', '.md'])
          file.write("#{title}\n\n#{body}")
          file.close

          editor = ENV.fetch('EDITOR', ENV.fetch('VISUAL', 'vi'))
          system(editor, file.path)

          content = File.read(file.path)
          file.unlink
          parse_pr_response(content)
        end

        def submit_pull_request(title, body)
          owner, repo = detect_remote
          token = resolve_token

          require 'legion/extensions/github/client'
          client = Legion::Extensions::Github::Client.new(token: token)
          result = client.create_pull_request(
            owner: owner, repo: repo, title: title,
            head: current_branch, base: options[:base],
            body: body, draft: options[:draft]
          )

          pr_data = result[:result]
          pr_data['html_url'] || pr_data['url'] || "#{owner}/#{repo}##{pr_data['number']}"
        end
      end
    end
  end
end
