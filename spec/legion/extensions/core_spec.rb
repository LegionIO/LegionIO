# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Extensions::Core do
  describe '.trigger_words' do
    it 'defaults to lex name segments derived from the module name' do
      stub_const('Legion::Extensions::Github', Module.new { extend Legion::Extensions::Core })
      expect(Legion::Extensions::Github.trigger_words).to eq(['github'])
    end

    it 'splits compound lex names into individual words' do
      stub_const('Legion::Extensions::IdentityLdap', Module.new { extend Legion::Extensions::Core })
      expect(Legion::Extensions::IdentityLdap.trigger_words).to eq(%w[identity ldap])
    end

    it 'returns explicit trigger_words unchanged when overridden' do
      mod = Module.new do
        extend Legion::Extensions::Core

        def self.trigger_words
          %w[custom words]
        end
      end
      expect(mod.trigger_words).to eq(%w[custom words])
    end
  end
end
