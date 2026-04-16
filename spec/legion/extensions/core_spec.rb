# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Extensions::Core do
  describe '.sticky_tools?' do
    it 'returns true by default' do
      stub_const('Legion::Extensions::StickyTest', Module.new { extend Legion::Extensions::Core })
      expect(Legion::Extensions::StickyTest.sticky_tools?).to eq(true)
    end

    it 'can be overridden to false on extension module' do
      mod = Module.new do
        extend Legion::Extensions::Core
        def self.sticky_tools?
          false
        end
      end
      expect(mod.sticky_tools?).to eq(false)
    end
  end

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
