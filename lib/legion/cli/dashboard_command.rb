# frozen_string_literal: true

require 'thor'

module Legion
  module CLI
    class DashboardCommand < Thor
      namespace 'dashboard'

      desc 'start', 'Launch the TUI dashboard'
      option :url, type: :string, default: 'http://localhost:4567', desc: 'API base URL'
      option :refresh, type: :numeric, default: 2, desc: 'Refresh interval in seconds'
      def start
        require 'legion/cli/dashboard/data_fetcher'
        require 'legion/cli/dashboard/renderer'

        fetcher = Dashboard::DataFetcher.new(base_url: options[:url])
        renderer = Dashboard::Renderer.new

        puts 'Starting dashboard... (press q to quit)'
        loop do
          system('clear') || system('cls')
          data = fetcher.summary
          puts renderer.render(data)

          ready = $stdin.wait_readable(options[:refresh])
          if ready
            input = $stdin.getc
            break if input == 'q'
          end
        rescue Interrupt
          Legion::Logging.debug('DashboardCommand#start interrupted by user') if defined?(Legion::Logging)
          break
        end
        puts 'Dashboard stopped.'
      end

      default_task :start
    end
  end
end
