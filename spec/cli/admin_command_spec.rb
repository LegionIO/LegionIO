# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli'
require 'legion/cli/admin_command'

RSpec.describe Legion::CLI::AdminCommand do
  describe '.detect_old_exchanges' do
    subject(:detect) { described_class.detect_old_exchanges(exchanges) }

    context 'when both legion.X and lex.X exist' do
      let(:exchanges) do
        [
          { name: 'lex.runner', type: 'topic' },
          { name: 'legion.runner', type: 'topic' },
          { name: 'lex.actor',    type: 'direct' },
          { name: 'legion.actor', type: 'direct' }
        ]
      end

      it 'returns both matched legion.* exchanges' do
        expect(detect.size).to eq(2)
      end

      it 'returns legion.runner as a candidate' do
        expect(detect.map { |e| e[:name] }).to include('legion.runner')
      end

      it 'returns legion.actor as a candidate' do
        expect(detect.map { |e| e[:name] }).to include('legion.actor')
      end

      it 'does not return the lex.* exchanges themselves' do
        names = detect.map { |e| e[:name] }
        expect(names).not_to include('lex.runner')
        expect(names).not_to include('lex.actor')
      end
    end

    context 'when there is no lex.* counterpart for a legion.* exchange' do
      let(:exchanges) do
        [
          { name: 'legion.orphan', type: 'topic' },
          { name: 'lex.other',     type: 'direct' }
        ]
      end

      it 'does not return legion.orphan (no lex.orphan exists)' do
        expect(detect).to be_empty
      end
    end

    context 'when core exchanges like task, node, extensions exist without lex.* counterparts' do
      let(:exchanges) do
        [
          { name: 'legion.task',       type: 'topic' },
          { name: 'legion.node',       type: 'topic' },
          { name: 'legion.extensions', type: 'fanout' }
        ]
      end

      it 'does not return legion.task' do
        names = detect.map { |e| e[:name] }
        expect(names).not_to include('legion.task')
      end

      it 'does not return legion.node' do
        names = detect.map { |e| e[:name] }
        expect(names).not_to include('legion.node')
      end

      it 'does not return legion.extensions' do
        names = detect.map { |e| e[:name] }
        expect(names).not_to include('legion.extensions')
      end

      it 'returns an empty list' do
        expect(detect).to be_empty
      end
    end

    context 'when the exchange list is empty' do
      let(:exchanges) { [] }

      it 'returns an empty array' do
        expect(detect).to be_empty
      end
    end

    context 'when only lex.* exchanges exist (no legion.* at all)' do
      let(:exchanges) do
        [
          { name: 'lex.runner', type: 'topic' },
          { name: 'lex.actor',  type: 'direct' }
        ]
      end

      it 'returns an empty array' do
        expect(detect).to be_empty
      end
    end

    context 'when a partial overlap exists (some pairs matched, some not)' do
      let(:exchanges) do
        [
          { name: 'lex.runner',      type: 'topic' },
          { name: 'legion.runner',   type: 'topic' },
          { name: 'legion.old_only', type: 'direct' }
        ]
      end

      it 'returns only the matched exchange' do
        expect(detect.size).to eq(1)
      end

      it 'returns legion.runner' do
        expect(detect.first[:name]).to eq('legion.runner')
      end

      it 'does not return legion.old_only (no lex.old_only counterpart)' do
        names = detect.map { |e| e[:name] }
        expect(names).not_to include('legion.old_only')
      end
    end

    context 'when exchanges have mixed prefixes and unrelated names' do
      let(:exchanges) do
        [
          { name: '',           type: 'direct' },
          { name: 'amq.direct', type: 'direct' },
          { name: 'amq.topic',  type: 'topic' },
          { name: 'lex.events', type: 'fanout' },
          { name: 'legion.events', type: 'fanout' }
        ]
      end

      it 'returns only legion.events' do
        expect(detect.size).to eq(1)
        expect(detect.first[:name]).to eq('legion.events')
      end
    end
  end

  describe 'Thor registration' do
    let(:command) { described_class.commands['purge_topology'] }

    it 'has a purge-topology command' do
      expect(described_class.commands).to have_key('purge_topology')
    end

    it 'declares --dry-run option' do
      expect(command.options).to have_key(:dry_run)
    end

    it 'declares --execute option' do
      expect(command.options).to have_key(:execute)
    end

    it 'declares --host option' do
      expect(command.options).to have_key(:host)
    end

    it 'defaults dry_run to true' do
      expect(command.options[:dry_run].default).to be true
    end

    it 'defaults execute to false' do
      expect(command.options[:execute].default).to be false
    end
  end
end
