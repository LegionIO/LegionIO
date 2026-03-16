# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli/chat/context'

RSpec.describe Legion::CLI::Chat::Context do
  let(:project_root) { File.expand_path('../../../..', __dir__) }

  describe '.detect' do
    it 'returns a hash with project info' do
      ctx = described_class.detect(project_root)
      expect(ctx).to be_a(Hash)
      expect(ctx).to have_key(:project_type)
      expect(ctx).to have_key(:directory)
    end

    it 'detects ruby projects' do
      ctx = described_class.detect(project_root)
      expect(ctx[:project_type]).to eq(:ruby)
    end
  end

  describe '.to_system_prompt' do
    it 'returns a string' do
      result = described_class.to_system_prompt(project_root)
      expect(result).to be_a(String)
      expect(result).to include('Legion')
    end

    it 'includes working directory' do
      result = described_class.to_system_prompt(project_root)
      expect(result).to include(project_root)
    end
  end
end
