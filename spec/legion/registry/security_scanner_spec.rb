# frozen_string_literal: true

require 'spec_helper'
require 'legion/registry/security_scanner'

RSpec.describe Legion::Registry::SecurityScanner do
  let(:scanner) { described_class.new }

  describe '#scan' do
    it 'returns result hash' do
      result = scanner.scan(name: 'lex-test')
      expect(result).to have_key(:passed)
      expect(result).to have_key(:checks)
      expect(result).to have_key(:scanned_at)
    end

    it 'passes valid naming' do
      result = scanner.scan(name: 'lex-test')
      naming = result[:checks].find { |c| c[:check] == :naming_convention }
      expect(naming[:status]).to eq(:pass)
    end

    it 'fails invalid naming' do
      result = scanner.scan(name: 'bad_name')
      naming = result[:checks].find { |c| c[:check] == :naming_convention }
      expect(naming[:status]).to eq(:fail)
    end

    it 'skips checksum without gem path' do
      result = scanner.scan(name: 'lex-test')
      checksum = result[:checks].find { |c| c[:check] == :checksum }
      expect(checksum[:status]).to eq(:skip)
    end

    it 'overall passes when no failures' do
      result = scanner.scan(name: 'lex-test')
      expect(result[:passed]).to be true
    end

    it 'overall fails when naming fails' do
      result = scanner.scan(name: 'BAD')
      expect(result[:passed]).to be false
    end
  end
end
