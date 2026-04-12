# frozen_string_literal: true

require 'spec_helper'
require 'thor'
require 'tmpdir'
require 'legion/cli/skill_command'

RSpec.describe Legion::CLI::Skill do
  let(:ok_skills_response) do
    double(:response,
           is_a?: true,
           body: Legion::JSON.dump({
                                     data: [
                                       { namespace: 'superpowers', name: 'brainstorming',
                                         trigger: 'on_demand', description: 'Brainstorm ideas' }
                                     ],
                                     meta: {}
                                   }))
  end

  let(:not_found_response) do
    double(:response, is_a?: false, code: '404', body: '{"error":{"code":"not_found"}}')
  end

  before do
    allow_any_instance_of(described_class).to receive(:daemon_get).and_return(ok_skills_response)
    allow(ok_skills_response).to receive(:is_a?).with(::Net::HTTPSuccess).and_return(true)
    allow(not_found_response).to receive(:is_a?).with(::Net::HTTPSuccess).and_return(false)
  end

  describe '#list' do
    it 'shows namespace:name format' do
      expect { described_class.start(%w[list]) }.to output(/superpowers:brainstorming/).to_stdout
    end

    it 'shows trigger type' do
      expect { described_class.start(%w[list]) }.to output(/on_demand/).to_stdout
    end

    it 'shows description' do
      expect { described_class.start(%w[list]) }.to output(/Brainstorm ideas/).to_stdout
    end

    context 'with empty skill list' do
      before do
        empty_response = double(:response, body: Legion::JSON.dump({ data: [], meta: {} }))
        allow(empty_response).to receive(:is_a?).with(::Net::HTTPSuccess).and_return(true)
        allow_any_instance_of(described_class).to receive(:daemon_get).and_return(empty_response)
      end

      it 'shows no skills message' do
        expect { described_class.start(%w[list]) }.to output(/No skills registered/).to_stdout
      end
    end
  end

  describe '#show' do
    let(:show_response) do
      double(:response,
             body: Legion::JSON.dump({
                                       data: {
                                         namespace: 'superpowers', name: 'brainstorming',
                                         description: 'Brainstorm ideas', trigger: 'on_demand',
                                         steps: ['ideate']
                                       },
                                       meta: {}
                                     }))
    end

    before do
      allow(show_response).to receive(:is_a?).with(::Net::HTTPSuccess).and_return(true)
      allow_any_instance_of(described_class).to receive(:daemon_get)
        .with('/api/skills/superpowers/brainstorming').and_return(show_response)
    end

    it 'shows skill namespace:name' do
      expect { described_class.start(%w[show superpowers:brainstorming]) }.to output(/superpowers:brainstorming/).to_stdout
    end

    it 'shows description' do
      expect { described_class.start(%w[show superpowers:brainstorming]) }.to output(/Brainstorm ideas/).to_stdout
    end

    context 'with nonexistent skill' do
      before do
        allow_any_instance_of(described_class).to receive(:daemon_get).and_return(not_found_response)
      end

      it 'shows not found message' do
        expect { described_class.start(%w[show unknown:nope]) }.to output(/not found/).to_stdout
      end
    end
  end

  describe '#create' do
    it 'creates skill file in .legion/skills/' do
      described_class.start(%w[create new-skill])
      path = '.legion/skills/new-skill.md'
      expect(File).to exist(path)
      content = File.read(path)
      expect(content).to include('name: new-skill')
      FileUtils.rm_rf('.legion/skills/new-skill.md')
    end

    context 'when skill already exists' do
      before do
        dir = '.legion/skills'
        FileUtils.mkdir_p(dir)
        File.write(File.join(dir, 'existing.md'), '---')
      end

      after { FileUtils.rm_rf('.legion/skills/existing.md') }

      it 'shows already exists message' do
        expect { described_class.start(%w[create existing]) }.to output(/already exists/).to_stdout
      end
    end
  end
end
