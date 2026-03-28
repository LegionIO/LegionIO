# frozen_string_literal: true

require 'spec_helper'
require 'legion/extensions/actors/dsl'

RSpec.describe Legion::Extensions::Actors::Dsl do
  let(:base_class) do
    Class.new do
      extend Legion::Extensions::Actors::Dsl

      define_dsl_accessor :time, default: 9
      define_dsl_accessor :run_now, default: true
      define_dsl_accessor :enabled, default: true
    end
  end

  it 'returns default when not set' do
    expect(base_class.time).to eq(9)
  end

  it 'sets and returns a value' do
    child = Class.new(base_class) { time 30 }
    expect(child.time).to eq(30)
  end

  it 'does not affect parent class' do
    child = Class.new(base_class) { time 30 }
    expect(base_class.time).to eq(9)
    expect(child.time).to eq(30)
  end

  it 'works as instance method too (reads class value)' do
    child = Class.new(base_class) { time 30 }
    instance = child.new
    expect(instance.time).to eq(30)
  end

  it 'allows boolean accessors' do
    child = Class.new(base_class) { run_now false }
    expect(child.run_now).to be false
  end
end
