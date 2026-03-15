# frozen_string_literal: true

require 'thor'
require 'legion/cli/output'

module Legion
  module CLI
    class Swarm < Thor
      def self.exit_on_failure?
        true
      end

      class_option :json,       type: :boolean, default: false, desc: 'Output as JSON'
      class_option :no_color,   type: :boolean, default: false, desc: 'Disable color output'
      class_option :verbose,    type: :boolean, default: false, aliases: ['-V'], desc: 'Verbose logging'
      class_option :config_dir, type: :string,  desc: 'Config directory path'
      class_option :model,      type: :string,  aliases: ['-m'], desc: 'Default model for agents'

      WORKFLOW_DIR = '.legion/swarms'

      desc 'start NAME', 'Start a swarm workflow'
      def start(name)
        out = formatter
        workflow = load_workflow(name)

        out.header("Swarm: #{workflow['name'] || name}")
        puts out.dim("  Goal: #{workflow['goal']}")
        puts out.dim("  Agents: #{workflow['agents']&.length || 0}")
        puts out.dim("  Pipeline: #{workflow['pipeline']&.join(' -> ')}")
        puts

        run_workflow(workflow, out)
      end

      desc 'list', 'List available swarm workflows'
      def list
        out = formatter
        dir = File.join(Dir.pwd, WORKFLOW_DIR)

        unless Dir.exist?(dir)
          out.warn("No workflows found. Create them in #{WORKFLOW_DIR}/")
          return
        end

        files = Dir.glob(File.join(dir, '*.json'))
        if files.empty?
          out.warn("No workflow files found in #{WORKFLOW_DIR}/")
          return
        end

        out.header("Swarm Workflows (#{files.length})")
        files.each do |f|
          name = File.basename(f, '.json')
          workflow = parse_workflow_file(f)
          goal = workflow&.dig('goal') || '(no goal)'
          puts "  #{name}  — #{goal}"
        end
      end

      desc 'show NAME', 'Show details of a swarm workflow'
      def show(name)
        out = formatter
        workflow = load_workflow(name)

        if options[:json]
          out.json(workflow)
        else
          out.header("Workflow: #{workflow['name'] || name}")
          puts "  Goal: #{workflow['goal']}"
          puts
          (workflow['agents'] || []).each do |agent|
            puts "  #{out.colorize(agent['role'], :accent)}"
            puts "    #{agent['description']}"
            puts "    Tools: #{agent['tools']&.join(', ') || 'all'}"
            puts "    Model: #{agent['model'] || 'default'}"
            puts
          end
          puts "  Pipeline: #{workflow['pipeline']&.join(' -> ')}"
        end
      end

      no_commands do
        def formatter
          @formatter ||= Output::Formatter.new(
            json:  options[:json],
            color: !options[:no_color]
          )
        end

        def load_workflow(name)
          path = File.join(Dir.pwd, WORKFLOW_DIR, "#{name}.json")
          raise CLI::Error, "Workflow not found: #{path}. Create it in #{WORKFLOW_DIR}/#{name}.json" unless File.exist?(path)

          parse_workflow_file(path)
        end

        def parse_workflow_file(path)
          require 'json'
          ::JSON.parse(File.read(path, encoding: 'utf-8'))
        rescue ::JSON::ParserError => e
          raise CLI::Error, "Invalid workflow JSON in #{path}: #{e.message}"
        end

        def run_workflow(workflow, out)
          require 'legion/cli/chat/subagent'
          pipeline = workflow['pipeline'] || []
          agents_map = (workflow['agents'] || []).to_h { |a| [a['role'], a] }

          previous_output = workflow['goal']

          pipeline.each_with_index do |role, idx|
            agent_def = agents_map[role]
            unless agent_def
              out.error("No agent defined for role: #{role}")
              break
            end

            step = idx + 1
            out.header("Step #{step}/#{pipeline.length}: #{role}")
            puts out.dim("  #{agent_def['description']}")

            task = <<~TASK
              You are a #{role} agent. Your task:
              #{agent_def['description']}

              Context from previous step:
              #{previous_output}

              Produce clear, structured output for the next agent in the pipeline.
            TASK

            result = Chat::Subagent.send(:run_headless,
                                         task:  task,
                                         model: agent_def['model'] || options[:model])

            if result[:exit_code]&.zero? && result[:output]
              previous_output = result[:output]
              out.success("#{role} complete (#{result[:output].length} chars)")
            else
              out.error("#{role} failed: #{result[:error] || 'unknown error'}")
              break
            end
          end

          puts
          out.header('Swarm Complete')
          puts previous_output
        end
      end
    end
  end
end
