# frozen_string_literal: true

module Legion
  module CLI
    module Dashboard
      class Renderer
        def initialize(width: nil)
          @width = width || default_width
        end

        def render(data)
          lines = []
          lines << header_line(data)
          lines << separator
          lines << workers_section(data[:workers] || [])
          lines << separator
          lines << events_section(data[:events] || [])
          lines << separator
          lines << health_section(data[:health] || {})
          lines << separator
          lines << org_chart_section(data[:departments] || [])
          lines << footer_line(data[:fetched_at])
          lines.flatten.join("\n")
        end

        private

        def default_width
          defined?(TTY::Screen) ? TTY::Screen.width : 80
        end

        def header_line(data)
          workers = data[:workers]&.size || 0
          "Legion Dashboard | Workers: #{workers} | #{Time.now.strftime('%H:%M:%S')}"
        end

        def separator
          '-' * @width
        end

        def workers_section(workers)
          lines = ['Active Workers:']
          workers.first(5).each do |w|
            id = w[:worker_id] || w[:id] || 'unknown'
            status = w[:status] || w[:lifecycle_state] || 'unknown'
            lines << "  #{id.to_s.ljust(20)} #{status.to_s.ljust(10)}"
          end
          lines << '  (none)' if workers.empty?
          lines
        end

        def events_section(events)
          lines = ['Recent Events:']
          events.first(5).each do |e|
            time = e[:timestamp] || e[:created_at] || ''
            name = e[:event_name] || e[:name] || ''
            lines << "  #{time.to_s[11..18]} #{name}"
          end
          lines << '  (none)' if events.empty?
          lines
        end

        def health_section(health)
          components = health.map { |k, v| "#{k}: #{v}" }.join(' | ')
          "Health: #{components.empty? ? 'unknown' : components}"
        end

        def org_chart_section(departments)
          lines = ['Org Chart:']
          if departments.empty?
            lines << '  (no departments)'
          else
            departments.each do |dept|
              lines << "  #{dept[:name]}"
              (dept[:roles] || []).each do |role|
                lines << "    +-- #{role[:name]}"
                (role[:workers] || []).each do |w|
                  lines << "    |   +-- #{w[:name]} (#{w[:status]})"
                end
              end
            end
          end
          lines
        end

        def footer_line(fetched_at)
          "Last updated: #{fetched_at&.strftime('%H:%M:%S') || 'never'} | Press q to quit, r to refresh"
        end
      end
    end
  end
end
