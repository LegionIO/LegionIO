# frozen_string_literal: true

module Legion
  class API < Sinatra::Base
    module Helpers
      def json_response(data, status_code: 200)
        content_type :json
        status status_code
        Legion::JSON.dump({
                            data: data,
                            meta: response_meta
                          })
      end

      def json_collection(dataset, status_code: 200)
        content_type :json
        status status_code

        paginated = paginate(dataset)
        items = paginated.respond_to?(:all) ? paginated.all : Array(paginated)
        total = collection_total(dataset, items)
        meta = response_meta.merge(
          count:  items.length,
          limit:  page_limit,
          offset: page_offset
        )
        meta[:total] = total unless total.nil?
        meta[:has_more] = collection_has_more?(items, total)

        Legion::JSON.dump({
                            data: items.map { |r| r.respond_to?(:values) ? r.values : r },
                            meta: meta
                          })
      end

      def json_error(code, message, status_code: 400)
        content_type :json
        status status_code
        Legion::JSON.dump({
                            error: { code: code, message: message },
                            meta:  response_meta
                          })
      end

      def require_data!
        return if Legion::Settings[:data][:connected]

        halt 503, json_error('data_unavailable', 'legion-data is not connected', status_code: 503)
      end

      def require_scheduler!
        require_data!
        return if defined?(Legion::Extensions::Scheduler)

        halt 503, json_error('scheduler_unavailable', 'lex-scheduler is not loaded', status_code: 503)
      end

      def require_knowledge_query!
        return if defined?(Legion::Extensions::Knowledge::Runners::Query)

        halt 503, json_error('knowledge_unavailable', 'lex-knowledge is not loaded', status_code: 503)
      end

      def require_knowledge_ingest!
        return if defined?(Legion::Extensions::Knowledge::Runners::Ingest)

        halt 503, json_error('knowledge_unavailable', 'lex-knowledge is not loaded', status_code: 503)
      end

      def require_knowledge_maintenance!
        return if defined?(Legion::Extensions::Knowledge::Runners::Maintenance)

        halt 503, json_error('knowledge_unavailable', 'lex-knowledge is not loaded', status_code: 503)
      end

      def require_knowledge_monitor!
        return if defined?(Legion::Extensions::Knowledge::Runners::Monitor)

        halt 503, json_error('knowledge_unavailable', 'lex-knowledge is not loaded', status_code: 503)
      end

      def require_mesh!
        return if defined?(Legion::Extensions::Mesh)

        halt 503, json_error('mesh_unavailable', 'lex-mesh is not loaded', status_code: 503)
      end

      def require_trace_search!
        return if defined?(Legion::TraceSearch) && defined?(Legion::LLM)

        halt 503, json_error('trace_search_unavailable', 'TraceSearch requires LLM subsystem', status_code: 503)
      end

      def parse_request_body
        body = request.body.read
        return {} if body.nil? || body.empty?

        Legion::JSON.load(body).transform_keys(&:to_sym)
      rescue StandardError => e
        Legion::Logging.warn "API#parse_request_body failed to parse JSON: #{e.message}" if defined?(Legion::Logging)
        halt 400, json_error('invalid_json', 'request body is not valid JSON', status_code: 400)
      end

      def find_or_halt(model_class, id)
        record = model_class[id.to_i]
        halt 404, json_error('not_found', "#{model_class.name.split('::').last} #{id} not found", status_code: 404) if record.nil?
        record
      end

      def redact_hash(hash, sensitive_keys: %i[password secret token key cert private_key api_key])
        return hash unless hash.is_a?(Hash)

        hash.each_with_object({}) do |(k, v), result|
          key_sym = k.to_sym
          result[k] = if v.is_a?(Hash)
                        redact_hash(v, sensitive_keys: sensitive_keys)
                      elsif sensitive_keys.any? { |s| key_sym.to_s.include?(s.to_s) }
                        '[REDACTED]'
                      else
                        v
                      end
        end
      end

      def transport_subclasses(base_class)
        ObjectSpace.each_object(Class)
                   .select { |klass| klass < base_class }
                   .map { |klass| { name: klass.name } }
                   .sort_by { |h| h[:name].to_s }
      rescue NameError => e
        Legion::Logging.debug "API#transport_subclasses failed for #{base_class}: #{e.message}" if defined?(Legion::Logging)
        []
      end

      def build_schedule_attrs(body)
        attrs = { function_id: body[:function_id].to_i, active: body.fetch(:active, true), last_run: Time.at(0) }
        attrs[:cron] = body[:cron] if body[:cron]
        attrs[:interval] = body[:interval].to_i if body[:interval]
        attrs[:task_ttl] = body[:task_ttl].to_i if body[:task_ttl]
        attrs[:payload] = Legion::JSON.dump(body[:payload] || {})
        attrs[:transformation] = body[:transformation] if body[:transformation]
        attrs
      end

      def build_schedule_updates(body)
        updates = {}
        updates[:cron] = body[:cron] if body.key?(:cron)
        updates[:interval] = body[:interval].to_i if body.key?(:interval)
        updates[:active] = body[:active] if body.key?(:active)
        updates[:task_ttl] = body[:task_ttl].to_i if body.key?(:task_ttl)
        updates[:function_id] = body[:function_id].to_i if body.key?(:function_id)
        updates[:payload] = Legion::JSON.dump(body[:payload]) if body.key?(:payload)
        updates[:transformation] = body[:transformation] if body.key?(:transformation)
        updates
      end

      def current_claims
        env['legion.auth']
      end

      def current_worker_id
        env['legion.worker_id']
      end

      def current_owner_msid
        env['legion.owner_msid']
      end

      def authenticated?
        !current_claims.nil?
      end

      private

      def response_meta
        meta = {
          timestamp: Time.now.utc.iso8601,
          node:      Legion::Settings[:client][:name]
        }

        if authenticated? && defined?(Legion::Identity::Request)
          req = env['legion.principal']
          if req
            meta[:caller] = {
              canonical_name: req.canonical_name,
              kind:           req.kind,
              source:         req.source
            }
          end
        end

        meta
      end

      def page_limit
        limit = (params[:limit] || 25).to_i
        limit = 25 if limit < 1
        limit = 100 if limit > 100
        limit
      end

      def page_offset
        offset = (params[:offset] || 0).to_i
        offset = 0 if offset.negative?
        offset
      end

      def paginate(dataset)
        if dataset.respond_to?(:limit)
          dataset.limit(page_limit, page_offset)
        elsif dataset.is_a?(Array)
          dataset.slice(page_offset, page_limit) || []
        else
          dataset
        end
      end

      def include_total_count?
        params[:include_total].to_s == 'true'
      end

      def collection_total(dataset, items)
        return dataset.count if include_total_count? && dataset.respond_to?(:count)
        return dataset.length if dataset.respond_to?(:length) && !dataset.respond_to?(:limit)

        return page_offset + items.length if items.length < page_limit

        nil
      end

      def collection_has_more?(items, total)
        return (page_offset + items.length) < total if total

        items.length == page_limit
      end
    end
  end
end
