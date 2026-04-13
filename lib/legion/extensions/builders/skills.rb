# frozen_string_literal: true

require_relative 'base'

module Legion
  module Extensions
    module Builder
      module Skills
        include Legion::Extensions::Builder::Base

        attr_reader :skills

        def build_skills
          return unless Object.const_defined?('Legion::LLM::Skills', false)
          return unless Object.const_defined?('Legion::LLM', false) &&
                        Legion::LLM.respond_to?(:started?) && Legion::LLM.started?
          return if Legion::LLM.settings.dig(:skills, :enabled) == false

          @skills = {}
          lex_mod = lex_class.is_a?(::Module) ? lex_class : ::Kernel.const_get(lex_class.to_s)
          lex_mod.const_set(:Skills, ::Module.new) unless lex_mod.const_defined?(:Skills, false)
          require_files(skill_files)
          build_skill_list
        end

        def build_skill_list
          skill_files.each do |file|
            skill_name       = file.split('/').last.sub('.rb', '')
            skill_class_name = "#{lex_class}::Skills::#{skill_name.split('_').collect(&:capitalize).join}"
            loaded_skill     = Kernel.const_get(skill_class_name)
            Legion::LLM::Skills::Registry.register(loaded_skill)
            @skills[skill_name.to_sym] = {
              skill_class:  skill_class_name,
              skill_module: loaded_skill
            }
            Legion::Logging.debug "[Skills] registered: #{skill_class_name}" if defined?(Legion::Logging)
          end
        end

        def skill_files
          @skill_files ||= find_files('skills')
        end
      end
    end
  end
end
