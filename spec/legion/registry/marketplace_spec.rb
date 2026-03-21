# frozen_string_literal: true

require 'spec_helper'
require 'legion/registry'

RSpec.describe Legion::Registry do
  let(:entry_attrs) do
    {
      name:        'lex-test',
      version:     '1.0.0',
      author:      'test-author',
      description: 'A test extension',
      risk_tier:   'low',
      airb_status: 'pending'
    }
  end

  let(:entry) { Legion::Registry::Entry.new(**entry_attrs) }

  before(:each) do
    Legion::Registry.clear!
    Legion::Registry.register(entry)
  end

  # ──────────────────────────────────────────────────────────
  # Entry status fields
  # ──────────────────────────────────────────────────────────

  describe 'Entry' do
    describe '#status' do
      it 'defaults to :active' do
        expect(entry.status).to eq(:active)
      end

      it 'accepts explicit status' do
        e = Legion::Registry::Entry.new(**entry_attrs, status: :pending_review)
        expect(e.status).to eq(:pending_review)
      end
    end

    describe '#deprecated?' do
      it 'returns false for active entry' do
        expect(entry.deprecated?).to be false
      end

      it 'returns true for deprecated status' do
        e = Legion::Registry::Entry.new(**entry_attrs, status: :deprecated)
        expect(e.deprecated?).to be true
      end

      it 'returns true for sunset status' do
        e = Legion::Registry::Entry.new(**entry_attrs, status: :sunset)
        expect(e.deprecated?).to be true
      end
    end

    describe '#pending_review?' do
      it 'returns false for active entry' do
        expect(entry.pending_review?).to be false
      end

      it 'returns true when status is pending_review' do
        e = Legion::Registry::Entry.new(**entry_attrs, status: :pending_review)
        expect(e.pending_review?).to be true
      end
    end

    describe '#to_h' do
      it 'includes status field' do
        expect(entry.to_h).to have_key(:status)
      end

      it 'includes successor field' do
        expect(entry.to_h).to have_key(:successor)
      end

      it 'includes sunset_date field' do
        expect(entry.to_h).to have_key(:sunset_date)
      end

      it 'includes submitted_at field' do
        expect(entry.to_h).to have_key(:submitted_at)
      end
    end
  end

  # ──────────────────────────────────────────────────────────
  # submit_for_review
  # ──────────────────────────────────────────────────────────

  describe '.submit_for_review' do
    it 'sets status to pending_review' do
      Legion::Registry.submit_for_review('lex-test')
      expect(Legion::Registry.lookup('lex-test').status).to eq(:pending_review)
    end

    it 'sets submitted_at timestamp' do
      Legion::Registry.submit_for_review('lex-test')
      expect(Legion::Registry.lookup('lex-test').submitted_at).to be_a(Time)
    end

    it 'returns true on success' do
      expect(Legion::Registry.submit_for_review('lex-test')).to be true
    end

    it 'raises ArgumentError for unknown extension' do
      expect { Legion::Registry.submit_for_review('lex-missing') }.to raise_error(ArgumentError, /not found/)
    end
  end

  # ──────────────────────────────────────────────────────────
  # approve
  # ──────────────────────────────────────────────────────────

  describe '.approve' do
    before { Legion::Registry.submit_for_review('lex-test') }

    it 'sets status to approved' do
      Legion::Registry.approve('lex-test')
      expect(Legion::Registry.lookup('lex-test').status).to eq(:approved)
    end

    it 'sets airb_status to approved' do
      Legion::Registry.approve('lex-test')
      expect(Legion::Registry.lookup('lex-test').airb_status).to eq('approved')
    end

    it 'stores review notes' do
      Legion::Registry.approve('lex-test', notes: 'LGTM')
      expect(Legion::Registry.lookup('lex-test').review_notes).to eq('LGTM')
    end

    it 'sets approved_at timestamp' do
      Legion::Registry.approve('lex-test')
      expect(Legion::Registry.lookup('lex-test').approved_at).to be_a(Time)
    end

    it 'returns true on success' do
      expect(Legion::Registry.approve('lex-test')).to be true
    end

    it 'raises ArgumentError for unknown extension' do
      expect { Legion::Registry.approve('lex-missing') }.to raise_error(ArgumentError, /not found/)
    end

    it 'makes approved? return true' do
      Legion::Registry.approve('lex-test')
      expect(Legion::Registry.lookup('lex-test').approved?).to be true
    end
  end

  # ──────────────────────────────────────────────────────────
  # reject
  # ──────────────────────────────────────────────────────────

  describe '.reject' do
    before { Legion::Registry.submit_for_review('lex-test') }

    it 'sets status to rejected' do
      Legion::Registry.reject('lex-test')
      expect(Legion::Registry.lookup('lex-test').status).to eq(:rejected)
    end

    it 'stores rejection reason' do
      Legion::Registry.reject('lex-test', reason: 'Security issues')
      expect(Legion::Registry.lookup('lex-test').reject_reason).to eq('Security issues')
    end

    it 'sets rejected_at timestamp' do
      Legion::Registry.reject('lex-test')
      expect(Legion::Registry.lookup('lex-test').rejected_at).to be_a(Time)
    end

    it 'returns true on success' do
      expect(Legion::Registry.reject('lex-test')).to be true
    end

    it 'raises ArgumentError for unknown extension' do
      expect { Legion::Registry.reject('lex-missing') }.to raise_error(ArgumentError, /not found/)
    end
  end

  # ──────────────────────────────────────────────────────────
  # deprecate
  # ──────────────────────────────────────────────────────────

  describe '.deprecate' do
    it 'sets status to deprecated' do
      Legion::Registry.deprecate('lex-test')
      expect(Legion::Registry.lookup('lex-test').status).to eq(:deprecated)
    end

    it 'stores successor' do
      Legion::Registry.deprecate('lex-test', successor: 'lex-test-v2')
      expect(Legion::Registry.lookup('lex-test').successor).to eq('lex-test-v2')
    end

    it 'stores sunset_date' do
      sunset = Date.new(2027, 1, 1)
      Legion::Registry.deprecate('lex-test', sunset_date: sunset)
      expect(Legion::Registry.lookup('lex-test').sunset_date).to eq(sunset)
    end

    it 'sets deprecated_at timestamp' do
      Legion::Registry.deprecate('lex-test')
      expect(Legion::Registry.lookup('lex-test').deprecated_at).to be_a(Time)
    end

    it 'makes deprecated? return true' do
      Legion::Registry.deprecate('lex-test')
      expect(Legion::Registry.lookup('lex-test').deprecated?).to be true
    end

    it 'returns true on success' do
      expect(Legion::Registry.deprecate('lex-test')).to be true
    end

    it 'raises ArgumentError for unknown extension' do
      expect { Legion::Registry.deprecate('lex-missing') }.to raise_error(ArgumentError, /not found/)
    end
  end

  # ──────────────────────────────────────────────────────────
  # pending_reviews
  # ──────────────────────────────────────────────────────────

  describe '.pending_reviews' do
    it 'returns empty array when none are pending' do
      expect(Legion::Registry.pending_reviews).to be_empty
    end

    it 'returns entries with pending_review status' do
      Legion::Registry.submit_for_review('lex-test')
      expect(Legion::Registry.pending_reviews.size).to eq(1)
    end

    it 'excludes active entries' do
      expect(Legion::Registry.pending_reviews).not_to include(entry)
    end

    it 'returns only pending_review entries when mixed statuses' do
      second = Legion::Registry::Entry.new(**entry_attrs, name: 'lex-other', status: :active)
      Legion::Registry.register(second)
      Legion::Registry.submit_for_review('lex-test')
      pending = Legion::Registry.pending_reviews
      expect(pending.map(&:name)).to eq(['lex-test'])
    end
  end

  # ──────────────────────────────────────────────────────────
  # usage_stats
  # ──────────────────────────────────────────────────────────

  describe '.usage_stats' do
    it 'returns nil for unknown extension' do
      expect(Legion::Registry.usage_stats('lex-missing')).to be_nil
    end

    it 'returns a hash for a registered extension' do
      expect(Legion::Registry.usage_stats('lex-test')).to be_a(Hash)
    end

    it 'includes name field' do
      expect(Legion::Registry.usage_stats('lex-test')[:name]).to eq('lex-test')
    end

    it 'includes install_count field' do
      expect(Legion::Registry.usage_stats('lex-test')).to have_key(:install_count)
    end

    it 'includes active_instances field' do
      expect(Legion::Registry.usage_stats('lex-test')).to have_key(:active_instances)
    end

    it 'includes downloads_7d field' do
      expect(Legion::Registry.usage_stats('lex-test')).to have_key(:downloads_7d)
    end

    it 'includes downloads_30d field' do
      expect(Legion::Registry.usage_stats('lex-test')).to have_key(:downloads_30d)
    end
  end

  # ──────────────────────────────────────────────────────────
  # full lifecycle flow
  # ──────────────────────────────────────────────────────────

  describe 'full review lifecycle' do
    it 'transitions: active -> pending_review -> approved' do
      expect(entry.status).to eq(:active)
      Legion::Registry.submit_for_review('lex-test')
      expect(Legion::Registry.lookup('lex-test').status).to eq(:pending_review)
      Legion::Registry.approve('lex-test', notes: 'All checks pass')
      approved = Legion::Registry.lookup('lex-test')
      expect(approved.status).to eq(:approved)
      expect(approved.airb_status).to eq('approved')
    end

    it 'transitions: active -> pending_review -> rejected' do
      Legion::Registry.submit_for_review('lex-test')
      Legion::Registry.reject('lex-test', reason: 'CVE found')
      rejected = Legion::Registry.lookup('lex-test')
      expect(rejected.status).to eq(:rejected)
      expect(rejected.reject_reason).to eq('CVE found')
    end

    it 'transitions: approved -> deprecated with successor' do
      Legion::Registry.submit_for_review('lex-test')
      Legion::Registry.approve('lex-test')
      Legion::Registry.deprecate('lex-test', successor: 'lex-test-v2', sunset_date: Date.new(2027, 6, 1))
      deprecated = Legion::Registry.lookup('lex-test')
      expect(deprecated.status).to eq(:deprecated)
      expect(deprecated.successor).to eq('lex-test-v2')
      expect(deprecated.sunset_date).to eq(Date.new(2027, 6, 1))
    end
  end
end
