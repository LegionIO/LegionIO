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

      it 'returns a logger instance' do
        expect(subject.log).to respond_to(:info, :warn, :error, :debug)
      end

      it 'memoizes the logger' do
        expect(subject.log).to be(subject.log)
      end
    end

    context 'when the object has Base included (derives segments from class name)' do
      subject { legacy_class.new }

      it 'returns a logger instance' do
        expect(subject.log).to respond_to(:info, :warn, :error, :debug)
      end
    end
  end

  describe '#handle_runner_exception' do
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

    before do
      stub_const('Legion::Exception::HandledTask', Class.new(StandardError)) unless defined?(Legion::Exception::HandledTask)
      allow(instance).to receive(:handle_exception)
    end

    it 'delegates to handle_exception from the gem' do
      expect(instance).to receive(:handle_exception).with(error, task_id: nil)
      begin
        instance.handle_runner_exception(error)
      rescue Legion::Exception::HandledTask
        nil
      end
    end

    it 'raises HandledTask' do
      expect { instance.handle_runner_exception(error) }.to raise_error(Legion::Exception::HandledTask)
    end

    it 'passes task_id through to handle_exception' do
      expect(instance).to receive(:handle_exception).with(error, task_id: 123)
      msg_double = instance_double('Legion::Transport::Messages::TaskLog', publish: true)
      allow(Legion::Transport::Messages::TaskLog).to receive(:new).and_return(msg_double)
      begin
        instance.handle_runner_exception(error, task_id: 123)
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
        instance.handle_runner_exception(error, task_id: 99)
      rescue Legion::Exception::HandledTask
        nil
      end
    end

    it 'does not publish a TaskLog when task_id is nil' do
      expect(Legion::Transport::Messages::TaskLog).not_to receive(:new)
      begin
        instance.handle_runner_exception(error)
      rescue Legion::Exception::HandledTask
        nil
      end
    end
  end
end
