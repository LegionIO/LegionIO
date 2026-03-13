# frozen_string_literal: true

module Legion
  module Runner
    module Log
      def self.exception(exc, **opts)
        Legion::Logging.error exc.message
        Legion::Logging.error opts
      end
    end
  end
end
