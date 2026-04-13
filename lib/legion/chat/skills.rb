# frozen_string_literal: true

module Legion
  module Chat
    module Skills
      class << self
        def discover
          return file_discover unless llm_skills_available?

          Legion::LLM::Skills::Registry.all.map { |s| registry_descriptor(s) }
        end

        def find(name)
          return file_find(name) unless llm_skills_available?

          skill = Legion::LLM::Skills::Registry.find(name)
          skill ? registry_descriptor(skill) : nil
        end

        # execute: REMOVED — all skill execution routes through the daemon API.
        # `legion skill run` / `legion chat` are thin HTTP clients; no local LLM boot.

        private

        def llm_skills_available?
          defined?(Legion::LLM::Skills) &&
            Legion::LLM.respond_to?(:started?) &&
            Legion::LLM.started?
        end

        def registry_descriptor(skill)
          { name: skill.skill_name, namespace: skill.namespace, prompt: nil,
            description: skill.description, source: :registry }
        end

        def file_discover
          dirs = skill_directories
          dirs.flat_map { |dir| ::Dir.glob(::File.join(dir, '*.{md,rb,yml,yaml}')) }
              .map { |f| { name: ::File.basename(f, '.*'), path: f, source: :file } }
        end

        def file_find(name)
          dirs = skill_directories
          dirs.each do |dir|
            %w[.md .rb .yml .yaml].each do |ext|
              path = ::File.join(dir, "#{name}#{ext}")
              next unless ::File.exist?(path)

              return { name: name, path: path, prompt: ::File.read(path), source: :file }
            end
          end
          nil
        end

        def skill_directories
          [
            ::File.expand_path('.legion/skills'),
            ::File.expand_path('~/.legionio/skills')
          ].select { |d| ::File.directory?(d) }
        end
      end
    end
  end
end
