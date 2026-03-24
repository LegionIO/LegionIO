# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Catalog unregister on extension unload' do
  before { Legion::Extensions::Catalog::Registry.reset! }

  describe '.unregister_capabilities' do
    it 'removes all capabilities for an extension' do
      runners = {
        pull_request: {
          extension: 'legion::extensions::github',
          extension_name: 'github',
          runner_name: 'pull_request',
          runner_class: 'Legion::Extensions::Github::Runners::PullRequest',
          class_methods: {
            close: { args: [[:keyreq, :pr_id]] },
            merge: { args: [[:keyreq, :pr_id]] }
          }
        }
      }

      Legion::Extensions.register_capabilities('lex-github', runners)
      expect(Legion::Extensions::Catalog::Registry.count).to eq(2)

      Legion::Extensions.unregister_capabilities('lex-github')
      expect(Legion::Extensions::Catalog::Registry.count).to eq(0)
    end

    it 'does not remove capabilities from other extensions' do
      runners_gh = {
        pull_request: {
          extension_name: 'github', runner_name: 'pull_request',
          runner_class: 'Legion::Extensions::Github::Runners::PullRequest',
          class_methods: { close: { args: [] } }
        }
      }
      runners_jira = {
        issue: {
          extension_name: 'jira', runner_name: 'issue',
          runner_class: 'Legion::Extensions::Jira::Runners::Issue',
          class_methods: { create: { args: [] } }
        }
      }

      Legion::Extensions.register_capabilities('lex-github', runners_gh)
      Legion::Extensions.register_capabilities('lex-jira', runners_jira)
      expect(Legion::Extensions::Catalog::Registry.count).to eq(2)

      Legion::Extensions.unregister_capabilities('lex-github')
      expect(Legion::Extensions::Catalog::Registry.count).to eq(1)
      expect(Legion::Extensions::Catalog::Registry.capabilities.first.extension).to eq('lex-jira')
    end
  end
end
