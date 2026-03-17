# frozen_string_literal: true

module Legion
  module CLI
    module LexTemplates
      REGISTRY = {
        'basic'               => {
          runners:      ['default'],
          actors:       ['subscription'],
          tools:        [],
          client:       false,
          dependencies: [],
          description:  'Basic extension with subscription actor'
        },
        'llm-agent'           => {
          runners:      %w[processor analyzer],
          actors:       %w[subscription polling],
          tools:        %w[process analyze],
          client:       true,
          dependencies: ['legion-llm'],
          description:  'LLM-powered agent extension'
        },
        'service-integration' => {
          runners:      ['operations'],
          actors:       ['subscription'],
          tools:        [],
          client:       true,
          dependencies: [],
          description:  'External service integration with standalone client'
        },
        'scheduled-task'      => {
          runners:      ['executor'],
          actors:       ['interval'],
          tools:        [],
          client:       false,
          dependencies: [],
          description:  'Scheduled task with interval actor'
        },
        'webhook-handler'     => {
          runners:      %w[handler validator],
          actors:       ['subscription'],
          tools:        [],
          client:       false,
          dependencies: [],
          description:  'Inbound webhook processing'
        }
      }.freeze

      class << self
        def list
          REGISTRY.map { |name, config| { name: name, description: config[:description] } }
        end

        def get(name)
          REGISTRY[name.to_s]
        end

        def valid?(name)
          REGISTRY.key?(name.to_s)
        end
      end
    end
  end
end
