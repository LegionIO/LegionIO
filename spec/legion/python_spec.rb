# frozen_string_literal: true

require 'spec_helper'
require 'legion/python'

RSpec.describe Legion::Python do
  describe 'constants' do
    it 'defines VENV_DIR as ~/.legionio/python' do
      expect(described_class::VENV_DIR).to end_with('.legionio/python')
    end

    it 'defines MARKER as ~/.legionio/.python-venv' do
      expect(described_class::MARKER).to end_with('.legionio/.python-venv')
    end

    it 'defines PACKAGES as a frozen array of pip packages' do
      expect(described_class::PACKAGES).to be_frozen
      expect(described_class::PACKAGES).to include('python-pptx', 'pandas', 'pillow')
    end

    it 'defines SYSTEM_CANDIDATES as known python3 paths' do
      expect(described_class::SYSTEM_CANDIDATES).to include('/opt/homebrew/bin/python3')
      expect(described_class::SYSTEM_CANDIDATES).to include('/usr/local/bin/python3')
    end
  end

  describe '.venv_python' do
    it 'returns the venv python3 path' do
      expect(described_class.venv_python).to eq("#{described_class::VENV_DIR}/bin/python3")
    end
  end

  describe '.venv_pip' do
    it 'returns the venv pip path' do
      expect(described_class.venv_pip).to eq("#{described_class::VENV_DIR}/bin/pip")
    end
  end

  describe '.venv_exists?' do
    it 'returns true when pyvenv.cfg exists' do
      allow(File).to receive(:exist?).with("#{described_class::VENV_DIR}/pyvenv.cfg").and_return(true)
      expect(described_class.venv_exists?).to be true
    end

    it 'returns false when pyvenv.cfg is missing' do
      allow(File).to receive(:exist?).with("#{described_class::VENV_DIR}/pyvenv.cfg").and_return(false)
      expect(described_class.venv_exists?).to be false
    end
  end

  describe '.venv_python_exists?' do
    it 'returns true when venv python3 is executable' do
      allow(File).to receive(:executable?).with(described_class.venv_python).and_return(true)
      expect(described_class.venv_python_exists?).to be true
    end

    it 'returns false when venv python3 is not executable' do
      allow(File).to receive(:executable?).with(described_class.venv_python).and_return(false)
      expect(described_class.venv_python_exists?).to be false
    end
  end

  describe '.interpreter' do
    context 'when venv python exists' do
      it 'returns the venv python path' do
        allow(File).to receive(:executable?).with(described_class.venv_python).and_return(true)
        expect(described_class.interpreter).to eq(described_class.venv_python)
      end
    end

    context 'when venv python does not exist' do
      before do
        allow(File).to receive(:executable?).with(described_class.venv_python).and_return(false)
      end

      it 'falls back to system python3' do
        allow(described_class).to receive(:find_system_python3).and_return('/usr/bin/python3')
        expect(described_class.interpreter).to eq('/usr/bin/python3')
      end

      it 'returns bare python3 when no system python found' do
        allow(described_class).to receive(:find_system_python3).and_return(nil)
        expect(described_class.interpreter).to eq('python3')
      end
    end
  end

  describe '.pip' do
    context 'when venv pip exists' do
      it 'returns the venv pip path' do
        allow(File).to receive(:executable?).with(described_class.venv_pip).and_return(true)
        expect(described_class.pip).to eq(described_class.venv_pip)
      end
    end

    context 'when venv pip does not exist' do
      it 'returns bare pip3' do
        allow(File).to receive(:executable?).with(described_class.venv_pip).and_return(false)
        expect(described_class.pip).to eq('pip3')
      end
    end
  end

  describe '.find_system_python3' do
    it 'returns the first executable candidate' do
      allow(described_class).to receive(:`).with('command -v python3 2>/dev/null').and_return('')
      allow(File).to receive(:executable?).and_return(false)
      allow(File).to receive(:executable?).with('/opt/homebrew/bin/python3').and_return(true)
      expect(described_class.find_system_python3).to eq('/opt/homebrew/bin/python3')
    end

    it 'prefers PATH python over hardcoded candidates' do
      allow(described_class).to receive(:`).with('command -v python3 2>/dev/null').and_return("/custom/bin/python3\n")
      allow(File).to receive(:executable?).and_return(false)
      allow(File).to receive(:executable?).with('/custom/bin/python3').and_return(true)
      expect(described_class.find_system_python3).to eq('/custom/bin/python3')
    end

    it 'returns nil when no python3 is found' do
      allow(described_class).to receive(:`).with('command -v python3 2>/dev/null').and_return('')
      allow(File).to receive(:executable?).and_return(false)
      expect(described_class.find_system_python3).to be_nil
    end
  end
end
