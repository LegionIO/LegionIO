# frozen_string_literal: true

require 'spec_helper'
require 'legion/extensions/helpers/data'

RSpec.describe Legion::Extensions::Helpers::Data do
  let(:test_class) do
    Class.new do
      include Legion::Extensions::Helpers::Data

      def lex_filename
        'test_lex'
      end
    end
  end

  subject { test_class.new }

  describe 'includes Legion::Data::Helper' do
    it 'responds to data helper methods' do
      expect(subject).to respond_to(:data_connected?, :data_connection, :data_adapter,
                                    :data_pool_stats, :data_stats, :data_can_read?,
                                    :data_can_write?)
    end

    it 'responds to local data helper methods' do
      expect(subject).to respond_to(:local_data_connected?, :local_data_connection,
                                    :local_data_model, :local_data_stats)
    end
  end

  describe 'includes Base' do
    it 'responds to base helper methods' do
      expect(subject).to respond_to(:lex_name, :segments)
    end
  end

  describe '#data_connected?' do
    it 'reads from settings' do
      allow(Legion::Settings).to receive(:[]).with(:data).and_return({ connected: true })
      expect(subject.data_connected?).to be true
    end
  end
end
