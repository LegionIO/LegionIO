# frozen_string_literal: true

require 'spec_helper'
require 'legion/extensions/builders/skills'

RSpec.describe Legion::Extensions::Builder::Skills do
  let(:extension_module) do
    mod = Module.new
    mod.extend(described_class)
    allow(mod).to receive(:lex_class).and_return(mod)
    allow(mod).to receive(:find_files).with('skills').and_return([])
    allow(mod).to receive(:require_files)
    mod
  end

  describe '#build_skills' do
    context 'when legion-llm is not loaded' do
      it 'returns nil without error' do
        hide_const('Legion::LLM::Skills')
        expect { extension_module.build_skills }.not_to raise_error
      end
    end

    context 'when skills directory is empty' do
      it 'registers nothing' do
        llm_mod = Module.new do
          def self.started?; true; end

          def self.settings; { skills: { enabled: true } }; end
        end
        stub_const('Legion::LLM', llm_mod)
        stub_const('Legion::LLM::Skills', Module.new)
        allow(extension_module).to receive(:find_files).with('skills').and_return([])
        extension_module.build_skills
        expect(extension_module.instance_variable_get(:@skills)).to eq({})
      end
    end
  end
end
