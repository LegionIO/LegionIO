# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Extensions::Helpers::Base do
  before(:all) do
    # Nested extension: Legion::Extensions::Agentic::Cognitive::Anchor
    unless defined?(Legion::Extensions::Agentic::Cognitive::Anchor::Actor::TestActor)
      module Legion
        module Extensions
          module Agentic
            module Cognitive
              module Anchor
                module Actor
                  class TestActor
                    include Legion::Extensions::Helpers::Base
                  end
                end
              end
            end
          end
        end
      end
    end

    # Flat extension: Legion::Extensions::Http (simulating lex-http)
    unless defined?(Legion::Extensions::Http::Actor::TestFlatActor)
      module Legion
        module Extensions
          module Http
            module Actor
              class TestFlatActor
                include Legion::Extensions::Helpers::Base
              end
            end
          end
        end
      end
    end
  end

  describe 'nested extension (Agentic::Cognitive::Anchor)' do
    subject { Legion::Extensions::Agentic::Cognitive::Anchor::Actor::TestActor.new }

    it 'returns segments array' do
      expect(subject.segments).to eq(%w[agentic cognitive anchor])
    end

    it 'returns lex_slug as dot-joined segments' do
      expect(subject.lex_slug).to eq('agentic.cognitive.anchor')
    end

    it 'returns log_tag as bracketed segments' do
      expect(subject.log_tag).to eq('[agentic][cognitive][anchor]')
    end

    it 'returns amqp_prefix with legion. prefix' do
      expect(subject.amqp_prefix).to eq('legion.agentic.cognitive.anchor')
    end

    it 'returns settings_path as symbol array' do
      expect(subject.settings_path).to eq(%i[agentic cognitive anchor])
    end

    it 'returns table_prefix as underscore-joined' do
      expect(subject.table_prefix).to eq('agentic_cognitive_anchor')
    end

    it 'returns lex_name as underscore-joined (backward compat)' do
      expect(subject.lex_name).to eq('agentic_cognitive_anchor')
    end
  end

  describe 'flat extension (Http)' do
    subject { Legion::Extensions::Http::Actor::TestFlatActor.new }

    it 'returns single-element segments array' do
      expect(subject.segments).to eq(['http'])
    end

    it 'returns simple lex_slug' do
      expect(subject.lex_slug).to eq('http')
    end

    it 'returns single-bracket log_tag' do
      expect(subject.log_tag).to eq('[http]')
    end

    it 'returns simple lex_name (backward compat)' do
      expect(subject.lex_name).to eq('http')
    end

    it 'returns amqp_prefix with legion. prefix' do
      expect(subject.amqp_prefix).to eq('legion.http')
    end

    it 'returns settings_path as symbol array' do
      expect(subject.settings_path).to eq([:http])
    end

    it 'returns table_prefix' do
      expect(subject.table_prefix).to eq('http')
    end
  end
end
