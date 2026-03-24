# frozen_string_literal: true

require_relative 'archiver'

module Legion
  module Audit
    class ArchiverActor
      INTERVAL_SECONDS = 3600 # check every hour; day-of-week guard applies

      class << self
        def enabled?
          Legion::Audit::Archiver.enabled?
        end

        def schedule_setting
          Legion::Settings[:audit]&.dig(:retention, :archive_schedule) || '0 2 * * 0'
        end

        # Parse cron day-of-week (field 5) — returns integer 0..6, 0=Sunday
        def scheduled_day_of_week
          schedule_setting.split[4].to_i
        end

        # Parse cron hour (field 2)
        def scheduled_hour
          schedule_setting.split[1].to_i
        end
      end

      def run_archival
        return unless self.class.enabled?

        now = Time.now.utc
        return unless now.wday == self.class.scheduled_day_of_week
        return unless now.hour == self.class.scheduled_hour

        Legion::Logging.info '[Audit::ArchiverActor] starting weekly archival' if defined?(Legion::Logging)

        warm_result = Legion::Audit::Archiver.archive_to_warm
        cold_result = Legion::Audit::Archiver.archive_to_cold

        if Legion::Audit::Archiver.verify_on_archive?
          verify_result = Legion::Audit::Archiver.verify_chain(tier: :warm)
          if !verify_result[:valid] && defined?(Legion::Logging)
            Legion::Logging.error "[Audit::ArchiverActor] chain broken after archival: #{verify_result[:broken_links].count} links"
          end
        end

        return unless defined?(Legion::Logging)

        Legion::Logging.info "[Audit::ArchiverActor] complete warm=#{warm_result[:moved]} cold=#{cold_result[:moved]}"
      end
    end
  end
end
