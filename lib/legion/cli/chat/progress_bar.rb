# frozen_string_literal: true

module Legion
  module CLI
    class Chat
      class ProgressBar
        attr_reader :total, :current

        def initialize(total:, label: '', width: 40, output: $stdout)
          @total = [total, 1].max
          @current = 0
          @label = label
          @width = width
          @output = output
          @start_time = Time.now
        end

        def advance(amount = 1)
          @current = [@current + amount, @total].min
          render
          self
        end

        def finish
          @current = @total
          render
          @output.puts
          self
        end

        def percentage
          (@current.to_f / @total * 100).round(1)
        end

        def elapsed
          Time.now - @start_time
        end

        def eta
          return 0 if @current.zero? || @current >= @total

          (elapsed / @current * (@total - @current)).round
        end

        private

        def render
          filled = (@width * @current.to_f / @total).round
          bar = ('#' * filled) + ('-' * [(@width - filled), 0].max)
          @output.print "\r#{@label} [#{bar}] #{percentage}% (#{@current}/#{@total}) ETA: #{eta}s  "
        end
      end
    end
  end
end
