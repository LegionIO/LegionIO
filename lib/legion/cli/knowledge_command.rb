# frozen_string_literal: true

module Legion
  module CLI
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

      no_commands do
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

        def knowledge_query
          Legion::Extensions::Knowledge::Runners::Query
        end

        def knowledge_ingest
          Legion::Extensions::Knowledge::Runners::Ingest
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

        def truncate(text, max)
          return text if text.length <= max
          return text[0, max] if max < 4

          "#{text[0, max - 3]}..."
        end
      end
    end
  end
end
