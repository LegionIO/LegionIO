# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

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

  describe '.autobuild' do
    it 'builds extension data when migrations exist even if data_required? is false' do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, 'data', 'migrations'))
        File.write(File.join(dir, 'data', 'migrations', '001_create_test_table.rb'), '# migration')

        stub_const('Legion::Extensions::MigrationProbe', Module.new { extend Legion::Extensions::Core })
        allow(Legion::Extensions::MigrationProbe).to receive(:extension_path).and_return(dir)
        allow(Legion::Extensions::MigrationProbe).to receive(:build_settings)
        allow(Legion::Extensions::MigrationProbe).to receive(:build_transport)
        allow(Legion::Extensions::MigrationProbe).to receive(:build_data)
        allow(Legion::Extensions::MigrationProbe).to receive(:build_helpers)
        allow(Legion::Extensions::MigrationProbe).to receive(:build_runners)
        allow(Legion::Extensions::MigrationProbe).to receive(:generate_messages_from_definitions)
        allow(Legion::Extensions::MigrationProbe).to receive(:build_absorbers)
        allow(Legion::Extensions::MigrationProbe).to receive(:build_actors)
        allow(Legion::Extensions::MigrationProbe).to receive(:build_hooks)
        allow(Legion::Extensions::MigrationProbe).to receive(:build_routes)
        allow(Legion::Settings).to receive(:[]).with(:data).and_return({ connected: true })

        Legion::Extensions::MigrationProbe.autobuild

        expect(Legion::Extensions::MigrationProbe).to have_received(:build_data)
      end
    end
  end
end
