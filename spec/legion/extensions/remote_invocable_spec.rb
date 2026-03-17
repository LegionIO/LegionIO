# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Extensions do
  describe '.resolve_remote_invocable' do
    before do
      allow(Legion::Settings).to receive(:dig).with(:extensions, anything).and_return(nil)
    end

    context 'level 5: default' do
      it 'returns true when nothing is configured' do
        expect(described_class.send(:resolve_remote_invocable, :test_ext)).to be true
      end
    end

    context 'level 4: extension module method' do
      it 'returns false when extension declares remote_invocable? false' do
        ext = Module.new { def self.remote_invocable? = false }
        expect(described_class.send(:resolve_remote_invocable, :test_ext, extension: ext)).to be false
      end

      it 'returns true when extension declares remote_invocable? true' do
        ext = Module.new { def self.remote_invocable? = true }
        expect(described_class.send(:resolve_remote_invocable, :test_ext, extension: ext)).to be true
      end
    end

    context 'level 3: runner class method' do
      it 'returns false when runner class declares remote_invocable? false' do
        runner = Module.new { def self.remote_invocable? = false }
        ext = Module.new { def self.remote_invocable? = true }
        expect(described_class.send(:resolve_remote_invocable, :test_ext, runner_class: runner, extension: ext)).to be false
      end

      it 'does not use remote_invocable? inherited from a superclass singleton chain' do
        parent = Class.new { def self.remote_invocable? = false }
        child = Class.new(parent)
        # child inherits remote_invocable? from parent but does not define it directly
        ext = Module.new { def self.remote_invocable? = true }
        expect(described_class.send(:resolve_remote_invocable, :test_ext, runner_class: child, extension: ext)).to be true
      end

      it 'honors remote_invocable? defined via extend' do
        mod = Module.new { def remote_invocable? = false }
        runner = Module.new { extend mod }
        # runner has remote_invocable? via extend — should be used at level 3
        ext = Module.new { def self.remote_invocable? = true }
        expect(described_class.send(:resolve_remote_invocable, :test_ext, runner_class: runner, extension: ext)).to be false
      end

      it 'runner class method overrides extension module method' do
        runner = Module.new { def self.remote_invocable? = false }
        ext = Module.new { def self.remote_invocable? = true }
        result = described_class.send(:resolve_remote_invocable, :test_ext, runner_class: runner, extension: ext)
        expect(result).to be false
      end
    end

    context 'level 2: extension settings' do
      before do
        allow(Legion::Settings).to receive(:dig).with(:extensions, :test_ext).and_return({ remote_invocable: false })
      end

      it 'returns false from settings' do
        expect(described_class.send(:resolve_remote_invocable, :test_ext)).to be false
      end

      it 'extension settings override extension module method' do
        ext = Module.new { def self.remote_invocable? = true }
        expect(described_class.send(:resolve_remote_invocable, :test_ext, extension: ext)).to be false
      end
    end

    context 'level 1: per-runner settings (runner-specific override)' do
      before do
        allow(Legion::Settings).to receive(:dig).with(:extensions, :test_ext).and_return({
                                                                                           runners: { my_runner: { remote_invocable: false } }
                                                                                         })
      end

      it 'returns false for the specific runner configured' do
        expect(described_class.send(:resolve_remote_invocable, :test_ext, actor_name: :my_runner)).to be false
      end

      it 'falls through to lower levels for unconfigured runners' do
        # No extension-level setting, no runner class, no extension module — falls to default true
        expect(described_class.send(:resolve_remote_invocable, :test_ext, actor_name: :other_runner)).to be true
      end

      it 'per-runner settings override extension module method' do
        ext = Module.new { def self.remote_invocable? = true }
        expect(described_class.send(:resolve_remote_invocable, :test_ext, actor_name: :my_runner, extension: ext)).to be false
      end
    end
  end

  describe '@local_tasks' do
    it 'is accessible via attr_reader' do
      expect(described_class).to respond_to(:local_tasks)
    end

    it 'is initialized as an array after hook_extensions' do
      described_class.instance_variable_set(:@local_tasks, [])
      expect(described_class.local_tasks).to be_an(Array)
    end
  end
end
