# frozen_string_literal: true

require 'spec_helper'
require 'thor'
require 'tmpdir'
require 'legion/cli/skill_command'
require 'legion/chat/skills'

RSpec.describe Legion::CLI::Skill do
  let(:tmpdir) { Dir.mktmpdir('skill-test') }
  let(:skill_dir) { File.join(tmpdir, '.legion', 'skills') }

  let(:sample_skill) do
    <<~SKILL
      ---
      name: review
      description: Review code for quality
      model: claude-sonnet
      tools: [read_file, search_content]
      ---

      Review the code and provide feedback on quality, security, and style.
    SKILL
  end

  before do
    FileUtils.mkdir_p(skill_dir)
    File.write(File.join(skill_dir, 'review.md'), sample_skill)
    stub_const('Legion::Chat::Skills::SKILL_DIRS', [File.join(tmpdir, '.legion/skills')])
  end

  after { FileUtils.rm_rf(tmpdir) }

  describe '#list' do
    it 'shows skill name with slash prefix' do
      expect { described_class.start(%w[list]) }.to output(%r{/review}).to_stdout
    end

    it 'shows skill description' do
      expect { described_class.start(%w[list]) }.to output(/Review code for quality/).to_stdout
    end

    it 'shows model and tools' do
      expect { described_class.start(%w[list]) }.to output(/claude-sonnet/).to_stdout
    end

    context 'with no skills' do
      before { FileUtils.rm(File.join(skill_dir, 'review.md')) }

      it 'shows no skills message' do
        expect { described_class.start(%w[list]) }.to output(/No skills found/).to_stdout
      end
    end
  end

  describe '#show' do
    it 'shows skill name' do
      expect { described_class.start(%w[show review]) }.to output(/Name: review/).to_stdout
    end

    it 'shows prompt content' do
      expect { described_class.start(%w[show review]) }.to output(/Review the code/).to_stdout
    end

    it 'shows tools list' do
      expect { described_class.start(%w[show review]) }.to output(/read_file, search_content/).to_stdout
    end

    context 'with nonexistent skill' do
      it 'shows not found message' do
        expect { described_class.start(%w[show nonexistent]) }.to output(/not found/).to_stdout
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
        File.write(File.join(dir, 'existing.md'), sample_skill)
      end

      after { FileUtils.rm_rf('.legion/skills/existing.md') }

      it 'shows already exists message' do
        expect { described_class.start(%w[create existing]) }.to output(/already exists/).to_stdout
      end
    end
  end

  describe '#execute' do
    it 'executes skill and shows output on success' do
      allow(Legion::Chat::Skills).to receive(:execute)
        .and_return({ success: true, output: 'skill result here' })
      expect { described_class.start(%w[run review some-input]) }.to output(/skill result here/).to_stdout
    end

    it 'shows error when skill fails' do
      allow(Legion::Chat::Skills).to receive(:execute)
        .and_return({ success: false, error: 'something broke' })
      expect { described_class.start(%w[run review test]) }.to output(/something broke/).to_stdout
    end

    context 'with nonexistent skill' do
      it 'shows not found message' do
        expect { described_class.start(%w[run nonexistent test]) }.to output(/not found/).to_stdout
      end
    end
  end
end
