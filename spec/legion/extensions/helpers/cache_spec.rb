# frozen_string_literal: true

require 'spec_helper'
require 'legion/extensions/helpers/cache'

RSpec.describe Legion::Extensions::Helpers::Cache do
  let(:test_class) do
    Class.new do
      include Legion::Extensions::Helpers::Cache

      def lex_filename
        'test_lex'
      end
    end
  end

  subject { test_class.new }

  describe 'includes Legion::Cache::Helper' do
    it 'responds to core cache helper methods' do
      expect(subject).to respond_to(:cache_get, :cache_set, :cache_delete, :cache_fetch,
                                    :cache_namespace)
    end

    it 'responds to local cache helper methods' do
      expect(subject).to respond_to(:local_cache_get, :local_cache_set, :local_cache_delete,
                                    :local_cache_fetch)
    end
  end

  describe 'includes Base' do
    it 'responds to base helper methods' do
      expect(subject).to respond_to(:lex_name, :segments)
    end
  end

  describe '#cache_namespace' do
    it 'derives from lex_filename' do
      expect(subject.cache_namespace).to eq('test_lex')
    end
  end

  describe '#cache_set' do
    it 'delegates to Legion::Cache with namespaced key' do
      allow(Legion::Cache).to receive(:set)
      subject.cache_set(':key', 'val', ttl: 120)
      expect(Legion::Cache).to have_received(:set) do |key, val, ttl, **_opts|
        expect(key).to eq('test_lex:key')
        expect(val).to eq('val')
        expect(ttl).to eq(120)
      end
    end
  end

  describe '#cache_get' do
    it 'delegates to Legion::Cache with namespaced key' do
      allow(Legion::Cache).to receive(:get).with('test_lex:key').and_return('val')
      expect(subject.cache_get(':key')).to eq('val')
    end
  end
end
