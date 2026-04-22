# frozen_string_literal: true

require 'shellwords'
require_relative 'api_client'

module Legion
  module CLI
    class MonitorCommand < Thor
      def self.exit_on_failure?
        true
      end

      class_option :json,     type: :boolean, default: false, desc: 'Output as JSON'
      class_option :no_color, type: :boolean, default: false, desc: 'Disable color output'

      desc 'add PATH', 'Add a directory to corpus monitors'
      option :extensions, type: :string,  desc: 'Comma-separated file extensions to watch (e.g. md,rb)'
      option :label,      type: :string,  desc: 'Human-readable label for this monitor'
      def add(path)
        out = formatter
        exts = options[:extensions]&.split(',')&.map(&:strip)
        result = api_post('/api/knowledge/monitors', path: path, extensions: exts, label: options[:label])

        if options[:json]
          out.json(result)
        elsif result[:success]
          out.success("Monitor added: #{path}")
        else
          out.warn("Failed to add monitor: #{result[:error]}")
        end
      end

      desc 'list', 'List registered corpus monitors'
      def list
        out = formatter
        monitors = api_get('/api/knowledge/monitors')

        if options[:json]
          out.json(monitors)
        elsif monitors.nil? || monitors.empty?
          out.warn('No monitors registered')
        else
          out.header('Knowledge Monitors')
          monitors.each do |m|
            label = m[:label] ? " [#{m[:label]}]" : ''
            exts  = m[:extensions]&.join(', ')
            puts "  #{m[:path]}#{label}"
            puts "    Extensions: #{exts}" if exts && !exts.empty?
          end
        end
      end
      default_task :list

      desc 'remove IDENTIFIER', 'Remove a corpus monitor by path or label'
      def remove(identifier)
        out = formatter
        result = api_delete("/api/knowledge/monitors?identifier=#{URI.encode_www_form_component(identifier)}")

        if options[:json]
          out.json(result)
        elsif result[:success]
          out.success("Monitor removed: #{identifier}")
        else
          out.warn("Failed to remove monitor: #{result[:error]}")
        end
      end

      desc 'status', 'Show monitor status (counts)'
      def status
        out = formatter
        result = api_get('/api/knowledge/monitors/status')

        if options[:json]
          out.json(result)
        else
          out.header('Monitor Status')
          out.detail({
                       'Total monitors' => result[:total_monitors].to_s,
                       'Total files'    => result[:total_files].to_s
                     })
        end
      end

      no_commands do
        include ApiClient

        def formatter
          @formatter ||= Output::Formatter.new(json: options[:json], color: !options[:no_color])
        end
      end
    end

    class CaptureCommand < Thor
      def self.exit_on_failure?
        true
      end

      class_option :json,     type: :boolean, default: false, desc: 'Output as JSON'
      class_option :no_color, type: :boolean, default: false, desc: 'Disable color output'

      desc 'commit', 'Capture the last git commit as knowledge'
      def commit
        log_line = `git log -1 --format='%H %s' 2>/dev/null`.strip
        diff_stat = `git diff HEAD~1 --stat 2>/dev/null`.strip

        if log_line.empty?
          formatter.warn('No git commit found')
          return
        end

        sha, *subject_parts = log_line.split
        subject = subject_parts.join(' ')
        content = "Git commit: #{sha}\nSubject: #{subject}\n\nDiff stat:\n#{diff_stat}"
        tags    = %w[git commit knowledge-capture]

        result = api_post('/api/knowledge/ingest', content: content, tags: tags, source: "git:#{sha}")

        out = formatter
        if options[:json]
          out.json(result)
        elsif result[:success]
          out.success("Captured commit #{sha[0, 8]}: #{subject}")
        else
          out.warn("Capture failed: #{result[:error]}")
        end
      end

      desc 'session', 'Capture a session note from stdin'
      def session
        input = $stdin.gets(nil) if $stdin.ready? rescue nil # rubocop:disable Style/RescueModifier
        input = input.to_s.strip

        if input.empty?
          formatter.warn('No session input provided (pipe text to stdin)')
          return
        end

        repo = `git rev-parse --show-toplevel 2>/dev/null`.strip.split('/').last
        content = "Session note (#{::Time.now.strftime('%Y-%m-%d')}):\n\n#{input}"
        tags    = ['session', 'knowledge-capture', ::Time.now.strftime('%Y-%m-%d')]
        tags   << "repo:#{repo}" unless repo.empty?

        result = api_post('/api/knowledge/ingest',
                          content: content, tags: tags, source: "session:#{::Time.now.iso8601}")

        out = formatter
        if options[:json]
          out.json(result)
        elsif result[:success]
          out.success('Session captured')
        else
          out.warn("Capture failed: #{result[:error]}")
        end
      end

      desc 'transcript', 'Capture a Claude Code session transcript as knowledge'
      option :session_id, type: :string, desc: 'Session ID (defaults to CLAUDE_SESSION_ID env)'
      option :cwd,        type: :string, desc: 'Working directory (defaults to CLAUDE_CWD env)'
      option :max_chunks, type: :numeric, default: 50, desc: 'Max conversation turn chunks to ingest'
      def transcript
        session_id = options[:session_id] || ENV.fetch('CLAUDE_SESSION_ID', nil)
        cwd        = options[:cwd] || ENV.fetch('CLAUDE_CWD', nil) || ::Dir.pwd

        unless session_id
          formatter.warn('No session ID provided (set CLAUDE_SESSION_ID or --session-id)')
          return
        end

        jsonl_path = resolve_transcript_path(session_id, cwd)
        unless jsonl_path && ::File.exist?(jsonl_path)
          formatter.warn("Transcript not found: #{jsonl_path || 'could not resolve path'}")
          return
        end

        turns = extract_turns(jsonl_path)
        if turns.empty?
          formatter.warn('No conversation turns found in transcript')
          return
        end

        repo      = `git -C #{Shellwords.escape(cwd)} rev-parse --show-toplevel 2>/dev/null`.strip.split('/').last
        base_tags = ['claude-code', 'transcript', "session:#{session_id}", ::Time.now.strftime('%Y-%m-%d')]
        base_tags << "repo:#{repo}" unless repo.to_s.empty?

        ingested = 0
        turns.first(options[:max_chunks]).each_with_index do |turn, idx|
          content = format_turn(turn, idx + 1)
          next if content.strip.empty?

          result = api_post('/api/knowledge/ingest',
                            content: content,
                            tags:    base_tags + ["turn:#{idx + 1}"],
                            source:  "claude-code:#{session_id}:turn-#{idx + 1}")
          ingested += 1 if result[:success]
        end

        out = formatter
        if options[:json]
          out.json(success: true, session_id: session_id, turns: turns.size, ingested: ingested)
        else
          out.success("Captured #{ingested}/#{[turns.size, options[:max_chunks]].min} turns from session #{session_id[0, 8]}")
        end
      end

      no_commands do
        include ApiClient

        def formatter
          @formatter ||= Output::Formatter.new(json: options[:json], color: !options[:no_color])
        end

        def resolve_transcript_path(session_id, cwd)
          project_dir = cwd.gsub('/', '-')
          ::File.expand_path("~/.claude/projects/#{project_dir}/#{session_id}.jsonl")
        end

        def extract_turns(path)
          turns = []
          current_turn = nil

          ::File.foreach(path) do |line|
            entry = ::JSON.parse(line, symbolize_names: true)
            type  = entry[:type]

            case type
            when 'user'
              turns << current_turn if current_turn
              current_turn = { user: extract_message_text(entry), assistant: +'', timestamp: entry[:timestamp] }
            when 'assistant'
              next unless current_turn

              text = extract_message_text(entry)
              current_turn[:assistant] << text unless text.empty?
            end
          rescue ::JSON::ParserError
            next
          end

          turns << current_turn if current_turn
          turns
        end

        def extract_message_text(entry)
          msg = entry[:message]
          return '' unless msg

          content = msg[:content]
          case content
          when String then content
          when Array
            content.filter_map { |block| block[:text] if block[:type] == 'text' }.join("\n")
          else ''
          end
        end

        def format_turn(turn, number)
          text = "## Turn #{number}\n"
          text << "Timestamp: #{turn[:timestamp]}\n\n" if turn[:timestamp]
          text << "### User\n#{truncate_text(turn[:user], 4096)}\n\n"
          text << "### Assistant\n#{truncate_text(turn[:assistant], 4096)}\n"
          text
        end

        def truncate_text(text, max_bytes)
          return text if text.bytesize <= max_bytes

          "#{text.byteslice(0, max_bytes - 20)}\n\n[truncated]"
        end
      end
    end

    class Knowledge < Thor
      def self.exit_on_failure?
        true
      end

      class_option :json,     type: :boolean, default: false, desc: 'Output as JSON'
      class_option :no_color, type: :boolean, default: false, desc: 'Disable color output'

      desc 'query QUESTION', 'Query the knowledge base with optional LLM synthesis'
      option :top_k,      type: :numeric, default: 5, desc: 'Number of source chunks'
      option :synthesize, type: :boolean, default: true,  desc: 'Synthesize an LLM answer'
      option :verbose,    type: :boolean, default: false, desc: 'Show full source metadata'
      def query(question)
        result = api_post('/api/knowledge/query',
                          question: question, top_k: options[:top_k], synthesize: options[:synthesize])
        out = formatter
        if options[:json]
          out.json(result)
        elsif result[:success]
          out.header('Knowledge Query')
          if result[:answer]
            out.spacer
            puts result[:answer]
            out.spacer
          end
          print_sources(result[:sources] || [], out, verbose: options[:verbose])
        else
          out.warn("Query failed: #{result[:error]}")
        end
      end
      default_task :help

      desc 'retrieve QUESTION', 'Retrieve source chunks without LLM synthesis'
      option :top_k, type: :numeric, default: 5, desc: 'Number of source chunks'
      def retrieve(question)
        result = api_post('/api/knowledge/retrieve', question: question, top_k: options[:top_k])
        out = formatter
        if options[:json]
          out.json(result)
        elsif result[:success]
          out.header("Knowledge Retrieve (#{(result[:sources] || []).size} chunks)")
          print_sources(result[:sources] || [], out, verbose: true)
        else
          out.warn("Retrieve failed: #{result[:error]}")
        end
      end

      desc 'ingest PATH', 'Ingest a file or directory into the knowledge base'
      option :force,   type: :boolean, default: false, desc: 'Re-ingest even unchanged files'
      option :dry_run, type: :boolean, default: false, desc: 'Preview without writing'
      def ingest(path)
        payload = { path: ::File.expand_path(path), force: options[:force] }
        payload[:dry_run] = options[:dry_run] if options[:dry_run]
        result = api_post('/api/knowledge/ingest', **payload)
        out = formatter
        if options[:json]
          out.json(result)
        elsif result[:success]
          out.success('Ingest complete')
          out.detail(result.except(:success))
        else
          out.warn("Ingest failed: #{result[:error]}")
        end
      end

      desc 'status', 'Show knowledge base status'
      def status
        result = api_post('/api/knowledge/status', path: ::Dir.pwd)
        out = formatter
        if options[:json]
          out.json(result)
        else
          out.header('Knowledge Status')
          out.detail({
                       'Path'       => result[:path].to_s,
                       'Files'      => result[:file_count].to_s,
                       'Total size' => "#{result[:total_bytes]} bytes"
                     })
        end
      end

      desc 'health', 'Show knowledge base health report (local, Apollo, sync)'
      option :corpus_path, type: :string, desc: 'Path to corpus directory (falls back to settings)'
      def health
        result = api_post('/api/knowledge/health', path: options[:corpus_path])
        out = formatter
        if options[:json]
          out.json(result)
        elsif result[:success]
          out.header('Knowledge Health')
          out.spacer
          out.header('Local')
          out.detail(result[:local])
          out.spacer
          out.header('Apollo')
          out.detail(result[:apollo])
          out.spacer
          out.header('Sync')
          out.detail(result[:sync])
        else
          out.warn("Health check failed: #{result[:error]}")
        end
      end

      desc 'maintain', 'Detect and clean up orphaned knowledge chunks'
      option :corpus_path, type: :string, desc: 'Path to corpus directory (falls back to settings)'
      option :dry_run, type: :boolean, default: true, desc: 'Preview without archiving (default: true)'
      def maintain
        result = api_post('/api/knowledge/maintain',
                          path: options[:corpus_path], dry_run: options[:dry_run])
        out = formatter
        if options[:json]
          out.json(result)
        elsif result[:success]
          out.header("Knowledge Maintain#{' (dry run)' if options[:dry_run]}")
          out.detail({
                       'Orphan files'  => (result[:orphan_files] || []).join(', '),
                       'Archived'      => result[:archived].to_s,
                       'Files cleaned' => result[:files_cleaned].to_s,
                       'Dry run'       => result[:dry_run].to_s
                     })
        else
          out.warn("Maintenance failed: #{result[:error]}")
        end
      end

      desc 'quality', 'Show knowledge quality report (hot, cold, low-confidence chunks)'
      option :limit, type: :numeric, default: 10, desc: 'Max entries per category'
      def quality
        result = api_post('/api/knowledge/quality', limit: options[:limit])
        out = formatter
        if options[:json]
          out.json(result)
        elsif result[:success]
          out.header('Knowledge Quality Report')
          out.spacer
          print_chunk_section('Hot Chunks (most accessed)', result[:hot_chunks], out)
          print_chunk_section('Cold Chunks (never accessed)', result[:cold_chunks], out)
          print_chunk_section('Low Confidence', result[:low_confidence], out)
          out.spacer
          out.header('Summary')
          out.detail(result[:summary])
        else
          out.warn("Quality report failed: #{result[:error]}")
        end
      end

      desc 'monitor SUBCOMMAND', 'Manage knowledge corpus monitors'
      subcommand 'monitor', MonitorCommand

      desc 'capture SUBCOMMAND', 'Capture knowledge from git commits or sessions'
      subcommand 'capture', CaptureCommand

      no_commands do
        include ApiClient

        def formatter
          @formatter ||= Output::Formatter.new(json: options[:json], color: !options[:no_color])
        end

        def print_sources(sources, out, verbose:)
          return out.warn('No sources found') if sources.empty?

          out.header("Sources (#{sources.size})")
          sources.each_with_index do |s, i|
            score   = format('%.2f', s[:score].to_f)
            heading = s[:heading].to_s.empty? ? '' : " \u00a7 #{s[:heading]}"
            puts "  #{i + 1}. #{s[:source_file]}#{heading}   score: #{score}"
            puts "     #{truncate(s[:content].to_s, 100)}" if verbose
          end
        end

        def print_chunk_section(title, chunks, out)
          out.header(title)
          if chunks.empty?
            out.warn('  (none)')
          else
            chunks.each do |c|
              puts "  id=#{c[:id]}  confidence=#{c[:confidence]}  #{c[:source_file]}"
            end
          end
          out.spacer
        end

        def truncate(text, max)
          return text if text.length <= max
          return text[0, max] if max < 4

          "#{text[0, max - 3]}..."
        end
      end
    end
  end
end
