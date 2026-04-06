# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Catalog population at boot' do
  describe '.register_capabilities' do
    it 'is a no-op (replaced by Tools::Discovery)' do
      runners = {
        pull_request: {
          extension:      'legion::extensions::github',
          extension_name: 'github',
          runner_name:    'pull_request',
          runner_class:   'Legion::Extensions::Github::Runners::PullRequest',
          class_methods:  {
            close: { args: [%i[keyreq pr_id]] }
          }
        }
      }

      expect { Legion::Extensions.register_capabilities('lex-github', runners) }.not_to raise_error
    end
  end
end
