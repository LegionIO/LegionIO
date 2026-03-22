# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli/error'
require 'legion/cli/error_handler'
require 'legion/cli/output'

RSpec.describe Legion::CLI::ErrorHandler do
  describe 'PATTERNS' do
    it 'matches RabbitMQ connection refused on port 5672' do
      pattern = described_class::PATTERNS.find { |p| p[:code] == :transport_unavailable }
      expect('connection refused to 5672').to match(pattern[:match])
    end

    it 'matches bunny not connected' do
      pattern = described_class::PATTERNS.find { |p| p[:code] == :transport_unavailable }
      expect('Bunny::NotConnected: bunny not connected').to match(pattern[:match])
    end

    it 'matches SQLite no such table' do
      pattern = described_class::PATTERNS.find { |p| p[:code] == :database_missing }
      expect('no such table: tasks').to match(pattern[:match])
    end

    it 'matches PostgreSQL PG::UndefinedTable' do
      pattern = described_class::PATTERNS.find { |p| p[:code] == :database_missing }
      expect('PG::UndefinedTable: ERROR: relation "tasks" does not exist').to match(pattern[:match])
    end

    it 'matches extension not found' do
      pattern = described_class::PATTERNS.find { |p| p[:code] == :extension_missing }
      expect('extension not found: lex-foo').to match(pattern[:match])
    end

    it 'matches uninitialized constant Extensions' do
      pattern = described_class::PATTERNS.find { |p| p[:code] == :extension_missing }
      expect('uninitialized constant Legion::Extensions::Foo').to match(pattern[:match])
    end

    it 'matches permission denied (lowercase)' do
      pattern = described_class::PATTERNS.find { |p| p[:code] == :permission_denied }
      expect('Permission denied @ rb_sysopen - /etc/legionio/settings.json').to match(pattern[:match])
    end

    it 'matches EACCES' do
      pattern = described_class::PATTERNS.find { |p| p[:code] == :permission_denied }
      expect('Errno::EACCES: permission denied').to match(pattern[:match])
    end

    it 'matches legion-data not connected' do
      pattern = described_class::PATTERNS.find { |p| p[:code] == :data_unavailable }
      expect('legion-data not connected').to match(pattern[:match])
    end

    it 'matches vault sealed' do
      pattern = described_class::PATTERNS.find { |p| p[:code] == :vault_unavailable }
      expect('Vault sealed').to match(pattern[:match])
    end

    it 'matches VAULT_ADDR not set' do
      pattern = described_class::PATTERNS.find { |p| p[:code] == :vault_unavailable }
      expect('VAULT_ADDR environment variable not set').to match(pattern[:match])
    end
  end

  describe '.wrap' do
    it 'wraps a known error into a CLI::Error with suggestions' do
      original = StandardError.new('connection refused to 5672')
      result = described_class.wrap(original)

      expect(result).to be_a(Legion::CLI::Error)
      expect(result.code).to eq(:transport_unavailable)
      expect(result.suggestions).not_to be_empty
      expect(result.message).to include('Cannot connect to RabbitMQ')
      expect(result.message).to include('connection refused to 5672')
    end

    it 'returns the original error unchanged for unknown patterns' do
      original = StandardError.new('some totally unknown error message')
      result = described_class.wrap(original)

      expect(result).to be(original)
    end

    it 'includes the original message in the wrapped error message' do
      original = StandardError.new('no such table: tasks')
      result = described_class.wrap(original)

      expect(result.message).to include('no such table: tasks')
    end
  end

  describe '.format_error' do
    let(:formatter) { instance_double(Legion::CLI::Output::Formatter) }

    before do
      allow(formatter).to receive(:error)
      allow(formatter).to receive(:colorize).with('>', :label).and_return('>')
    end

    it 'always calls formatter.error with the message' do
      error = Legion::CLI::Error.new('something went wrong')
      expect(formatter).to receive(:error).with('something went wrong')
      described_class.format_error(error, formatter)
    end

    it 'prints suggestions for actionable CLI errors' do
      error = Legion::CLI::Error.actionable(
        code:        :transport_unavailable,
        message:     'Cannot connect',
        suggestions: ['Run legion doctor', 'Check settings']
      )

      expect { described_class.format_error(error, formatter) }.to output(
        a_string_including('Run legion doctor')
      ).to_stdout
    end

    it 'does not print suggestions for non-actionable CLI errors' do
      error = Legion::CLI::Error.new('plain error')
      described_class.format_error(error, formatter)
      # formatter.error is called but colorize is never called (no suggestion lines)
      expect(formatter).to have_received(:error).with('plain error')
      expect(formatter).not_to have_received(:colorize)
    end

    it 'does not print suggestions for plain StandardError' do
      error = StandardError.new('plain standard error')
      described_class.format_error(error, formatter)
      expect(formatter).to have_received(:error).with('plain standard error')
      expect(formatter).not_to have_received(:colorize)
    end
  end
end
