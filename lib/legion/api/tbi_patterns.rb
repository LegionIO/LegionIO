# frozen_string_literal: true

require 'digest'

module Legion
  class API < Sinatra::Base
    module Routes
      module TbiPatterns
        MAX_DESCRIPTION_BYTES  = 1024
        MAX_PAYLOAD_SHAPE_BYTES = 65_536
        VALID_TIERS = %w[tier1 tier2 tier3 tier4 tier5].freeze

        def self.registered(app)
          register_export(app)
          register_fetch(app)
          register_all(app)
          register_score(app)
          register_discover(app)
        end

        # POST /api/tbi/patterns/export — anonymously export a learned behavioral pattern
        def self.register_export(app) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
          app.post '/api/tbi/patterns/export' do
            require_data!
            body = parse_request_body

            unless body[:pattern_type]
              Legion::Logging.warn 'API POST /api/tbi/patterns/export returned 422: pattern_type is required' if defined?(Legion::Logging)
              halt 422, json_error('missing_field', 'pattern_type is required', status_code: 422)
            end
            unless body[:description]
              Legion::Logging.warn 'API POST /api/tbi/patterns/export returned 422: description is required' if defined?(Legion::Logging)
              halt 422, json_error('missing_field', 'description is required', status_code: 422)
            end
            unless body[:pattern_data]
              Legion::Logging.warn 'API POST /api/tbi/patterns/export returned 422: pattern_data is required' if defined?(Legion::Logging)
              halt 422, json_error('missing_field', 'pattern_data is required', status_code: 422)
            end
            unless body[:tier]
              Legion::Logging.warn 'API POST /api/tbi/patterns/export returned 422: tier is required' if defined?(Legion::Logging)
              halt 422, json_error('missing_field', 'tier is required', status_code: 422)
            end

            if body[:description].to_s.bytesize > MAX_DESCRIPTION_BYTES
              halt 422, json_error('field_too_large', "description exceeds #{MAX_DESCRIPTION_BYTES} bytes", status_code: 422)
            end

            pattern_data_str = Routes::TbiPatterns.serialize_pattern_data(body[:pattern_data])
            if pattern_data_str.bytesize > MAX_PAYLOAD_SHAPE_BYTES
              halt 422, json_error('field_too_large', "pattern_data exceeds #{MAX_PAYLOAD_SHAPE_BYTES} bytes", status_code: 422)
            end

            unless VALID_TIERS.include?(body[:tier].to_s)
              halt 422, json_error('invalid_field', "tier must be one of: #{VALID_TIERS.join(', ')}", status_code: 422)
            end

            # Anonymize: strip any identifying keys before persisting
            anonymous_data = Routes::TbiPatterns.anonymize(body)

            invocation_count = Routes::TbiPatterns.parse_integer(body[:invocation_count], 0)
            success_rate     = Routes::TbiPatterns.parse_float(body[:success_rate], 0.0)
            quality_score    = Routes::TbiPatterns.compute_quality(
              invocation_count: invocation_count,
              success_rate:     success_rate,
              tier:             body[:tier].to_s
            )

            record = Legion::Data::Model::TbiPattern.create(
              pattern_type:     body[:pattern_type].to_s,
              description:      body[:description].to_s,
              tier:             body[:tier].to_s,
              pattern_data:     pattern_data_str,
              quality_score:    quality_score,
              invocation_count: invocation_count,
              success_rate:     success_rate,
              source_hash:      anonymous_data[:source_hash]
            )
            Legion::Logging.info "API: exported TBI pattern id=#{record.id} tier=#{record.tier}" if defined?(Legion::Logging)
            json_response(record.values, status_code: 201)
          rescue StandardError => e
            Legion::Logging.error "API POST /api/tbi/patterns/export: #{e.class} — #{e.message}" if defined?(Legion::Logging)
            json_error('export_error', e.message, status_code: 500)
          end
        end

        # GET /api/tbi/patterns/:id — fetch a single pattern by integer ID
        def self.register_fetch(app)
          app.get '/api/tbi/patterns/:id' do
            require_data!
            id_val = params[:id].to_i
            if id_val <= 0
              halt 422, json_error('invalid_id', 'id must be a positive integer', status_code: 422)
            end

            record = Legion::Data::Model::TbiPattern.first(id: id_val)
            unless record
              halt 404, json_error('not_found', "TBI pattern #{params[:id]} not found", status_code: 404)
            end

            json_response(record.values)
          rescue StandardError => e
            Legion::Logging.error "API GET /api/tbi/patterns/#{params[:id]}: #{e.class} — #{e.message}" if defined?(Legion::Logging)
            json_error('fetch_error', e.message, status_code: 500)
          end
        end

        # GET /api/tbi/patterns — list patterns with optional tier/type filter
        def self.register_all(app)
          app.get '/api/tbi/patterns' do
            require_data!
            dataset = Legion::Data::Model::TbiPattern.order(Sequel.desc(:quality_score))
            dataset = dataset.where(tier: params[:tier])             if params[:tier]
            dataset = dataset.where(pattern_type: params[:type])    if params[:type]
            json_collection(dataset)
          rescue StandardError => e
            Legion::Logging.error "API GET /api/tbi/patterns: #{e.class} — #{e.message}" if defined?(Legion::Logging)
            json_error('list_error', e.message, status_code: 500)
          end
        end

        # PATCH /api/tbi/patterns/:id/score — update quality score with new usage metadata
        def self.register_score(app) # rubocop:disable Metrics/AbcSize
          app.patch '/api/tbi/patterns/:id/score' do
            require_data!
            id_val = params[:id].to_i
            if id_val <= 0
              halt 422, json_error('invalid_id', 'id must be a positive integer', status_code: 422)
            end

            record = Legion::Data::Model::TbiPattern.first(id: id_val)
            unless record
              halt 404, json_error('not_found', "TBI pattern #{params[:id]} not found", status_code: 404)
            end

            body = parse_request_body
            invocation_count = Routes::TbiPatterns.parse_integer(body[:invocation_count], record.invocation_count)
            success_rate     = Routes::TbiPatterns.parse_float(body[:success_rate],     record.success_rate)
            quality_score    = Routes::TbiPatterns.compute_quality(
              invocation_count: invocation_count,
              success_rate:     success_rate,
              tier:             record.tier
            )

            record.update(
              invocation_count: invocation_count,
              success_rate:     success_rate,
              quality_score:    quality_score
            )
            Legion::Logging.info "API: rescored TBI pattern id=#{record.id} quality=#{quality_score}" if defined?(Legion::Logging)
            json_response(record.values)
          rescue StandardError => e
            Legion::Logging.error "API PATCH /api/tbi/patterns/#{params[:id]}/score: #{e.class} — #{e.message}" if defined?(Legion::Logging)
            json_error('score_error', e.message, status_code: 500)
          end
        end

        # GET /api/tbi/patterns/discover — cross-instance pattern discovery (P3/TBI Phase 6)
        # TODO: implement cross-instance discovery per docs/work/completed/knowledge-pattern-marketplace.md
        def self.register_discover(app)
          app.get '/api/tbi/patterns/discover' do
            halt 501, json_error('not_implemented', 'cross-instance pattern discovery is not yet available', status_code: 501)
          end
        end

        # --- helpers ---

        # Anonymize pattern export: remove instance-identifying fields, compute a
        # one-way hash for deduplication without fingerprinting.
        def self.anonymize(body)
          identifying_keys = %i[node_id instance_id hostname ip_address worker_id]
          sanitized = body.reject { |k, _v| identifying_keys.include?(k.to_sym) }
          # Remove both string and symbol variants
          sanitized = sanitized.reject { |k, _v| identifying_keys.map(&:to_s).include?(k.to_s) }

          salt_source = "#{body[:pattern_type]}:#{body[:tier]}:#{body[:description]}"
          source_hash = Digest::SHA256.hexdigest(salt_source)[0, 16]

          sanitized.merge(source_hash: source_hash)
        end

        def self.serialize_pattern_data(pattern_data)
          return pattern_data.to_s if pattern_data.is_a?(String)

          Legion::JSON.dump(pattern_data)
        rescue StandardError
          pattern_data.to_s
        end

        def self.compute_quality(invocation_count:, success_rate:, tier:)
          # tier weight: higher tiers (closer to tier5) earn a modest bonus
          tier_num    = tier.to_s.gsub(/[^0-9]/, '').to_i.clamp(1, 5)
          tier_weight = tier_num / 5.0

          count_score   = [invocation_count.to_f / 100.0, 1.0].min
          success_score = success_rate.to_f.clamp(0.0, 1.0)

          ((count_score * 0.4) + (success_score * 0.5) + (tier_weight * 0.1)).round(4)
        end

        # Parse an integer from user input; return default if blank, zero on invalid string.
        def self.parse_integer(value, default)
          return default if value.nil?
          return default if value.to_s.strip.empty?
          raise ArgumentError, 'not numeric' unless value.to_s =~ /\A-?\d+\z/

          value.to_i
        rescue ArgumentError
          0
        end

        # Parse a float from user input; return default if blank, raise on non-numeric.
        def self.parse_float(value, default)
          return default if value.nil?
          return default if value.to_s.strip.empty?
          raise ArgumentError, 'not numeric' unless value.to_s =~ /\A-?\d+(\.\d+)?\z/

          value.to_f
        rescue ArgumentError
          0.0
        end

        private_class_method :register_export, :register_fetch, :register_all,
                             :register_score, :register_discover
      end
    end
  end
end
