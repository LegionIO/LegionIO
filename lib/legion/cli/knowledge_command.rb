# frozen_string_literal: true

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
        require_monitor!
        exts = options[:extensions]&.split(',')&.map(&:strip)
        result = Legion::Extensions::Knowledge::Runners::Monitor.add_monitor(
          path:       path,
          extensions: exts,
          label:      options[:label]
        )
        out = formatter
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
        require_monitor!
        monitors = Legion::Extensions::Knowledge::Runners::Monitor.list_monitors
        out = formatter
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
        require_monitor!
        result = Legion::Extensions::Knowledge::Runners::Monitor.remove_monitor(identifier:)
        out = formatter
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
        require_monitor!
        result = Legion::Extensions::Knowledge::Runners::Monitor.monitor_status
        out = formatter
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
        def formatter
          @formatter ||= Output::Formatter.new(json: options[:json], color: !options[:no_color])
        end

        def require_monitor!
          return if defined?(Legion::Extensions::Knowledge::Runners::Monitor)

          raise CLI::Error, 'lex-knowledge extension is not loaded. Install and enable it first.'
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

        result = if defined?(Legion::Extensions::Knowledge::Runners::Ingest)
                   Legion::Extensions::Knowledge::Runners::Ingest.ingest_file(
                     content: content,
                     tags:    tags,
                     source:  "git:#{sha}"
                   )
                 else
                   { success: false, error: 'lex-knowledge not loaded' }
                 end

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

        result = if defined?(Legion::Extensions::Knowledge::Runners::Ingest)
                   Legion::Extensions::Knowledge::Runners::Ingest.ingest_file(
                     content: content,
                     tags:    tags,
                     source:  "session:#{::Time.now.iso8601}"
                   )
                 else
                   { success: false, error: 'lex-knowledge not loaded' }
                 end

        out = formatter
        if options[:json]
          out.json(result)
        elsif result[:success]
          out.success('Session captured')
        else
          out.warn("Capture failed: #{result[:error]}")
        end
      end

      no_commands do
        def formatter
          @formatter ||= Output::Formatter.new(json: options[:json], color: !options[:no_color])
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
        require_knowledge!
        result = knowledge_query.query(question: question, top_k: options[:top_k],
                                       synthesize: options[:synthesize])
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
        require_knowledge!
        result = knowledge_query.retrieve(question: question, top_k: options[:top_k])
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
        require_ingest!
        result = if ::File.directory?(path)
                   knowledge_ingest.ingest_corpus(path: path, force: options[:force],
                                                  dry_run: options[:dry_run])
                 else
                   knowledge_ingest.ingest_file(file_path: path, force: options[:force],
                                                dry_run: options[:dry_run])
                 end
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
        require_ingest!
        result = knowledge_ingest.scan_corpus(path: ::Dir.pwd)
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
        require_maintenance!
        path = resolve_corpus_path
        result = knowledge_maintenance.health(path: path)
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
        require_maintenance!
        path = resolve_corpus_path
        result = knowledge_maintenance.cleanup_orphans(path: path, dry_run: options[:dry_run])
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
        require_maintenance!
        result = knowledge_maintenance.quality_report(limit: options[:limit])
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

      no_commands do # rubocop:disable Metrics/BlockLength
        def formatter
          @formatter ||= Output::Formatter.new(json: options[:json], color: !options[:no_color])
        end

        def require_knowledge!
          return if defined?(Legion::Extensions::Knowledge::Runners::Query)

          raise CLI::Error, 'lex-knowledge extension is not loaded. Install and enable it first.'
        end

        def require_ingest!
          return if defined?(Legion::Extensions::Knowledge::Runners::Ingest)

          raise CLI::Error, 'lex-knowledge extension is not loaded. Install and enable it first.'
        end

        def require_maintenance!
          return if defined?(Legion::Extensions::Knowledge::Runners::Maintenance)

          raise CLI::Error, 'lex-knowledge extension is not loaded. Install and enable it first.'
        end

        def knowledge_query
          Legion::Extensions::Knowledge::Runners::Query
        end

        def knowledge_ingest
          Legion::Extensions::Knowledge::Runners::Ingest
        end

        def knowledge_maintenance
          Legion::Extensions::Knowledge::Runners::Maintenance
        end

        def resolve_corpus_path
          if options[:corpus_path]
            options[:corpus_path]
          elsif defined?(Legion::Extensions::Knowledge::Runners::Monitor)
            monitors = Legion::Extensions::Knowledge::Runners::Monitor.resolve_monitors
            monitors.first&.dig(:path) || legacy_corpus_path || ::Dir.pwd
          elsif defined?(Legion::Settings)
            Legion::Settings.dig(:knowledge, :corpus_path) || ::Dir.pwd
          else
            ::Dir.pwd
          end
        end

        def legacy_corpus_path
          return unless defined?(Legion::Settings)

          Legion::Settings.dig(:knowledge, :corpus_path)
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
