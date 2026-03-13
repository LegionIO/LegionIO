# frozen_string_literal: true

module Legion
  module Extensions
    module Helpers
      module Base
        def lex_class
          @lex_class ||= Kernel.const_get(calling_class_array[0..2].join('::'))
        end
        alias extension_class lex_class

        def lex_name
          @lex_name ||= calling_class_array[2].gsub(/(?<!^)[A-Z]/) { "_#{Regexp.last_match(0)}" }.downcase
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
      end
    end
  end
end
