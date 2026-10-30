# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli/connect_command'
require_relative '../../fixtures/chatgpt_cli'

RSpec.describe Legion::CLI::ConnectCommand do
  let(:fixture) { ChatgptCliFixture.new }

  around do |example|
    example.run
  ensure
    fixture.close
  end

  it 'persists browser login under the exact name across both binaries and removes it on disconnect' do
    instance = 'Personal/work'
    login = fixture.run(args: ['chatgpt', '--instance', instance]) do |line, _pid|
      fixture.approve_browser(line: line)
    end
    expect(login[:exitstatus]).to eq(0), login[:stderr]
    expect(fixture.store.records.keys).to eq([instance])
    restart = fixture.run(args: ['status', '--provider', 'chatgpt', '--instance', instance], binary: 'legionio')
    expect(restart[:exitstatus]).to eq(0), restart[:stderr]
    expect(restart[:stdout]).to include('authenticated')
    disconnect = fixture.run(args: ['disconnect', 'chatgpt', '--instance', instance])
    expect(disconnect[:exitstatus]).to eq(0), disconnect[:stderr]
    removed = fixture.run(args: ['status', '--provider', 'chatgpt', '--instance', instance])
    expect(removed[:stdout]).to include('missing')
    output = [login, restart, disconnect, removed].flat_map { |result| result.values_at(:stdout, :stderr) }.join
    expect(output).not_to include(*fixture.secrets)
  end

  it 'completes device authorization without requiring a browser callback' do
    result = fixture.run(args: %w[chatgpt --instance Work --device])
    expect(result[:exitstatus]).to eq(0), result[:stderr]
    expect(result[:stdout]).to include('https://auth.openai.com/codex/device', 'FIXTURE-USER-CODE')
    expect(fixture.store.read(instance: 'Work')[:status]).to eq('authenticated')
    expect(result[:stdout] + result[:stderr]).not_to include(*fixture.secrets)
  end

  it 'does not create credentials or perform HTTP while reporting a missing named login' do
    result = fixture.run(args: %w[status --provider chatgpt --instance personal])
    expect(result[:exitstatus]).to eq(0), result[:stderr]
    expect(result[:stdout]).to include('missing')
    expect(fixture.requests).to be_empty
    expect(File.exist?(fixture.credential_root)).to be(false)
  end

  it 'reports expired-but-refreshable credentials without refreshing or mutating the stored bundle' do
    fixture.seed(instance: 'personal', expires_at: Time.now.to_f - 60)
    previous = fixture.store.read(instance: 'personal')
    result = fixture.run(args: %w[status --provider chatgpt --instance personal])
    expect(result[:exitstatus]).to eq(0), result[:stderr]
    expect(result[:stdout]).to include('expired_refreshable')
    expect(fixture.store.read(instance: 'personal')).to eq(previous)
    expect(fixture.requests).to be_empty
    expect(result[:stdout] + result[:stderr]).not_to include(*fixture.secrets)
  end

  it 'distinguishes known revoked grants from a missing login without attempting another login' do
    fixture.seed(instance: 'personal')
    expect do
      fixture.store.refresh_credentials(instance: 'personal') do
        raise Legion::Extensions::Llm::Openai::Chatgpt::Error.new(
          message: 'Fixture revoked grant', kind: :authentication, metadata: { reauth_required: true }
        )
      end
    end.to raise_error(Legion::Extensions::Llm::Openai::Chatgpt::Error)
    result = fixture.run(args: %w[status --provider chatgpt --instance personal])
    expect(result[:exitstatus]).to eq(0), result[:stderr]
    expect(result[:stdout]).to include('reauth_required')
    expect(fixture.requests).to be_empty
    expect(result[:stdout] + result[:stderr]).not_to include(*fixture.secrets)
  end

  it 'fails actionably when the native extension cannot be loaded' do
    result = fixture.run(args: %w[chatgpt --instance personal --device], missing: true)
    expect(result[:exitstatus]).to eq(1)
    expect(result[:stderr]).to include('lex-llm-openai')
    expect(result[:stdout] + result[:stderr]).not_to include(*fixture.secrets)
    expect(fixture.requests).to be_empty
    expect(File.exist?(fixture.credential_root)).to be(false)
  end

  it 'returns a failure when device authorization is denied without exposing the OAuth body' do
    fixture.mode = :denied
    result = fixture.run(args: %w[chatgpt --instance personal --device])
    expect(result[:exitstatus]).to eq(1)
    expect(result[:stdout] + result[:stderr]).not_to include(*fixture.secrets)
    expect(fixture.store.records).to be_empty
  end

  it 'returns a failure on interrupt without persisting an approved-looking login' do
    fixture.mode = :pending
    result = fixture.run(args: %w[chatgpt --instance personal --device]) do |line, pid|
      ::Process.kill('INT', pid) if line.include?('FIXTURE-USER-CODE')
    end
    expect(result[:exitstatus]).to eq(1)
    expect(result[:stdout] + result[:stderr]).not_to include(*fixture.secrets)
    expect(fixture.store.records).to be_empty
  end

  it 'does not report login success when persistence fails after a successful token exchange' do
    fixture.mode = :storage_failure
    result = fixture.run(args: %w[chatgpt --instance personal --device])
    expect(result[:exitstatus]).to eq(1)
    expect(result[:stdout] + result[:stderr]).not_to include(*fixture.secrets)
    File.chmod(0o700, fixture.credential_root)
    expect(fixture.store.records).to be_empty
  end

  it 'rejects disconnecting a missing login instead of claiming a successful no-op' do
    result = fixture.run(args: %w[disconnect chatgpt --instance absent])
    expect(result[:exitstatus]).to eq(1)
    expect(fixture.requests).to be_empty
    expect(File.exist?(fixture.credential_root)).to be(false)
  end

  it 'preserves unfiltered legacy status when the native extension is unavailable' do
    result = fixture.run(args: ['status'], missing: true)
    expect(result[:exitstatus]).to eq(0), result[:stderr]
    expect(result[:stdout]).to include('microsoft:', 'github:', 'google:')
    expect(fixture.requests).to be_empty
  end

  it 'filters a legacy provider without requiring a native instance or extension' do
    result = fixture.run(args: %w[status --provider github], missing: true)
    expect(result[:exitstatus]).to eq(0), result[:stderr]
    expect(result[:stdout]).to include('github:')
    expect(result[:stdout]).not_to include('microsoft:', 'google:')
  end

  it 'requires an explicit instance rather than selecting a default account' do
    result = fixture.run(args: %w[status --provider chatgpt])
    expect(result[:exitstatus]).to eq(1)
    expect(result[:stderr]).to include('--instance')
    expect(fixture.requests).to be_empty
    expect(File.exist?(fixture.credential_root)).to be(false)
  end
end
