# frozen_string_literal: true

module Legion
  module CLI
    class Doctor
      class Result
        SCORE_MAP = { pass: 1.0, warn: 0.5, fail: 0.0, skip: nil }.freeze

        attr_reader :name, :status, :message, :prescription, :auto_fixable, :weight

        def initialize(name:, status:, message: nil, prescription: nil, auto_fixable: false, weight: 1.0) # rubocop:disable Metrics/ParameterLists
          @name         = name
          @status       = status
          @message      = message
          @prescription = prescription
          @auto_fixable = auto_fixable
          @weight       = weight
        end

        def score
          SCORE_MAP[status]
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
            score:        score,
            weight:       weight,
            message:      message,
            prescription: prescription,
            auto_fixable: auto_fixable
          }.compact
        end
      end
    end
  end
end
