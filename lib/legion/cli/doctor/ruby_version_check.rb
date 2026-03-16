# frozen_string_literal: true

module Legion
  module CLI
    class Doctor
      class RubyVersionCheck
        MINIMUM_VERSION = '3.4'

        def name
          'Ruby version'
        end

        def run
          current = RUBY_VERSION
          if Gem::Version.new(current) >= Gem::Version.new(MINIMUM_VERSION)
            Result.new(name: name, status: :pass, message: "Ruby #{current}")
          else
            Result.new(
              name:         name,
              status:       :fail,
              message:      "Ruby #{current} is below minimum #{MINIMUM_VERSION}",
              prescription: "Upgrade Ruby to >= #{MINIMUM_VERSION} (current: #{current})"
            )
          end
        end
      end
    end
  end
end
