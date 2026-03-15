# frozen_string_literal: true

require 'thor'
require 'legion/cli/output'
require 'legion/cli/connection'
require 'legion/cli/error'
require 'open3'

module Legion
  module CLI
    class Commit < Thor
      def self.exit_on_failure?
        true
      end

      class_option :json,       type: :boolean, default: false, desc: 'Output as JSON'
      class_option :no_color,   type: :boolean, default: false, desc: 'Disable color output'
      class_option :verbose,    type: :boolean, default: false, aliases: ['-V'], desc: 'Verbose logging'
      class_option :config_dir, type: :string,  desc: 'Config directory path'
      class_option :model,      type: :string,  aliases: ['-m'], desc: 'Model ID'
      class_option :provider,   type: :string,  desc: 'LLM provider'

      desc 'generate', 'Generate a commit message from staged changes'
      option :all,   type: :boolean, default: false, aliases: ['-a'], desc: 'Stage all modified files first'
      option :amend, type: :boolean, default: false, desc: 'Amend the last commit'
      option :yes,   type: :boolean, default: false, aliases: ['-y'], desc: 'Auto-approve (skip confirmation)'
      def generate
        out = formatter

        stage_all if options[:all]
        diff = staged_diff
        if diff.strip.empty?
          out.error('Nothing staged to commit. Use -a to stage all changes, or git add files first.')
          raise SystemExit, 1
        end

        stat = staged_stat
        log = recent_commits
        setup_connection

        out.header('Generating commit message...')
        message = generate_message(diff, stat, log)

        if options[:json]
          out.json({ message: message, stat: stat })
          return
        end

        puts
        puts out.colorize(message, :green)
        puts
        puts out.dim(stat)
        puts

        unless options[:yes]
          $stderr.print "#{out.colorize('Commit with this message?', :yellow)} [Y/n/e(dit)] "
          response = $stdin.gets&.strip&.downcase
          case response
          when 'n', 'no'
            out.warn('Commit aborted.')
            return
          when 'e', 'edit'
            message = edit_message(message)
            return out.warn('Commit aborted (empty message).') if message.strip.empty?
          end
        end

        run_commit(message, amend: options[:amend])
        out.success(options[:amend] ? 'Commit amended.' : 'Committed.')
      rescue CLI::Error => e
        out.error(e.message)
        raise SystemExit, 1
      ensure
        Connection.shutdown if Connection.respond_to?(:shutdown)
      end
      default_task :generate

      no_commands do
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

        def stage_all
          stdout, stderr, status = Open3.capture3('git', 'add', '-u')
          return if status.success?

          raise CLI::Error, "git add -u failed: #{stderr.strip.empty? ? stdout : stderr}"
        end

        def staged_diff
          stdout, _stderr, _status = Open3.capture3('git', 'diff', '--staged')
          stdout
        end

        def staged_stat
          stdout, _stderr, _status = Open3.capture3('git', 'diff', '--staged', '--stat')
          stdout.strip
        end

        def recent_commits
          stdout, _stderr, _status = Open3.capture3('git', 'log', '--oneline', '-10', '--no-decorate')
          stdout.strip
        end

        def generate_message(diff, stat, log)
          opts = {}
          opts[:model]    = options[:model] if options[:model]
          opts[:provider] = options[:provider]&.to_sym if options[:provider]

          chat = Legion::LLM.chat(**opts)
          prompt = build_prompt(diff, stat, log)
          response = chat.ask(prompt)
          response.content.strip
        end

        def build_prompt(diff, stat, log)
          <<~PROMPT
            Generate a concise git commit message for the following staged changes.

            Rules:
            - Use lowercase, imperative mood (e.g., "add feature", "fix bug", not "Added" or "Fixes")
            - First line: summary under 72 characters
            - If the changes are complex, add a blank line then bullet points explaining key changes
            - No emojis
            - Match the style of recent commits shown below
            - Output ONLY the commit message, nothing else

            Recent commits (for style reference):
            #{log}

            Diffstat:
            #{stat}

            Full diff:
            #{diff[0, 8000]}
          PROMPT
        end

        def edit_message(message)
          require 'tempfile'
          file = Tempfile.new(['legion-commit', '.txt'])
          file.write(message)
          file.close

          editor = ENV.fetch('EDITOR', ENV.fetch('VISUAL', 'vi'))
          system(editor, file.path)

          result = File.read(file.path)
          file.unlink
          result.strip
        end

        def run_commit(message, amend: false)
          cmd = %w[git commit]
          cmd << '--amend' if amend
          cmd.push('-m', message)

          _stdout, stderr, status = Open3.capture3(*cmd)
          return if status.success?

          raise CLI::Error, "git commit failed: #{stderr.strip}"
        end
      end
    end
  end
end
