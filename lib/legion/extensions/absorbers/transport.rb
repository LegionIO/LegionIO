# frozen_string_literal: true

require 'securerandom'

module Legion
  module Extensions
    module Absorbers
      module Transport
        module_function

        def publish_absorb_request(absorber_class:, record:)
          lex  = lex_name_from_absorber_class(absorber_class)
          name = absorber_name_from_class(absorber_class)
          msg  = build_message(lex_name: lex, absorber_name: name, record: record)
          return msg unless transport_connected?

          exchange = Legion::Transport::Exchange.new(msg[:exchange], type: :topic, durable: true)
          exchange.publish(
            Legion::JSON.dump(msg[:payload]),
            routing_key:  msg[:routing_key],
            content_type: 'application/json',
            message_id:   record[:absorb_id]
          )
          msg
        end

        def build_message(lex_name:, absorber_name:, record:)
          input = record[:input].to_s
          {
            exchange:    "lex.#{lex_name}",
            routing_key: "lex.#{lex_name}.absorbers.#{absorber_name}.absorb",
            payload:     {
              type:      'absorb.request',
              version:   '1.0',
              id:        SecureRandom.uuid,
              absorb_id: record[:absorb_id],
              timestamp: Time.now.utc.iso8601,
              url:       input.start_with?('http') ? input : nil,
              file_path: input.start_with?('http') ? nil : input,
              context:   record[:context],
              metadata:  record[:metadata] || {}
            }
          }
        end

        def lex_name_from_absorber_class(klass)
          name = klass.name.to_s
          # Legion::Extensions::MicrosoftTeams::Absorbers::Meeting -> microsoft_teams
          # Lex::Example::Absorbers::Content -> example
          m = name.match(/Legion::Extensions::(\w+)::Absorbers::/) ||
              name.match(/Lex::(\w+)::Absorbers::/)
          return 'unknown' unless m

          m[1].gsub(/([A-Z])/, '_\1').sub(/^_/, '').downcase
        end

        def absorber_name_from_class(klass)
          klass.name.to_s.split('::').last
               .gsub(/([A-Z])/, '_\1').sub(/^_/, '').downcase
        end

        def transport_connected?
          defined?(Legion::Transport) &&
            Legion::Transport.respond_to?(:connected?) &&
            Legion::Transport.connected?
        end
      end
    end
  end
end
