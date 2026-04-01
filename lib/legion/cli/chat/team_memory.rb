# frozen_string_literal: true

module Legion
  module CLI
    class Chat
      module TeamMemory
        class << self
          def enabled?
            settings = team_sync_settings
            settings[:enabled] == true
          end

          def sync_add(text)
            return unless enabled?
            return unless apollo_available?

            repo = git_remote_url
            return unless repo

            Legion::Apollo.ingest(
              content:          text,
              tags:             ['team_memory', "repo:#{repo}"],
              knowledge_domain: 'team_memory',
              source_agent:     "user:#{current_user}",
              scope:            :global,
              is_inference:     false
            )
          rescue StandardError => e
            Legion::Logging.debug "[TeamMemory] sync_add failed: #{e.message}" if defined?(Legion::Logging)
          end

          def retrieve
            return [] unless enabled?
            return [] unless apollo_available?

            repo = git_remote_url
            return [] unless repo

            limit = team_sync_settings[:limit] || 20
            results = Legion::Apollo.retrieve(
              '',
              tags:  ['team_memory', "repo:#{repo}"],
              scope: :global,
              limit: limit
            )

            return [] unless results.is_a?(Array)

            results.map { |r| r.is_a?(Hash) ? (r[:content] || r['content']) : r.to_s }
                   .compact
                   .reject(&:empty?)
          rescue StandardError => e
            Legion::Logging.debug "[TeamMemory] retrieve failed: #{e.message}" if defined?(Legion::Logging)
            []
          end

          def load_context
            entries = retrieve
            return nil if entries.empty?

            "## Team Memory\n\n#{entries.map { |e| "- #{e}" }.join("\n")}"
          end

          private

          def team_sync_settings
            raw = begin
              Legion::Settings.dig(:memory, :team_sync)
            rescue StandardError
              nil
            end
            raw.is_a?(Hash) ? { enabled: false, limit: 20 }.merge(raw) : { enabled: false, limit: 20 }
          end

          def apollo_available?
            defined?(Legion::Apollo) &&
              Legion::Apollo.respond_to?(:ingest) &&
              Legion::Apollo.respond_to?(:retrieve)
          end

          def git_remote_url
            url = `git remote get-url origin 2>/dev/null`.strip
            url.empty? ? nil : url
          rescue StandardError
            nil
          end

          def current_user
            ENV['USER'] || 'unknown'
          end
        end
      end
    end
  end
end
