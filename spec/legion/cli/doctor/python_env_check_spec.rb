# frozen_string_literal: true

require 'spec_helper'
require 'legion/python'
require 'legion/cli/doctor_command'

RSpec.describe Legion::CLI::Doctor::PythonEnvCheck do
  subject(:check) { described_class.new }

  describe '#name' do
    it 'returns Python env' do
      expect(check.name).to eq('Python env')
    end
  end

  describe '#run' do
    context 'when python3 is not available' do
      before do
        allow(Legion::Python).to receive(:find_system_python3).and_return(nil)
      end

      it 'returns a skip result' do
        result = check.run
        expect(result.status).to eq(:skip)
        expect(result.message).to include('python3 not found')
      end
    end

    context 'when python3 exists but venv is missing' do
      before do
        allow(Legion::Python).to receive(:find_system_python3).and_return('/usr/bin/python3')
        allow(Legion::Python).to receive(:venv_exists?).and_return(false)
      end

      it 'returns a warn result' do
        result = check.run
        expect(result.status).to eq(:warn)
        expect(result.message).to include('venv missing')
      end
    end

    context 'when venv exists but pip is missing' do
      before do
        allow(Legion::Python).to receive(:find_system_python3).and_return('/usr/bin/python3')
        allow(Legion::Python).to receive(:venv_exists?).and_return(true)
        allow(Legion::Python).to receive(:venv_pip_exists?).and_return(false)
      end

      it 'returns a warn result about corrupt venv' do
        result = check.run
        expect(result.status).to eq(:warn)
        expect(result.message).to include('pip not found')
      end
    end

    context 'when venv is healthy with all packages' do
      before do
        allow(Legion::Python).to receive(:find_system_python3).and_return('/usr/bin/python3')
        allow(Legion::Python).to receive(:venv_exists?).and_return(true)
        allow(Legion::Python).to receive(:venv_pip_exists?).and_return(true)
        allow(Legion::Python).to receive(:venv_python).and_return('/fake/python3')
        allow(File).to receive(:executable?).and_call_original
        allow(File).to receive(:executable?).with('/fake/python3').and_return(true)

        pkg_lines = Legion::Python::PACKAGES.map { |p| "#{p}  1.0.0" }.join("\n")
        pip_output = "Package    Version\n---------- -------\n#{pkg_lines}"
        allow(check).to receive(:`).and_return(pip_output)
      end

      it 'returns a pass result' do
        allow(check).to receive(:`).with(/".*python3" --version/).and_return('Python 3.12.0')
        result = check.run
        expect(result.status).to eq(:pass)
      end
    end

    context 'when packages are missing' do
      before do
        allow(Legion::Python).to receive(:find_system_python3).and_return('/usr/bin/python3')
        allow(Legion::Python).to receive(:venv_exists?).and_return(true)
        allow(Legion::Python).to receive(:venv_pip_exists?).and_return(true)
        allow(Legion::Python).to receive(:venv_pip).and_return('/fake/pip')

        pip_output = "Package    Version\n---------- -------\npandas  2.0.0\n"
        allow(check).to receive(:`).and_return(pip_output)
      end

      it 'returns a warn result listing missing packages' do
        result = check.run
        expect(result.status).to eq(:warn)
        expect(result.message).to include('Missing packages')
        expect(result.message).to include('python-pptx')
      end
    end
  end

  describe '#fix' do
    it 'calls legionio setup python' do
      allow(check).to receive(:system).with('legionio', 'setup', 'python').and_return(true)
      check.fix
      expect(check).to have_received(:system).with('legionio', 'setup', 'python')
    end
  end
end
