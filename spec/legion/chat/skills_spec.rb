# frozen_string_literal: true

require 'spec_helper'
require 'legion/chat/skills'
require 'tmpdir'

RSpec.describe Legion::Chat::Skills do
  describe '.discover' do
    context 'when LLM::Skills is not available' do
      it 'returns empty array when no skill dirs exist' do
        hide_const('Legion::LLM::Skills')
        allow(described_class).to receive(:skill_directories).and_return([])
        expect(described_class.discover).to eq([])
      end

      it 'returns basenames from skill directories' do
        hide_const('Legion::LLM::Skills')
        Dir.mktmpdir do |dir|
          File.write(File.join(dir, 'one.md'), 'content')
          File.write(File.join(dir, 'two.rb'), 'content')
          allow(described_class).to receive(:skill_directories).and_return([dir])
          expect(described_class.discover).to contain_exactly('one', 'two')
        end
      end
    end

    context 'when LLM::Skills is available and started' do
      it 'delegates to Registry.all' do
        registry_mod = Module.new { def self.all = [:skill_a] }
        llm_mod = Module.new { def self.started? = true }
        stub_const('Legion::LLM', llm_mod)
        stub_const('Legion::LLM::Skills', Module.new)
        stub_const('Legion::LLM::Skills::Registry', registry_mod)
        expect(described_class.discover).to eq([:skill_a])
      end
    end
  end

  describe '.find' do
    context 'when LLM::Skills is not available' do
      it 'returns nil when skill not found in file system' do
        hide_const('Legion::LLM::Skills')
        allow(described_class).to receive(:skill_directories).and_return([])
        expect(described_class.find('nonexistent')).to be_nil
      end

      it 'returns path when skill file found' do
        hide_const('Legion::LLM::Skills')
        Dir.mktmpdir do |dir|
          path = File.join(dir, 'target.md')
          File.write(path, 'content')
          allow(described_class).to receive(:skill_directories).and_return([dir])
          expect(described_class.find('target')).to eq(path)
        end
      end
    end

    context 'when LLM::Skills is available and started' do
      it 'delegates to Registry.find' do
        skill_class = double('SkillClass')
        registry_mod = Module.new
        allow(registry_mod).to receive(:find).with('my_skill').and_return(skill_class)
        llm_mod = Module.new { def self.started? = true }
        stub_const('Legion::LLM', llm_mod)
        stub_const('Legion::LLM::Skills', Module.new)
        stub_const('Legion::LLM::Skills::Registry', registry_mod)
        expect(described_class.find('my_skill')).to eq(skill_class)
      end
    end
  end
end
