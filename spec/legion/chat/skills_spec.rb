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

      it 'returns descriptor hashes from skill directories' do
        hide_const('Legion::LLM::Skills')
        Dir.mktmpdir do |dir|
          File.write(File.join(dir, 'one.md'), 'content')
          File.write(File.join(dir, 'two.rb'), 'content')
          allow(described_class).to receive(:skill_directories).and_return([dir])
          result = described_class.discover
          expect(result.map { |h| h[:name] }).to contain_exactly('one', 'two')
          expect(result).to all(include(source: :file))
        end
      end
    end

    context 'when LLM::Skills is available and started' do
      it 'delegates to Registry.all and returns descriptor hashes' do
        skill_class = instance_double('SkillClass',
                                      skill_name:    'brainstorming',
                                      namespace:     'superpowers',
                                      description:   'Brainstorm ideas',
                                      trigger:       'on_demand',
                                      follows_skill: nil)
        registry_mod = Module.new
        allow(registry_mod).to receive(:all).and_return([skill_class])
        llm_mod = Module.new { def self.started? = true }
        stub_const('Legion::LLM', llm_mod)
        stub_const('Legion::LLM::Skills', Module.new)
        stub_const('Legion::LLM::Skills::Registry', registry_mod)
        result = described_class.discover
        expect(result).to eq([{ name: 'brainstorming', namespace: 'superpowers',
                                prompt: nil, description: 'Brainstorm ideas',
                                source: :registry }])
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

      it 'returns descriptor hash when skill file found' do
        hide_const('Legion::LLM::Skills')
        Dir.mktmpdir do |dir|
          path = File.join(dir, 'target.md')
          File.write(path, 'content')
          allow(described_class).to receive(:skill_directories).and_return([dir])
          result = described_class.find('target')
          expect(result).to eq({ name: 'target', path: path, prompt: 'content', source: :file })
        end
      end
    end

    context 'when LLM::Skills is available and started' do
      it 'delegates to Registry.find and returns descriptor hash' do
        skill_class = instance_double('SkillClass',
                                      skill_name:    'my_skill',
                                      namespace:     'core',
                                      description:   'A skill',
                                      trigger:       'on_demand',
                                      follows_skill: nil)
        registry_mod = Module.new
        allow(registry_mod).to receive(:find).with('my_skill').and_return(skill_class)
        llm_mod = Module.new { def self.started? = true }
        stub_const('Legion::LLM', llm_mod)
        stub_const('Legion::LLM::Skills', Module.new)
        stub_const('Legion::LLM::Skills::Registry', registry_mod)
        result = described_class.find('my_skill')
        expect(result).to eq({ name: 'my_skill', namespace: 'core', prompt: nil,
                                description: 'A skill', source: :registry })
      end

      it 'returns nil when Registry.find returns nil' do
        registry_mod = Module.new
        allow(registry_mod).to receive(:find).with('missing').and_return(nil)
        llm_mod = Module.new { def self.started? = true }
        stub_const('Legion::LLM', llm_mod)
        stub_const('Legion::LLM::Skills', Module.new)
        stub_const('Legion::LLM::Skills::Registry', registry_mod)
        expect(described_class.find('missing')).to be_nil
      end
    end
  end
end
