# frozen_string_literal: true

require_relative 'base'

module Legion
  module Extensions
    module Helpers
      module Logger
        include Legion::Extensions::Helpers::Base
        include Legion::Logging::Helper

        def handle_exception(exception, task_id: nil, **opts)
          spec = gem_spec_for_lex
          log.log_exception(exception,
                            lex:             log_lex_name,
                            component_type:  derive_component_type,
                            gem_name:        lex_gem_name,
                            lex_version:     spec&.version&.to_s,
                            gem_path:        spec&.full_gem_path,
                            source_code_uri: spec&.metadata&.[]('source_code_uri'),
                            handled:         true,
                            payload_summary: opts.empty? ? nil : opts,
                            task_id:         task_id)

          unless task_id.nil?
            Legion::Transport::Messages::TaskLog.new(
              task_id:      task_id,
              runner_class: to_s,
              entry:        {
                exception: true,
                message:   exception.message,
                **opts
              }
            ).publish
          end

          raise Legion::Exception::HandledTask
        end

        private

        def derive_component_type
          parts = respond_to?(:calling_class_array) ? calling_class_array : self.class.to_s.split('::')
          match = parts.find { |p| Legion::Extensions::Helpers::Base::NAMESPACE_BOUNDARIES.include?(p) }
          case match
          when 'Runners'          then :runner
          when 'Actor', 'Actors'  then :actor
          when 'Transport'        then :transport
          when 'Helpers'          then :helper
          when 'Data'             then :data
          else :unknown
          end
        rescue StandardError
          :unknown
        end

        def lex_gem_name
          base_name = log_lex_name
          return nil unless base_name

          "lex-#{base_name}"
        rescue StandardError
          nil
        end

        def gem_spec_for_lex
          name = lex_gem_name
          return nil unless name

          Gem::Specification.find_by_name(name)
        rescue Gem::MissingSpecError
          nil
        end

        def log_lex_name
          if respond_to?(:segments)
            segments.join('-')
          else
            derive_log_tag
          end
        rescue StandardError
          nil
        end
      end
    end
  end
end
