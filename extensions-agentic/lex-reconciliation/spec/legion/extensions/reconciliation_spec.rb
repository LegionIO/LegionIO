# frozen_string_literal: true

RSpec.describe Legion::Extensions::Reconciliation do
  it 'has a version number' do
    expect(Legion::Extensions::Reconciliation::VERSION).not_to be_nil
  end

  it 'defines DriftLog' do
    expect(defined?(Legion::Extensions::Reconciliation::DriftLog)).to eq('constant')
  end

  it 'defines Runners::DriftChecker' do
    expect(defined?(Legion::Extensions::Reconciliation::Runners::DriftChecker)).to eq('constant')
  end

  it 'defines Actors::ReconciliationCycle' do
    expect(defined?(Legion::Extensions::Reconciliation::Actors::ReconciliationCycle)).to eq('constant')
  end
end
