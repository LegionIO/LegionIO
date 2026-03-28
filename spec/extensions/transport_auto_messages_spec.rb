# frozen_string_literal: true

require 'spec_helper'
require 'legion/extensions/transport'
require 'legion/extensions/definitions'

RSpec.describe Legion::Extensions::Transport do
  # Minimal dummy builder that satisfies the mixin's dependencies without
  # requiring a live RabbitMQ connection.
  let(:dummy_builder) do
    transport_mod = Module.new
    transport_mod.const_set('Messages', Module.new)

    Class.new do
      include Legion::Extensions::Transport

      define_method(:transport_class) { transport_mod }
      define_method(:amqp_prefix) { 'lex.test_ext' }

      def log
        @log ||= Logger.new(nil)
      end
    end.new
  end

  # A runner module with definition_for returning inputs for :process_item
  # but no inputs for :internal_helper.
  let(:runner_with_definitions) do
    mod = Module.new
    mod.extend(Legion::Extensions::Definitions)
    mod.definition(:process_item, inputs: { payload: { type: :string } })
    # :internal_helper intentionally has no definition (returns nil)
    mod.define_method(:process_item) { nil }
    mod.define_method(:internal_helper) { nil }
    mod
  end

  # A runner module with definition_for returning empty inputs
  let(:runner_with_empty_inputs) do
    mod = Module.new
    mod.extend(Legion::Extensions::Definitions)
    mod.definition(:no_input_method, inputs: {})
    mod.define_method(:no_input_method) { nil }
    mod
  end

  # A runner module without definition_for at all
  let(:runner_without_definitions) do
    Module.new do
      def some_method; end
    end
  end

  def set_runners(builder, runners_hash)
    builder.instance_variable_set(:@runners, runners_hash)
  end

  describe '#auto_generate_messages' do
    context 'when @runners is not set' do
      it 'returns without error' do
        expect { dummy_builder.auto_generate_messages }.not_to raise_error
      end
    end

    context 'when @runners is an empty hash' do
      before { set_runners(dummy_builder, {}) }

      it 'returns without error' do
        expect { dummy_builder.auto_generate_messages }.not_to raise_error
      end

      it 'leaves Messages module empty' do
        dummy_builder.auto_generate_messages
        expect(dummy_builder.transport_class::Messages.constants).to be_empty
      end
    end

    context 'when a runner method has definition inputs' do
      before do
        set_runners(dummy_builder, {
                      test_runner: {
                        runner_name:   'test_runner',
                        runner_module: runner_with_definitions
                      }
                    })
        dummy_builder.auto_generate_messages
      end

      it 'creates a message class for the method with inputs' do
        expect(dummy_builder.transport_class::Messages.const_defined?('TestRunnerProcessItem', false)).to be true
      end

      it 'creates a class that inherits from Legion::Transport::Message' do
        klass = dummy_builder.transport_class::Messages::TestRunnerProcessItem
        expect(klass.ancestors).to include(Legion::Transport::Message)
      end

      it 'sets the correct routing_key on an instance of the generated class' do
        instance = dummy_builder.transport_class::Messages::TestRunnerProcessItem.allocate
        expect(instance.routing_key).to eq('lex.test_ext.runners.test_runner.process_item')
      end

      it 'sets the correct exchange_name on an instance of the generated class' do
        instance = dummy_builder.transport_class::Messages::TestRunnerProcessItem.allocate
        expect(instance.exchange_name).to eq('lex.test_ext')
      end
    end

    context 'when a runner method has no definition' do
      before do
        set_runners(dummy_builder, {
                      test_runner: {
                        runner_name:   'test_runner',
                        runner_module: runner_with_definitions
                      }
                    })
        dummy_builder.auto_generate_messages
      end

      it 'does not create a message class for the method without definition inputs' do
        expect(dummy_builder.transport_class::Messages.const_defined?('TestRunnerInternalHelper', false)).to be false
      end
    end

    context 'when a runner method has an empty inputs hash' do
      before do
        set_runners(dummy_builder, {
                      no_input_runner: {
                        runner_name:   'no_input_runner',
                        runner_module: runner_with_empty_inputs
                      }
                    })
        dummy_builder.auto_generate_messages
      end

      it 'does not create a message class for a method with empty inputs' do
        expect(dummy_builder.transport_class::Messages.const_defined?('NoInputRunnerNoInputMethod', false)).to be false
      end
    end

    context 'when runner_module does not respond to definition_for' do
      before do
        set_runners(dummy_builder, {
                      plain_runner: {
                        runner_name:   'plain_runner',
                        runner_module: runner_without_definitions
                      }
                    })
        dummy_builder.auto_generate_messages
      end

      it 'skips the runner without error' do
        expect { dummy_builder.auto_generate_messages }.not_to raise_error
      end

      it 'creates no message classes' do
        expect(dummy_builder.transport_class::Messages.constants).to be_empty
      end
    end

    context 'when runner_module is nil' do
      before do
        set_runners(dummy_builder, {
                      nil_runner: {
                        runner_name:   'nil_runner',
                        runner_module: nil
                      }
                    })
      end

      it 'skips the nil runner without error' do
        expect { dummy_builder.auto_generate_messages }.not_to raise_error
      end
    end

    context 'when an explicit message class already exists' do
      let(:explicit_class) { Class.new(Legion::Transport::Message) }

      before do
        dummy_builder.transport_class::Messages.const_set('TestRunnerProcessItem', explicit_class)
        set_runners(dummy_builder, {
                      test_runner: {
                        runner_name:   'test_runner',
                        runner_module: runner_with_definitions
                      }
                    })
        dummy_builder.auto_generate_messages
      end

      it 'does not overwrite the explicit message class' do
        expect(dummy_builder.transport_class::Messages::TestRunnerProcessItem).to be(explicit_class)
      end
    end

    context 'with a multi-word runner and method name' do
      let(:multi_word_runner) do
        mod = Module.new
        mod.extend(Legion::Extensions::Definitions)
        mod.definition(:send_alert_email, inputs: { to: { type: :string } })
        mod.define_method(:send_alert_email) { nil }
        mod
      end

      before do
        set_runners(dummy_builder, {
                      alert_notifier: {
                        runner_name:   'alert_notifier',
                        runner_module: multi_word_runner
                      }
                    })
        dummy_builder.auto_generate_messages
      end

      it 'CamelCases both the runner name and method name for the class constant' do
        expect(dummy_builder.transport_class::Messages.const_defined?('AlertNotifierSendAlertEmail', false)).to be true
      end
    end
  end
end
