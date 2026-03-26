# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli'

RSpec.describe Legion::CLI::CodegenCommand do
  subject(:cli) { described_class.new }

  describe '#status' do
    it 'responds to status' do
      expect(cli).to respond_to(:status)
    end
  end

  describe '#list' do
    it 'responds to list' do
      expect(cli).to respond_to(:list)
    end
  end

  describe '#show' do
    it 'responds to show' do
      expect(cli).to respond_to(:show)
    end
  end

  describe '#approve' do
    it 'responds to approve' do
      expect(cli).to respond_to(:approve)
    end
  end

  describe '#reject' do
    it 'responds to reject' do
      expect(cli).to respond_to(:reject)
    end
  end

  describe '#gaps' do
    it 'responds to gaps' do
      expect(cli).to respond_to(:gaps)
    end
  end

  describe '#cycle' do
    it 'responds to cycle' do
      expect(cli).to respond_to(:cycle)
    end
  end
end
