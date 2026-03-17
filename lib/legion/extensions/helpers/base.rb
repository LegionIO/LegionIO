# frozen_string_literal: true

module Legion
  module Extensions
    module Helpers
      module Base
        # Words that mark the boundary between extension namespace segments and
        # internal module structure. Segment extraction stops at these words.
        NAMESPACE_BOUNDARIES = %w[Actor Actors Runners Helpers Transport Data].freeze

        def segments
          @segments ||= derive_segments_from_namespace
        end

        def lex_slug
          segments.join('.')
        end

        def log_tag
          Helpers::Segments.segments_to_log_tag(segments)
        end

        def amqp_prefix
          Helpers::Segments.segments_to_amqp_prefix(segments)
        end

        def settings_path
          Helpers::Segments.segments_to_settings_path(segments)
        end

        def table_prefix
          Helpers::Segments.segments_to_table_prefix(segments)
        end

        def lex_class
          @lex_class ||= Kernel.const_get(calling_class_array[0..2].join('::'))
        end
        alias extension_class lex_class

        def lex_name
          segments.join('_')
        end
        alias extension_name lex_name
        alias lex_filename lex_name

        def lex_const
          @lex_const ||= calling_class_array[2]
        end

        def calling_class
          @calling_class ||= respond_to?(:ancestors) ? ancestors.first : self.class
        end

        def calling_class_array
          @calling_class_array ||= calling_class.to_s.split('::')
        end

        def actor_class
          calling_class
        end

        def actor_name
          @actor_name ||= calling_class_array.last.gsub(/(?<!^)[A-Z]/) { "_#{Regexp.last_match(0)}" }.downcase
        end

        def actor_const
          @actor_const ||= calling_class_array.last
        end

        def runner_class
          @runner_class ||= Kernel.const_get(actor_class.to_s.sub!('Actor', 'Runners'))
        end

        def runner_name
          @runner_name ||= runner_class.to_s.split('::').last.gsub(/(?<!^)[A-Z]/) { "_#{Regexp.last_match(0)}" }.downcase
        end

        def runner_const
          @runner_const ||= runner_class.to_s.split('::').last
        end

        def full_path
          @full_path ||= "#{Gem::Specification.find_by_name("lex-#{lex_name}").gem_dir}/lib/legion/extensions/#{lex_filename}"
        end
        alias extension_path full_path

        def from_json(string)
          Legion::JSON.load(string)
        end

        def normalize(thing)
          if thing.is_a? String
            to_json(from_json(thing))
          else
            from_json(to_json(thing))
          end
        end

        def to_dotted_hash(hash, recursive_key = '')
          hash.each_with_object({}) do |(k, v), ret|
            key = recursive_key + k.to_s
            if v.is_a? Hash
              ret.merge! to_dotted_hash(v, "#{key}.")
            else
              ret[key.to_sym] = v
            end
          end
        end

        private

        def derive_segments_from_namespace
          parts = calling_class_array
          ext_idx = parts.index('Extensions')
          return [camelize_to_snake(parts[0])] unless ext_idx

          ext_parts = []
          ((ext_idx + 1)...parts.length).each do |i|
            break if NAMESPACE_BOUNDARIES.include?(parts[i])

            ext_parts << camelize_to_snake(parts[i])
          end
          ext_parts.empty? ? [parts[ext_idx + 1].downcase] : ext_parts
        end

        def camelize_to_snake(str)
          str.gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
             .gsub(/([a-z\d])([A-Z])/, '\1_\2')
             .downcase
        end
      end
    end
  end
end
