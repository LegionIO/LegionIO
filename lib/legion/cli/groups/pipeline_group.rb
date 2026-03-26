# frozen_string_literal: true

require 'thor'

module Legion
  module CLI
    module Groups
      class Pipeline < Thor
        namespace 'pipeline'

        def self.exit_on_failure?
          true
        end

        desc 'skill', 'Manage skills (.legion/skills/ markdown files)'
        subcommand 'skill', Legion::CLI::Skill

        desc 'prompt SUBCOMMAND', 'Manage versioned LLM prompt templates'
        subcommand 'prompt', Legion::CLI::Prompt

        desc 'eval SUBCOMMAND', 'Eval gating and experiment management'
        subcommand 'eval', Legion::CLI::Eval

        desc 'dataset SUBCOMMAND', 'Manage versioned datasets'
        subcommand 'dataset', Legion::CLI::Dataset

        desc 'image SUBCOMMAND', 'Multimodal image analysis and comparison'
        subcommand 'image', Legion::CLI::Image

        desc 'notebook', 'Read and export Jupyter notebooks'
        subcommand 'notebook', Legion::CLI::Notebook
      end
    end
  end
end
