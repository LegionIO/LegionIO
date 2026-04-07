# frozen_string_literal: true

require 'spec_helper'
require 'legion/mode'

RSpec.describe Legion::Mode do
  before do
    ENV.delete('LEGION_MODE')
  end

  after do
    ENV.delete('LEGION_MODE')
  end

  describe '.current' do
    context 'when no ENV, settings, or legacy role is set' do
      before do
        allow(described_class).to receive(:settings_dig).and_return(nil)
      end

      it 'returns :agent by default' do
        expect(described_class.current).to eq(:agent)
      end
    end

    context 'when ENV[LEGION_MODE] is set' do
      it 'returns :agent when set to "agent"' do
        ENV['LEGION_MODE'] = 'agent'
        expect(described_class.current).to eq(:agent)
      end

      it 'returns :worker when set to "worker"' do
        ENV['LEGION_MODE'] = 'worker'
        expect(described_class.current).to eq(:worker)
      end

      it 'returns :lite when set to "lite"' do
        ENV['LEGION_MODE'] = 'lite'
        expect(described_class.current).to eq(:lite)
      end

      it 'returns :infra when set to "infra"' do
        ENV['LEGION_MODE'] = 'infra'
        expect(described_class.current).to eq(:infra)
      end

      it 'takes precedence over settings' do
        ENV['LEGION_MODE'] = 'lite'
        allow(Legion::Settings).to receive(:[]).with(:mode).and_return('worker')
        expect(described_class.current).to eq(:lite)
      end

      it 'normalizes uppercase input' do
        ENV['LEGION_MODE'] = 'WORKER'
        expect(described_class.current).to eq(:worker)
      end
    end

    context 'when Settings[:mode] is set' do
      before { ENV.delete('LEGION_MODE') }

      it 'returns the mode from Settings[:mode]' do
        allow(Legion::Settings).to receive(:[]).with(:mode).and_return('worker')
        allow(Legion::Settings).to receive(:[]).with('mode').and_return(nil)
        allow(Legion::Settings).to receive(:[]).with(:process).and_return(nil)
        allow(Legion::Settings).to receive(:[]).with('process').and_return(nil)
        expect(described_class.current).to eq(:worker)
      end
    end

    context 'when Settings[:process][:mode] is set' do
      before { ENV.delete('LEGION_MODE') }

      it 'returns the mode from Settings[:process][:mode]' do
        allow(Legion::Settings).to receive(:[]).with(:mode).and_return(nil)
        allow(Legion::Settings).to receive(:[]).with('mode').and_return(nil)
        allow(Legion::Settings).to receive(:[]).with(:process).and_return({ mode: 'infra' })
        allow(Legion::Settings).to receive(:[]).with('process').and_return(nil)
        expect(described_class.current).to eq(:infra)
      end
    end

    context 'when Settings[:process][:role] (legacy) is set' do
      before { ENV.delete('LEGION_MODE') }

      it 'maps :full to :agent via LEGACY_MAP' do
        allow(Legion::Settings).to receive(:[]).with(:mode).and_return(nil)
        allow(Legion::Settings).to receive(:[]).with('mode').and_return(nil)
        allow(Legion::Settings).to receive(:[]).with(:process).and_return({ role: 'full' })
        allow(Legion::Settings).to receive(:[]).with('process').and_return(nil)
        expect(described_class.current).to eq(:agent)
      end

      it 'maps :api to :worker via LEGACY_MAP' do
        allow(Legion::Settings).to receive(:[]).with(:mode).and_return(nil)
        allow(Legion::Settings).to receive(:[]).with('mode').and_return(nil)
        allow(Legion::Settings).to receive(:[]).with(:process).and_return({ role: 'api' })
        allow(Legion::Settings).to receive(:[]).with('process').and_return(nil)
        expect(described_class.current).to eq(:worker)
      end

      it 'maps :router to :worker via LEGACY_MAP' do
        allow(Legion::Settings).to receive(:[]).with(:mode).and_return(nil)
        allow(Legion::Settings).to receive(:[]).with('mode').and_return(nil)
        allow(Legion::Settings).to receive(:[]).with(:process).and_return({ role: 'router' })
        allow(Legion::Settings).to receive(:[]).with('process').and_return(nil)
        expect(described_class.current).to eq(:worker)
      end

      it 'maps :worker to :worker via LEGACY_MAP' do
        allow(Legion::Settings).to receive(:[]).with(:mode).and_return(nil)
        allow(Legion::Settings).to receive(:[]).with('mode').and_return(nil)
        allow(Legion::Settings).to receive(:[]).with(:process).and_return({ role: 'worker' })
        allow(Legion::Settings).to receive(:[]).with('process').and_return(nil)
        expect(described_class.current).to eq(:worker)
      end

      it 'maps :lite to :lite via LEGACY_MAP' do
        allow(Legion::Settings).to receive(:[]).with(:mode).and_return(nil)
        allow(Legion::Settings).to receive(:[]).with('mode').and_return(nil)
        allow(Legion::Settings).to receive(:[]).with(:process).and_return({ role: 'lite' })
        allow(Legion::Settings).to receive(:[]).with('process').and_return(nil)
        expect(described_class.current).to eq(:lite)
      end
    end

    context 'with unknown mode value' do
      it 'falls back to :agent for unrecognized mode' do
        ENV['LEGION_MODE'] = 'bogus_mode'
        expect(described_class.current).to eq(:agent)
      end
    end
  end

  describe 'convenience predicates' do
    describe '.agent?' do
      it 'returns true when current mode is :agent' do
        allow(described_class).to receive(:current).and_return(:agent)
        expect(described_class.agent?).to be true
      end

      it 'returns false when current mode is not :agent' do
        allow(described_class).to receive(:current).and_return(:worker)
        expect(described_class.agent?).to be false
      end
    end

    describe '.worker?' do
      it 'returns true when current mode is :worker' do
        allow(described_class).to receive(:current).and_return(:worker)
        expect(described_class.worker?).to be true
      end

      it 'returns false when current mode is not :worker' do
        allow(described_class).to receive(:current).and_return(:agent)
        expect(described_class.worker?).to be false
      end
    end

    describe '.infra?' do
      it 'returns true when current mode is :infra' do
        allow(described_class).to receive(:current).and_return(:infra)
        expect(described_class.infra?).to be true
      end

      it 'returns false when current mode is not :infra' do
        allow(described_class).to receive(:current).and_return(:agent)
        expect(described_class.infra?).to be false
      end
    end

    describe '.lite?' do
      it 'returns true when current mode is :lite' do
        allow(described_class).to receive(:current).and_return(:lite)
        expect(described_class.lite?).to be true
      end

      it 'returns false when current mode is not :lite' do
        allow(described_class).to receive(:current).and_return(:agent)
        expect(described_class.lite?).to be false
      end
    end
  end

  describe 'LEGACY_MAP' do
    it 'maps :full to :agent' do
      expect(described_class::LEGACY_MAP[:full]).to eq(:agent)
    end

    it 'maps :api to :worker' do
      expect(described_class::LEGACY_MAP[:api]).to eq(:worker)
    end

    it 'maps :router to :worker' do
      expect(described_class::LEGACY_MAP[:router]).to eq(:worker)
    end

    it 'maps :worker to :worker' do
      expect(described_class::LEGACY_MAP[:worker]).to eq(:worker)
    end

    it 'maps :lite to :lite' do
      expect(described_class::LEGACY_MAP[:lite]).to eq(:lite)
    end
  end
end
