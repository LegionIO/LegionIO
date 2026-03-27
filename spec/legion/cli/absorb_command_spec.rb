# frozen_string_literal: true

require 'spec_helper'
require 'thor'
require 'legion/cli/output'
require 'legion/cli/error'
require 'legion/extensions/absorbers'
require 'legion/extensions/actors/absorber_dispatch'
require 'legion/cli/absorb_command'

RSpec.describe Legion::CLI::AbsorbCommand do
  let(:command) { described_class.new }

  before do
    allow(Legion::Extensions::Absorbers::PatternMatcher).to receive(:list).and_return([])
    allow(Legion::Extensions::Absorbers::PatternMatcher).to receive(:resolve).and_return(nil)
    allow(Legion::Extensions::Actors::AbsorberDispatch).to receive(:dispatch).and_return(nil)
  end

  describe '.exit_on_failure?' do
    it 'returns true' do
      expect(described_class.exit_on_failure?).to be true
    end
  end

  describe '#list' do
    it 'responds to list' do
      expect(command).to respond_to(:list)
    end
  end

  describe '#url' do
    it 'responds to url' do
      expect(command).to respond_to(:url)
    end
  end

  describe '#resolve' do
    it 'responds to resolve' do
      expect(command).to respond_to(:resolve)
    end
  end
end
