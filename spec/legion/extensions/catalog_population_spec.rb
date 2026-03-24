# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Catalog population at boot' do
  before { Legion::Extensions::Catalog::Registry.reset! }

  describe '.register_capabilities' do
    it 'registers capabilities from runner metadata' do
      runners = {
        pull_request: {
          extension: 'legion::extensions::github',
          extension_name: 'github',
          runner_name: 'pull_request',
          runner_class: 'Legion::Extensions::Github::Runners::PullRequest',
          class_methods: {
            close: { args: [[:keyreq, :pr_id]] },
            merge: { args: [[:keyreq, :pr_id], [:key, :strategy]] }
          }
        }
      }

      Legion::Extensions.register_capabilities('lex-github', runners)

      caps = Legion::Extensions::Catalog::Registry.capabilities
      expect(caps.length).to eq(2)
      names = caps.map(&:name)
      expect(names).to include(match(/lex-github:.*:close/))
      expect(names).to include(match(/lex-github:.*:merge/))
    end

    it 'skips methods starting with underscore' do
      runners = {
        request: {
          extension: 'legion::extensions::http',
          extension_name: 'http',
          runner_name: 'request',
          runner_class: 'Legion::Extensions::Http::Runners::Request',
          class_methods: {
            get: { args: [] },
            _internal: { args: [] }
          }
        }
      }

      Legion::Extensions.register_capabilities('lex-http', runners)

      caps = Legion::Extensions::Catalog::Registry.capabilities
      expect(caps.length).to eq(1)
      expect(caps.first.function).to eq('get')
    end

    it 'extracts parameter info from runner args' do
      runners = {
        issue: {
          extension: 'legion::extensions::jira',
          extension_name: 'jira',
          runner_name: 'issue',
          runner_class: 'Legion::Extensions::Jira::Runners::Issue',
          class_methods: {
            create: { args: [[:keyreq, :summary], [:key, :description]] }
          }
        }
      }

      Legion::Extensions.register_capabilities('lex-jira', runners)

      cap = Legion::Extensions::Catalog::Registry.capabilities.first
      expect(cap.parameters[:summary][:required]).to eq(true)
      expect(cap.parameters[:description][:required]).to eq(false)
    end
  end
end
