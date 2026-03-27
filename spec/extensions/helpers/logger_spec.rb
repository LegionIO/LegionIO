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

  describe '#handle_exception' do
    let(:test_class) do
      Class.new do
        include Legion::Extensions::Helpers::Logger

        def segments
          %w[eval]
        end

        def calling_class_array
          %w[Legion Extensions Eval Runners CodeReview]
        end

        def to_s
          'Legion::Extensions::Eval::Runners::CodeReview'
        end
      end
    end

    let(:instance) { test_class.new }
    let(:error) do
      raise TypeError, 'wrong argument type'
    rescue TypeError => e
      e
    end
    let(:logger_double) { instance_double(Legion::Logging::Logger, log_exception: nil) }

    before do
      stub_const('Legion::Exception::HandledTask', Class.new(StandardError)) unless defined?(Legion::Exception::HandledTask)
      allow(instance).to receive(:log).and_return(logger_double)
    end

    it 'calls log.log_exception with lex context' do
      expect(logger_double).to receive(:log_exception).with(
        error,
        hash_including(
          lex:            'eval',
          component_type: :runner,
          gem_name:       'lex-eval',
          handled:        true
        )
      )
      begin
        instance.handle_exception(error)
      rescue Legion::Exception::HandledTask
        nil
      end
    end

    it 'raises HandledTask' do
      expect { instance.handle_exception(error) }.to raise_error(Legion::Exception::HandledTask)
    end

    it 'passes task_id through to log_exception' do
      expect(logger_double).to receive(:log_exception).with(
        error,
        hash_including(task_id: 123)
      )
      msg_double = instance_double('Legion::Transport::Messages::TaskLog', publish: true)
      allow(Legion::Transport::Messages::TaskLog).to receive(:new).and_return(msg_double)
      begin
        instance.handle_exception(error, task_id: 123)
      rescue Legion::Exception::HandledTask
        nil
      end
    end

    it 'publishes a TaskLog when task_id is given' do
      msg_double = instance_double('Legion::Transport::Messages::TaskLog', publish: true)
      expect(Legion::Transport::Messages::TaskLog).to receive(:new).with(
        hash_including(task_id: 99, runner_class: 'Legion::Extensions::Eval::Runners::CodeReview')
      ).and_return(msg_double)
      expect(msg_double).to receive(:publish)
      begin
        instance.handle_exception(error, task_id: 99)
      rescue Legion::Exception::HandledTask
        nil
      end
    end

    it 'does not publish a TaskLog when task_id is nil' do
      expect(Legion::Transport::Messages::TaskLog).not_to receive(:new)
      begin
        instance.handle_exception(error)
      rescue Legion::Exception::HandledTask
        nil
      end
    end
  end

  describe '#derive_component_type' do
    let(:test_class) do
      Class.new do
        include Legion::Extensions::Helpers::Logger

        def calling_class_array
          %w[Legion Extensions Eval Runners CodeReview]
        end
      end
    end

    it 'returns :runner for Runners in the namespace' do
      expect(test_class.new.send(:derive_component_type)).to eq(:runner)
    end

    context 'when namespace contains Actor' do
      let(:actor_class) do
        Class.new do
          include Legion::Extensions::Helpers::Logger

          def calling_class_array
            %w[Legion Extensions Eval Actor Interval]
          end
        end
      end

      it 'returns :actor' do
        expect(actor_class.new.send(:derive_component_type)).to eq(:actor)
      end
    end

    context 'when namespace has no recognized boundary' do
      let(:unknown_class) do
        Class.new do
          include Legion::Extensions::Helpers::Logger

          def calling_class_array
            %w[Legion Something Else]
          end
        end
      end

      it 'returns :unknown' do
        expect(unknown_class.new.send(:derive_component_type)).to eq(:unknown)
      end
    end
  end
end
