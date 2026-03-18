# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Extensions::Helpers::Logger do
  # A test class that includes the Logger helper and has segments (nested extension)
  let(:segmented_class) do
    klass = Class.new do
      include Legion::Extensions::Helpers::Logger

      def segments
        %w[agentic cognitive anchor]
      end

      # Satisfy handle_exception dependency
      def lex_filename
        'agentic_cognitive_anchor'
      end
    end
    klass
  end

  # A test class that includes Logger but lacks segments (legacy flat extension)
  let(:legacy_class) do
    klass = Class.new do
      include Legion::Extensions::Helpers::Logger

      def lex_filename
        'microsoft_teams'
      end
    end
    klass
  end

  describe '#log' do
    context 'when the object responds to :segments' do
      subject { segmented_class.new }

      it 'builds a logger with lex_segments: from segments' do
        logger_double = instance_double(Legion::Logging::Logger)
        expect(Legion::Logging::Logger).to receive(:new).with(hash_including(lex_segments: %w[agentic cognitive anchor])).and_return(logger_double)
        subject.log
      end

      it 'does not pass lex: keyword when segments is available' do
        logger_double = instance_double(Legion::Logging::Logger)
        expect(Legion::Logging::Logger).to receive(:new).with(hash_not_including(:lex)).and_return(logger_double)
        subject.log
      end
    end

    context 'when the object does not respond to :segments (legacy)' do
      subject { legacy_class.new }

      it 'builds a logger with lex: from lex_filename' do
        logger_double = instance_double(Legion::Logging::Logger)
        expect(Legion::Logging::Logger).to receive(:new).with(hash_including(lex: 'microsoft_teams')).and_return(logger_double)
        subject.log
      end
    end
  end
end
