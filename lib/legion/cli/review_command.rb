# frozen_string_literal: true

require 'thor'
require 'legion/cli/output'
require 'legion/cli/connection'
require 'legion/cli/error'
require 'open3'

module Legion
  module CLI
    class Review < Thor
      def self.exit_on_failure?
        true
      end

      class_option :json,       type: :boolean, default: false, desc: 'Output as JSON'
      class_option :no_color,   type: :boolean, default: false, desc: 'Disable color output'
      class_option :verbose,    type: :boolean, default: false, aliases: ['-V'], desc: 'Verbose logging'
      class_option :config_dir, type: :string,  desc: 'Config directory path'
      class_option :model,      type: :string,  aliases: ['-m'], desc: 'Model ID'
      class_option :provider,   type: :string,  desc: 'LLM provider'

      desc 'diff', 'Review code changes via LLM'
      option :staged, type: :boolean, default: false, desc: 'Review only staged changes'
      option :base,   type: :string,  desc: 'Base branch for comparison (e.g., main)'
      option :pr,     type: :numeric, desc: 'Review a GitHub PR by number'
      option :fix,    type: :boolean, default: false, desc: 'Generate and apply fixes'
      option :yes,    type: :boolean, default: false, aliases: ['-y'], desc: 'Auto-approve fixes'
      option :token,  type: :string,  desc: 'GitHub token (for --pr mode)'
      def diff
        out = formatter
        setup_connection

        diff_text, context = fetch_diff(out)
        if diff_text.strip.empty?
          out.error('No changes to review.')
          raise SystemExit, 1
        end

        out.header('Reviewing code changes...')
        review = run_review(diff_text, context)

        if options[:json]
          out.json(review)
          return
        end

        display_review(out, review)

        apply_fixes(out, review[:fixes]) if options[:fix] && review[:fixes]&.any?

        exit(1) if review[:findings].any? { |f| f[:severity] == 'critical' }
      rescue CLI::Error => e
        out.error(e.message)
        raise SystemExit, 1
      ensure
        Connection.shutdown if Connection.respond_to?(:shutdown)
      end
      default_task :diff

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

        def fetch_diff(out)
          if options[:pr]
            fetch_pr_diff(out)
          elsif options[:base]
            fetch_branch_diff
          elsif options[:staged]
            fetch_staged_diff
          else
            fetch_working_diff
          end
        end

        def fetch_staged_diff
          diff = git_capture('git', 'diff', '--staged')
          stat = git_capture('git', 'diff', '--staged', '--stat')
          [diff, { mode: 'staged', stat: stat }]
        end

        def fetch_working_diff
          diff = git_capture('git', 'diff')
          stat = git_capture('git', 'diff', '--stat')
          [diff, { mode: 'working', stat: stat }]
        end

        def fetch_branch_diff
          base = options[:base]
          diff = git_capture('git', 'diff', "#{base}...HEAD")
          stat = git_capture('git', 'diff', "#{base}...HEAD", '--stat')
          log = git_capture('git', 'log', "#{base}..HEAD", '--oneline', '--no-decorate')
          [diff, { mode: 'branch', base: base, stat: stat, log: log }]
        end

        def fetch_pr_diff(out)
          owner, repo = detect_remote
          token = resolve_token
          out.header("Fetching PR ##{options[:pr]}...")

          require 'legion/extensions/github/client'
          client = Legion::Extensions::Github::Client.new(token: token)
          pr = client.get_pull_request(owner: owner, repo: repo, pull_number: options[:pr])
          files = client.list_pull_request_files(owner: owner, repo: repo, pull_number: options[:pr])

          pr_data = pr[:result]
          patches = files[:result].map { |f| "--- a/#{f['filename']}\n+++ b/#{f['filename']}\n#{f['patch']}" }
          diff = patches.join("\n\n")

          context = {
            mode:  'pr',
            pr:    options[:pr],
            title: pr_data['title'],
            body:  pr_data['body'],
            stat:  files[:result].map { |f| "#{f['filename']} (+#{f['additions']}/-#{f['deletions']})" }.join("\n")
          }

          [diff, context]
        end

        def run_review(diff_text, context)
          opts = {}
          opts[:model]    = options[:model] if options[:model]
          opts[:provider] = options[:provider]&.to_sym if options[:provider]

          chat = Legion::LLM.chat(**opts, caller: { source: 'cli', command: 'review' })
          prompt = build_review_prompt(diff_text, context)
          response = chat.ask(prompt)
          parse_review(response.content, context)
        end

        def build_review_prompt(diff_text, context)
          fix_instruction = options[:fix] ? fix_prompt_section : ''
          context_section = build_context_section(context)

          <<~PROMPT
            You are a senior code reviewer. Review the following code changes and provide structured feedback.

            #{context_section}

            For each finding, output exactly this format (one per finding):
            [SEVERITY] file:line - description

            Severity levels:
            - CRITICAL: bugs, security vulnerabilities, data loss risks
            - WARNING: logic errors, performance issues, bad practices
            - SUGGESTION: style improvements, refactoring opportunities
            - NOTE: observations, questions, documentation needs

            After all findings, output a single line:
            SUMMARY: one-sentence overall assessment
            #{fix_instruction}

            Diff:
            #{diff_text[0, 12_000]}
          PROMPT
        end

        def fix_prompt_section
          <<~FIX

            Additionally, for each CRITICAL and WARNING finding, output a fix in unified diff format:
            FIX file:line
            ```diff
            (unified diff patch)
            ```
          FIX
        end

        def build_context_section(context)
          case context[:mode]
          when 'pr'
            "PR ##{context[:pr]}: #{context[:title]}\n#{context[:body]}\n\nChanged files:\n#{context[:stat]}"
          when 'branch'
            "Branch diff against #{context[:base]}\nCommits:\n#{context[:log]}\n\nDiffstat:\n#{context[:stat]}"
          else
            "#{context[:mode].capitalize} changes\n\nDiffstat:\n#{context[:stat]}"
          end
        end

        def parse_review(content, context)
          findings = []
          fixes = []
          summary = nil

          content.each_line do |line|
            stripped = line.strip
            case stripped
            when /^\[(CRITICAL|WARNING|SUGGESTION|NOTE)\]\s+(.+)/
              findings << { severity: Regexp.last_match(1).downcase, detail: Regexp.last_match(2) }
            when /^SUMMARY:\s+(.+)/
              summary = Regexp.last_match(1)
            when /^FIX\s+(.+)/
              fixes << { target: Regexp.last_match(1) }
            end
          end

          # Extract fix patches from code blocks
          content.scan(/FIX\s+(.+?)\n```diff\n(.*?)```/m).each_with_index do |(target, patch), i|
            fixes[i] = { target: target.strip, patch: patch } if fixes[i]
          end

          {
            findings: findings,
            fixes:    fixes.select { |f| f[:patch] },
            summary:  summary || 'No summary provided.',
            mode:     context[:mode]
          }
        end

        def display_review(out, review)
          puts

          severity_colors = {
            'critical'   => :red,
            'warning'    => :yellow,
            'suggestion' => :cyan,
            'note'       => :white
          }

          review[:findings].each do |finding|
            color = severity_colors[finding[:severity]] || :white
            label = finding[:severity].upcase.ljust(10)
            puts "  #{out.colorize(label, color)} #{finding[:detail]}"
          end

          puts out.colorize('  No issues found.', :green) if review[:findings].empty?

          puts
          counts = review[:findings].group_by { |f| f[:severity] }.transform_values(&:count)
          parts = %w[critical warning suggestion note].filter_map do |sev|
            "#{counts[sev]} #{sev}" if counts[sev]
          end
          puts "  #{parts.any? ? parts.join(', ') : 'Clean'}"
          puts "  #{out.dim(review[:summary])}"
          puts
        end

        def apply_fixes(out, fixes)
          out.header("#{fixes.length} fix(es) available")

          fixes.each do |fix|
            puts out.dim("  #{fix[:target]}")
          end
          puts

          unless options[:yes]
            $stderr.print "#{out.colorize('Apply fixes?', :yellow)} [Y/n] "
            response = $stdin.gets&.strip&.downcase
            return out.warn('Fixes skipped.') if %w[n no].include?(response)
          end

          fixes.each do |fix|
            apply_patch(fix[:patch], out)
          end
        end

        def apply_patch(patch, out)
          require 'tempfile'
          file = Tempfile.new(['legion-fix', '.patch'])
          file.write(patch)
          file.close

          _stdout, stderr, status = Open3.capture3('git', 'apply', '--check', file.path)
          if status.success?
            Open3.capture3('git', 'apply', file.path)
            out.success('Patch applied.')
          else
            out.warn("Patch skipped (would not apply cleanly): #{stderr.strip}")
          end
        ensure
          file&.unlink
        end

        def git_capture(*cmd)
          stdout, _stderr, _status = Open3.capture3(*cmd)
          stdout.strip
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
      end
    end
  end
end
