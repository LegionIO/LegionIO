# frozen_string_literal: true

require 'spec_helper'
require 'legion/service'
require 'legion/apollo'

RSpec.describe Legion::Service do
  describe '#setup_apollo' do
    let(:service) { described_class.allocate }

    context 'when legion-apollo is installed' do
      before do
        allow(Legion::Apollo).to receive(:start)
      end

      it 'calls Legion::Apollo.start' do
        expect(Legion::Apollo).to receive(:start)
        service.send(:setup_apollo)
      end

      it 'does not raise errors' do
        expect { service.send(:setup_apollo) }.not_to raise_error
      end
    end

    context 'when legion-apollo raises LoadError' do
      it 'rescues gracefully' do
        allow(service).to receive(:require).and_raise(LoadError, 'cannot load such file')
        expect { service.send(:setup_apollo) }.not_to raise_error
      end
    end

    context 'when legion-apollo raises StandardError' do
      it 'rescues gracefully' do
        allow(Legion::Apollo).to receive(:start).and_raise(StandardError, 'something went wrong')
        expect { service.send(:setup_apollo) }.not_to raise_error
      end
    end

    context 'when Apollo::Local is available' do
      before do
        stub_const('Legion::Apollo::Local', Module.new do
          extend self

          define_method(:start) { nil }
        end)
        allow(Legion::Apollo).to receive(:start)
        allow(Legion::Apollo::Local).to receive(:start)
      end

      it 'starts Apollo::Local' do
        service.send(:setup_apollo)
        expect(Legion::Apollo::Local).to have_received(:start).once
      end
    end
  end

  describe 'Readiness COMPONENTS' do
    it 'includes :apollo between :llm and :gaia' do
      components = Legion::Readiness::COMPONENTS
      llm_idx    = components.index(:llm)
      apollo_idx = components.index(:apollo)
      gaia_idx   = components.index(:gaia)

      expect(apollo_idx).not_to be_nil
      expect(apollo_idx).to be > llm_idx
      expect(apollo_idx).to be < gaia_idx
    end
  end
end
