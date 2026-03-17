# frozen_string_literal: true

require 'thor'

module Legion
  module CLI
    class Skill < Thor
      def self.exit_on_failure?
        true
      end

      desc 'list', 'List all discovered skills'
      def list
        require 'legion/chat/skills'
        skills = Legion::Chat::Skills.discover
        if skills.empty?
          say 'No skills found. Create skills in .legion/skills/ or ~/.legionio/skills/'
          return
        end

        skills.each do |s|
          say "  /#{s[:name]} — #{s[:description]}", :green
          say "    model: #{s[:model] || 'default'}, tools: #{s[:tools].empty? ? 'none' : s[:tools].join(', ')}"
        end
      end

      desc 'show NAME', 'Display skill definition'
      def show(name)
        require 'legion/chat/skills'
        skill = Legion::Chat::Skills.find(name)
        if skill
          say "Name: #{skill[:name]}", :green
          say "Description: #{skill[:description]}"
          say "Model: #{skill[:model] || 'default'}"
          say "Tools: #{skill[:tools].empty? ? 'none' : skill[:tools].join(', ')}"
          say "Path: #{skill[:path]}"
          say "\n--- Prompt ---\n#{skill[:prompt]}"
        else
          say "Skill '#{name}' not found", :red
        end
      end

      desc 'create NAME', 'Scaffold a new skill file'
      def create(name)
        dir = '.legion/skills'
        FileUtils.mkdir_p(dir)
        path = File.join(dir, "#{name}.md")

        if File.exist?(path)
          say "Skill already exists: #{path}", :red
          return
        end

        content = <<~SKILL
          ---
          name: #{name}
          description: Describe what this skill does
          model:
          tools: []
          ---

          You are a helpful assistant. Describe the skill's behavior here.
        SKILL

        File.write(path, content)
        say "Created: #{path}", :green
      end

      desc 'execute NAME [INPUT]', 'Run a skill outside of chat'
      map 'run' => :execute
      def execute(name, *input)
        require 'legion/chat/skills'
        skill = Legion::Chat::Skills.find(name)
        unless skill
          say "Skill '#{name}' not found", :red
          return
        end

        say "Skill: #{skill[:name]}", :green
        say "Prompt: #{skill[:prompt]&.slice(0, 80)}..."
        say "Input: #{input.join(' ')}"
        say "\nNote: Full skill execution requires an active chat session. Use `/#{name}` in `legion chat`."
      end
    end
  end
end
