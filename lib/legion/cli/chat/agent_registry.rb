# frozen_string_literal: true

module Legion
  module CLI
    class Chat
      module AgentRegistry
        AGENT_DIR = '.legion/agents'
        SUPPORTED_EXTENSIONS = %w[.json .yml .yaml].freeze

        @agents = {}

        class << self
          attr_reader :agents

          def load_agents(base_dir = Dir.pwd)
            @agents = {}
            dir = File.join(base_dir, AGENT_DIR)
            return @agents unless Dir.exist?(dir)

            Dir.glob(File.join(dir, '*')).each do |path|
              ext = File.extname(path)
              next unless SUPPORTED_EXTENSIONS.include?(ext)

              agent = parse_file(path)
              next unless agent && agent['name']

              @agents[agent['name']] = normalize(agent, path)
            end

            @agents
          end

          def find(name)
            @agents[name]
          end

          def names
            @agents.keys
          end

          def list
            @agents.values
          end

          def match_for_task(task_description)
            return nil if @agents.empty?

            @agents.values.max_by do |agent|
              score = 0
              keywords = (agent[:description] || '').downcase.split(/\W+/)
              task_words = task_description.downcase.split(/\W+/)
              matching = (keywords & task_words).length
              score += matching * 10
              score += (agent[:weight] || 1.0) * 5
              score
            end
          end

          private

          def parse_file(path)
            content = File.read(path, encoding: 'utf-8')
            case File.extname(path)
            when '.json'
              require 'json'
              ::JSON.parse(content)
            when '.yml', '.yaml'
              require 'yaml'
              YAML.safe_load(content, permitted_classes: [Symbol])
            end
          rescue StandardError
            nil
          end

          def normalize(raw, source_path)
            {
              name:          raw['name'],
              description:   raw['description'] || '',
              model:         raw['model'],
              system_prompt: raw['system_prompt'] || raw['prompt'],
              tools:         raw['tools'],
              weight:        (raw['weight'] || 1.0).to_f,
              conditions:    raw['conditions'] || {},
              source:        source_path
            }
          end
        end
      end
    end
  end
end
