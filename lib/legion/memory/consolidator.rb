# frozen_string_literal: true

require 'fileutils'

module Legion
  module Memory
    module Consolidator
      LOCK_FILE    = File.expand_path('~/.legionio/cache/memory_consolidation.lock')
      SESSIONS_DIR = File.expand_path('~/.legion/sessions')

      class << self
        def run(force: false)
          return { success: false, reason: :disabled } unless enabled?
          return { success: false, reason: :gates_failed, details: gate_status } unless force || gates_pass?
          return { success: false, reason: :locked } unless acquire_lock

          begin
            result = consolidate
            touch_lock
            publish_to_apollo(result[:insights]) if result[:insights]&.any?
            { success: true, insights_count: result[:insights]&.length || 0, **result }
          ensure
            release_lock
          end
        rescue StandardError => e
          Legion::Logging.error "[Consolidator] failed: #{e.message}" if defined?(Legion::Logging)
          { success: false, reason: :error, error: e.message }
        end

        def gate_status
          {
            time_gate:    time_gate_passes?,
            session_gate: session_gate_passes?,
            lock_gate:    lock_gate_passes?
          }
        end

        def gates_pass?
          time_gate_passes? && session_gate_passes? && lock_gate_passes?
        end

        def enabled?
          settings = consolidation_settings
          settings.fetch(:enabled, false)
        end

        def consolidation_settings
          raw = begin
            Legion::Settings.dig(:memory, :consolidation)
          rescue StandardError
            nil
          end
          defaults = {
            enabled:               false,
            min_hours:             24,
            min_sessions:          5,
            scan_interval_minutes: 10,
            max_index_lines:       200
          }
          raw.is_a?(Hash) ? defaults.merge(raw) : defaults
        end

        private

        def time_gate_passes?
          return true unless File.exist?(LOCK_FILE)

          min_hours = consolidation_settings[:min_hours]
          age_hours = (Time.now - File.mtime(LOCK_FILE)) / 3600.0
          age_hours >= min_hours
        end

        def session_gate_passes?
          return false unless Dir.exist?(SESSIONS_DIR)

          cutoff = File.exist?(LOCK_FILE) ? File.mtime(LOCK_FILE) : Time.at(0)
          recent = Dir.glob(File.join(SESSIONS_DIR, '*.json')).count do |path|
            File.mtime(path) > cutoff
          end
          recent >= consolidation_settings[:min_sessions]
        end

        def lock_gate_passes?
          return true unless File.exist?(LOCK_FILE)

          !File.exist?("#{LOCK_FILE}.active")
        end

        def acquire_lock
          FileUtils.mkdir_p(File.dirname(LOCK_FILE))
          File.open("#{LOCK_FILE}.active", File::WRONLY | File::CREAT | File::EXCL) do |f|
            f.write(::Process.pid.to_s)
          end
          true
        rescue Errno::EEXIST
          false
        rescue StandardError => e
          Legion::Logging.debug "[Consolidator] acquire_lock failed: #{e.message}" if defined?(Legion::Logging)
          false
        end

        def release_lock
          FileUtils.rm_f("#{LOCK_FILE}.active")
        end

        def touch_lock
          FileUtils.mkdir_p(File.dirname(LOCK_FILE))
          FileUtils.touch(LOCK_FILE)
        end

        def consolidate
          transcripts = load_recent_transcripts
          return { insights: [], transcripts_scanned: 0 } if transcripts.empty?

          existing_memory = load_existing_memory

          if llm_available?
            insights = extract_insights_via_llm(transcripts, existing_memory)
            write_insights(insights) if insights.any?
            { insights: insights, transcripts_scanned: transcripts.length }
          else
            { insights: [], transcripts_scanned: transcripts.length, reason: :llm_unavailable }
          end
        end

        def load_recent_transcripts
          return [] unless Dir.exist?(SESSIONS_DIR)

          cutoff = File.exist?(LOCK_FILE) ? File.mtime(LOCK_FILE) : Time.at(0)
          max = consolidation_settings[:min_sessions] * 2

          Dir.glob(File.join(SESSIONS_DIR, '*.json'))
             .select { |p| File.mtime(p) > cutoff }
             .sort_by { |p| File.mtime(p) }
             .last(max)
             .map { |p| extract_transcript_summary(p) }
             .compact
        end

        def extract_transcript_summary(path)
          raw = File.read(path, encoding: 'utf-8')
          data = defined?(Legion::JSON) ? Legion::JSON.load(raw) : JSON.parse(raw, symbolize_names: true)
          messages = data[:messages] || []

          user_msgs = messages.select { |m| m[:role]&.to_s == 'user' }
                              .map { |m| m[:content].to_s[0..300] }
                              .first(10)
          return nil if user_msgs.empty?

          { name: data[:name], messages: user_msgs.join("\n"), cwd: data[:cwd] }
        rescue StandardError => e
          Legion::Logging.debug "[Consolidator] transcript parse failed for #{path}: #{e.message}" if defined?(Legion::Logging)
          nil
        end

        def load_existing_memory
          require 'legion/cli/chat/memory_store'
          Legion::CLI::Chat::MemoryStore.load_context
        rescue StandardError
          nil
        end

        def llm_available?
          defined?(Legion::LLM) && Legion::LLM.respond_to?(:chat_direct)
        end

        def extract_insights_via_llm(transcripts, existing_memory)
          transcript_text = transcripts.map do |t|
            "Session: #{t[:name]} (#{t[:cwd]})\n#{t[:messages]}"
          end.join("\n---\n")

          prompt = <<~PROMPT
            You are a memory consolidation agent. Analyze these recent session transcripts and extract cross-session insights.

            ## Existing Memory
            #{existing_memory || '(empty)'}

            ## Recent Session Transcripts
            #{transcript_text}

            Extract insights as a JSON array. Each insight should have:
            - "text": a concise one-line insight (pattern, preference, or learning)
            - "category": one of "pattern", "preference", "learning", "project"

            Only include genuinely new insights not already in existing memory. Return [] if nothing new.
            Respond with ONLY the JSON array, no other text.
          PROMPT

          session = Legion::LLM.chat_direct(model: nil, provider: nil)
          response = session.ask(prompt)
          content = response.respond_to?(:content) ? response.content : response.to_s

          parse_insights(content)
        rescue StandardError => e
          Legion::Logging.warn "[Consolidator] LLM extraction failed: #{e.message}" if defined?(Legion::Logging)
          []
        end

        def parse_insights(text)
          json_match = text.match(/\[.*\]/m)
          return [] unless json_match

          parsed = defined?(Legion::JSON) ? Legion::JSON.load(json_match[0]) : JSON.parse(json_match[0], symbolize_names: true)
          return [] unless parsed.is_a?(Array)

          parsed.select { |i| i.is_a?(Hash) && (i[:text] || i['text']) }
                .map { |i| { text: (i[:text] || i['text']).to_s, category: (i[:category] || i['category'] || 'learning').to_s } }
        rescue StandardError
          []
        end

        def write_insights(insights)
          require 'legion/cli/chat/memory_store'
          insights.each do |insight|
            Legion::CLI::Chat::MemoryStore.add(
              "[#{insight[:category]}] #{insight[:text]}",
              scope: :global
            )
          end
          Legion::Logging.info "[Consolidator] wrote #{insights.length} insights to global memory" if defined?(Legion::Logging)
        end

        def publish_to_apollo(insights)
          return unless defined?(Legion::Apollo) && Legion::Apollo.respond_to?(:ingest)

          insights.each do |insight|
            Legion::Apollo.ingest(
              content:          insight[:text],
              tags:             ['memory_consolidation', 'cross_session', insight[:category]],
              knowledge_domain: 'memory',
              source_agent:     'system:memory_consolidator',
              is_inference:     true
            )
          end
        rescue StandardError => e
          Legion::Logging.debug "[Consolidator] Apollo publish failed: #{e.message}" if defined?(Legion::Logging)
        end
      end
    end
  end
end
