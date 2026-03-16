# frozen_string_literal: true

module Legion
  module CLI
    class Doctor
      class Result
        attr_reader :name, :status, :message, :prescription, :auto_fixable

        def initialize(name:, status:, message: nil, prescription: nil, auto_fixable: false)
          @name         = name
          @status       = status
          @message      = message
          @prescription = prescription
          @auto_fixable = auto_fixable
        end

        def pass?
          status == :pass
        end

        def fail?
          status == :fail
        end

        def warn?
          status == :warn
        end

        def skip?
          status == :skip
        end

        def to_h
          {
            name:         name,
            status:       status,
            message:      message,
            prescription: prescription,
            auto_fixable: auto_fixable
          }.compact
        end
      end
    end
  end
end
