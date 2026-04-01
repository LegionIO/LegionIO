# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'legion/memory/consolidator'

RSpec.describe Legion::Memory::Consolidator do
  let(:tmpdir) { Dir.mktmpdir }
  let(:lock_file) { File.join(tmpdir, 'memory_consolidation.lock') }
  let(:sessions_dir) { File.join(tmpdir, 'sessions') }

  before do
    stub_const('Legion::Memory::Consolidator::LOCK_FILE', lock_file)
    stub_const('Legion::Memory::Consolidator::SESSIONS_DIR', sessions_dir)
    FileUtils.mkdir_p(sessions_dir)
    allow(Legion::Logging).to receive(:info)
    allow(Legion::Logging).to receive(:debug)
    allow(Legion::Logging).to receive(:warn)
    allow(Legion::Logging).to receive(:error)
  end

  after { FileUtils.rm_rf(tmpdir) }

  def write_session(name, messages: [], cwd: '/tmp')
    data = { name: name, cwd: cwd, messages: messages }
    raw = defined?(Legion::JSON) ? Legion::JSON.dump(data) : data.to_json
    File.write(File.join(sessions_dir, "#{name}.json"), raw)
  end

  describe '.enabled?' do
    it 'returns false by default' do
      allow(Legion::Settings).to receive(:dig).with(:memory, :consolidation).and_return(nil)
      expect(described_class.enabled?).to be false
    end

    it 'returns true when enabled in settings' do
      allow(Legion::Settings).to receive(:dig).with(:memory, :consolidation).and_return({ enabled: true })
      expect(described_class.enabled?).to be true
    end
  end

  describe '.gate_status' do
    before do
      allow(Legion::Settings).to receive(:dig).with(:memory, :consolidation)
                                              .and_return({ enabled: true, min_hours: 24, min_sessions: 5 })
    end

    it 'returns hash with three gates' do
      status = described_class.gate_status
      expect(status).to have_key(:time_gate)
      expect(status).to have_key(:session_gate)
      expect(status).to have_key(:lock_gate)
    end

    context 'time gate' do
      it 'passes when no lock file exists' do
        expect(described_class.gate_status[:time_gate]).to be true
      end

      it 'fails when lock file is recent' do
        FileUtils.mkdir_p(File.dirname(lock_file))
        FileUtils.touch(lock_file)
        expect(described_class.gate_status[:time_gate]).to be false
      end
    end

    context 'session gate' do
      it 'fails when fewer than min_sessions exist' do
        2.times { |i| write_session("s#{i}", messages: [{ role: 'user', content: "msg#{i}" }]) }
        expect(described_class.gate_status[:session_gate]).to be false
      end

      it 'passes when enough new sessions exist' do
        6.times { |i| write_session("s#{i}", messages: [{ role: 'user', content: "msg#{i}" }]) }
        expect(described_class.gate_status[:session_gate]).to be true
      end
    end

    context 'lock gate' do
      it 'passes when no active lock' do
        expect(described_class.gate_status[:lock_gate]).to be true
      end

      it 'fails when active lock exists' do
        FileUtils.mkdir_p(File.dirname(lock_file))
        FileUtils.touch(lock_file)
        File.write("#{lock_file}.active", '12345')
        expect(described_class.gate_status[:lock_gate]).to be false
      end
    end
  end

  describe '.run' do
    before do
      allow(Legion::Settings).to receive(:dig).with(:memory, :consolidation)
                                              .and_return({ enabled: true, min_hours: 0, min_sessions: 1 })
    end

    it 'returns disabled when not enabled' do
      allow(Legion::Settings).to receive(:dig).with(:memory, :consolidation).and_return({ enabled: false })
      result = described_class.run
      expect(result[:success]).to be false
      expect(result[:reason]).to eq(:disabled)
    end

    it 'returns gates_failed when gates do not pass' do
      allow(Legion::Settings).to receive(:dig).with(:memory, :consolidation)
                                              .and_return({ enabled: true, min_hours: 24, min_sessions: 100 })
      result = described_class.run
      expect(result[:success]).to be false
      expect(result[:reason]).to eq(:gates_failed)
    end

    it 'succeeds with force even when gates fail' do
      write_session('forced', messages: [{ role: 'user', content: 'hello' }])
      result = described_class.run(force: true)
      expect(result[:success]).to be true
    end

    it 'returns llm_unavailable reason when no LLM' do
      hide_const('Legion::LLM') if defined?(Legion::LLM)
      write_session('test', messages: [{ role: 'user', content: 'hello' }])
      result = described_class.run(force: true)
      expect(result[:success]).to be true
      expect(result[:reason]).to eq(:llm_unavailable)
      expect(result[:insights]).to eq([])
    end

    it 'releases lock even on failure' do
      write_session('test', messages: [{ role: 'user', content: 'hello' }])
      described_class.run(force: true)
      expect(File.exist?("#{lock_file}.active")).to be false
    end

    it 'touches lock file on success' do
      write_session('test', messages: [{ role: 'user', content: 'hello' }])
      described_class.run(force: true)
      expect(File.exist?(lock_file)).to be true
    end
  end

  describe '.parse_insights' do
    it 'parses valid JSON array' do
      json = '[{"text": "user prefers concise output", "category": "preference"}]'
      result = described_class.send(:parse_insights, json)
      expect(result.length).to eq(1)
      expect(result.first[:text]).to eq('user prefers concise output')
    end

    it 'returns empty array for invalid JSON' do
      expect(described_class.send(:parse_insights, 'not json')).to eq([])
    end

    it 'extracts JSON from markdown-wrapped response' do
      text = "Here are the insights:\n```json\n[{\"text\": \"insight\", \"category\": \"learning\"}]\n```"
      result = described_class.send(:parse_insights, text)
      expect(result.length).to eq(1)
    end
  end
end
