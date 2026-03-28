# frozen_string_literal: true

require 'spec_helper'
require 'legion/extensions/absorbers/transport'

RSpec.describe Legion::Extensions::Absorbers::Transport do
  describe '.build_message' do
    let(:record) do
      {
        absorb_id: 'absorb:test-123',
        input:     'https://example.com/item/1',
        context:   { depth: 0, max_depth: 5, ancestor_chain: [], conversation_id: 'conv-1' },
        metadata:  {}
      }
    end

    it 'builds a message with correct exchange and routing key' do
      msg = described_class.build_message(
        lex_name:      'example',
        absorber_name: 'content',
        record:        record
      )
      expect(msg[:exchange]).to eq('lex.example')
      expect(msg[:routing_key]).to eq('lex.example.absorbers.content.absorb')
      expect(msg[:payload][:type]).to eq('absorb.request')
      expect(msg[:payload][:absorb_id]).to eq('absorb:test-123')
    end

    it 'sets url field for http inputs' do
      msg = described_class.build_message(
        lex_name: 'example', absorber_name: 'content', record: record
      )
      expect(msg[:payload][:url]).to eq('https://example.com/item/1')
      expect(msg[:payload][:file_path]).to be_nil
    end

    it 'sets file_path field for non-http inputs' do
      file_record = record.merge(input: '/home/user/doc.pdf')
      msg = described_class.build_message(
        lex_name: 'example', absorber_name: 'content', record: file_record
      )
      expect(msg[:payload][:file_path]).to eq('/home/user/doc.pdf')
      expect(msg[:payload][:url]).to be_nil
    end
  end

  describe '.lex_name_from_absorber_class' do
    it 'extracts lex_name from a Legion::Extensions namespace' do
      klass = double(name: 'Legion::Extensions::MicrosoftTeams::Absorbers::Meeting')
      expect(described_class.lex_name_from_absorber_class(klass)).to eq('microsoft_teams')
    end

    it 'extracts lex_name from a Lex namespace' do
      klass = double(name: 'Lex::Example::Absorbers::Content')
      expect(described_class.lex_name_from_absorber_class(klass)).to eq('example')
    end
  end

  describe '.absorber_name_from_class' do
    it 'returns snake_case class name' do
      klass = double(name: 'Legion::Extensions::MicrosoftTeams::Absorbers::Meeting')
      expect(described_class.absorber_name_from_class(klass)).to eq('meeting')
    end
  end
end
