# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'legion/cli/lex_templates'

RSpec.describe Legion::CLI::LexTemplates do
  describe '.list' do
    it 'returns all templates' do
      templates = described_class.list
      expect(templates.size).to eq(6)
      expect(templates.map { |t| t[:name] }).to include('basic', 'llm-agent', 'service-integration', 'data-pipeline')
    end

    it 'returns hashes with :name and :description keys' do
      described_class.list.each do |t|
        expect(t).to have_key(:name)
        expect(t).to have_key(:description)
      end
    end
  end

  describe '.get' do
    it 'returns template config for llm-agent' do
      config = described_class.get('llm-agent')
      expect(config[:runners]).to include('processor', 'analyzer')
      expect(config[:client]).to be true
    end

    it 'returns template config for service-integration' do
      config = described_class.get('service-integration')
      expect(config[:client]).to be true
      expect(config[:description]).to include('service')
    end

    it 'returns template config for data-pipeline' do
      config = described_class.get('data-pipeline')
      expect(config[:runners]).to include('transform')
      expect(config[:actors]).to include('ingest')
    end

    it 'returns nil for unknown' do
      expect(described_class.get('nonexistent')).to be_nil
    end
  end

  describe '.valid?' do
    it 'validates known templates' do
      expect(described_class.valid?('basic')).to be true
      expect(described_class.valid?('llm-agent')).to be true
      expect(described_class.valid?('service-integration')).to be true
      expect(described_class.valid?('data-pipeline')).to be true
    end

    it 'rejects unknown templates' do
      expect(described_class.valid?('fake')).to be false
    end
  end

  describe '.template_dir' do
    it 'returns nil for basic (no overlay)' do
      expect(described_class.template_dir('basic')).to be_nil
    end

    it 'returns a path for llm-agent' do
      dir = described_class.template_dir('llm-agent')
      expect(dir).to end_with('llm_agent')
    end

    it 'returns a path for service-integration' do
      dir = described_class.template_dir('service-integration')
      expect(dir).to end_with('service_integration')
    end

    it 'returns a path for data-pipeline' do
      dir = described_class.template_dir('data-pipeline')
      expect(dir).to end_with('data_pipeline')
    end

    it 'returns nil for unknown template' do
      expect(described_class.template_dir('nonexistent')).to be_nil
    end
  end

  describe Legion::CLI::LexTemplates::TemplateOverlay do
    let(:tmpdir) { Dir.mktmpdir }
    let(:vars) do
      { lex_class: 'MyAgent', lex_name: 'myagent', name_class: 'Myagent', gem_name: 'lex-myagent' }
    end

    after { FileUtils.remove_entry(tmpdir) }

    describe '#apply' do
      context 'with llm-agent template' do
        subject(:overlay) { described_class.new('llm-agent', tmpdir, vars) }

        before { overlay.apply }

        it 'generates the runner file' do
          expect(File.exist?(File.join(tmpdir, 'runners/myagent.rb'))).to be true
        end

        it 'generates the helpers/client.rb file' do
          expect(File.exist?(File.join(tmpdir, 'helpers/client.rb'))).to be true
        end

        it 'generates the prompts/default.yml file' do
          expect(File.exist?(File.join(tmpdir, 'prompts/default.yml'))).to be true
        end

        it 'generates the spec runner file' do
          expect(File.exist?(File.join(tmpdir, 'spec/runners/myagent_spec.rb'))).to be true
        end

        it 'substitutes lex_class in the runner' do
          content = File.read(File.join(tmpdir, 'runners/myagent.rb'))
          expect(content).to include('MyAgent')
        end
      end

      context 'with service-integration template' do
        let(:vars) do
          { lex_class: 'MyService', lex_name: 'myservice', name_class: 'Myservice', gem_name: 'lex-myservice' }
        end
        subject(:overlay) { described_class.new('service-integration', tmpdir, vars) }

        before { overlay.apply }

        it 'generates the runner file' do
          expect(File.exist?(File.join(tmpdir, 'runners/myservice.rb'))).to be true
        end

        it 'generates the helpers/client.rb file' do
          expect(File.exist?(File.join(tmpdir, 'helpers/client.rb'))).to be true
        end

        it 'generates the helpers/auth.rb file' do
          expect(File.exist?(File.join(tmpdir, 'helpers/auth.rb'))).to be true
        end

        it 'generates the spec/runners file' do
          expect(File.exist?(File.join(tmpdir, 'spec/runners/myservice_spec.rb'))).to be true
        end

        it 'generates the spec/helpers/client_spec.rb file' do
          expect(File.exist?(File.join(tmpdir, 'spec/helpers/client_spec.rb'))).to be true
        end

        it 'includes CRUD runner methods' do
          content = File.read(File.join(tmpdir, 'runners/myservice.rb'))
          %w[list get create update delete].each do |method|
            expect(content).to include("def #{method}")
          end
        end
      end

      context 'with data-pipeline template' do
        let(:vars) do
          { lex_class: 'MyPipeline', lex_name: 'mypipeline', name_class: 'Mypipeline', gem_name: 'lex-mypipeline' }
        end
        subject(:overlay) { described_class.new('data-pipeline', tmpdir, vars) }

        before { overlay.apply }

        it 'generates the transform runner' do
          expect(File.exist?(File.join(tmpdir, 'runners/transform.rb'))).to be true
        end

        it 'generates the ingest actor' do
          expect(File.exist?(File.join(tmpdir, 'actors/ingest.rb'))).to be true
        end

        it 'generates transport exchange file' do
          expect(File.exist?(File.join(tmpdir, 'transport/exchanges/mypipeline.rb'))).to be true
        end

        it 'generates transport queue file' do
          expect(File.exist?(File.join(tmpdir, 'transport/queues/ingest.rb'))).to be true
        end

        it 'generates transport message file' do
          expect(File.exist?(File.join(tmpdir, 'transport/messages/mypipeline_output.rb'))).to be true
        end

        it 'generates the transform spec' do
          expect(File.exist?(File.join(tmpdir, 'spec/runners/transform_spec.rb'))).to be true
        end

        it 'generates the ingest actor spec' do
          expect(File.exist?(File.join(tmpdir, 'spec/actors/ingest_spec.rb'))).to be true
        end
      end

      context 'with basic template (no overlay dir)' do
        subject(:overlay) { described_class.new('basic', tmpdir, vars) }

        it 'applies nothing and does not raise' do
          expect { overlay.apply }.not_to raise_error
        end
      end
    end
  end
end
