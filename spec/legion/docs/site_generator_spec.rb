# frozen_string_literal: true

require 'spec_helper'
require 'legion/docs/site_generator'
require 'tmpdir'

RSpec.describe Legion::Docs::SiteGenerator do
  describe '#generate' do
    it 'creates output directory and index' do
      Dir.mktmpdir do |dir|
        gen = described_class.new(output_dir: dir)
        result = gen.generate
        expect(result[:output]).to eq(dir)
        expect(File.exist?(File.join(dir, 'index.md'))).to be true
      end
    end

    it 'returns section count' do
      Dir.mktmpdir do |dir|
        gen = described_class.new(output_dir: dir)
        result = gen.generate
        expect(result[:sections]).to eq(5)
      end
    end
  end
end
