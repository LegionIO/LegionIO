# frozen_string_literal: true

require 'spec_helper'
require 'legion/workflow/manifest'

RSpec.describe 'Fleet Manifest' do
  let(:manifest_path) { File.expand_path('../../../lib/legion/fleet/manifest.yml', __dir__) }
  let(:manifest) { Legion::Workflow::Manifest.new(path: manifest_path) }

  it 'loads without error' do
    expect { manifest }.not_to raise_error
  end

  it 'has the correct name' do
    expect(manifest.name).to eq('fleet-pipeline')
  end

  it 'has a version' do
    expect(manifest.version).to match(/\A\d+\.\d+\.\d+\z/)
  end

  it 'has a description' do
    expect(manifest.description).not_to be_nil
  end

  it 'defines exactly 10 relationships' do
    expect(manifest.relationships.size).to eq(10)
  end

  it 'is valid' do
    expect(manifest).to be_valid
  end

  it 'requires fleet extension gems' do
    expect(manifest.requires).to include('lex-assessor', 'lex-planner', 'lex-developer', 'lex-validator')
  end

  describe 'relationship 1: assessor -> planner (planning enabled)' do
    subject(:rel) { manifest.relationships[0] }

    it 'triggers from assessor.assess' do
      expect(rel[:trigger]).to eq({ extension: 'assessor', runner: 'assessor', function: 'assess' })
    end

    it 'routes to planner.plan' do
      expect(rel[:action]).to eq({ extension: 'planner', runner: 'planner', function: 'plan' })
    end

    it 'conditions on planning.enabled == true' do
      expect(rel[:conditions][:all]).to include(
        { fact: 'results.config.planning.enabled', operator: 'equal', value: true }
      )
    end

    it 'allows new chains (entry relationship)' do
      expect(rel[:allow_new_chains]).to be true
    end
  end

  describe 'relationship 2: assessor -> developer (planning disabled)' do
    subject(:rel) { manifest.relationships[1] }

    it 'triggers from assessor.assess' do
      expect(rel[:trigger]).to eq({ extension: 'assessor', runner: 'assessor', function: 'assess' })
    end

    it 'routes to developer.implement' do
      expect(rel[:action]).to eq({ extension: 'developer', runner: 'developer', function: 'implement' })
    end

    it 'conditions on planning.enabled == false' do
      expect(rel[:conditions][:all]).to include(
        { fact: 'results.config.planning.enabled', operator: 'equal', value: false }
      )
    end

    it 'allows new chains (entry relationship)' do
      expect(rel[:allow_new_chains]).to be true
    end
  end

  describe 'relationship 3: planner -> developer' do
    subject(:rel) { manifest.relationships[2] }

    it 'triggers from planner.plan' do
      expect(rel[:trigger]).to eq({ extension: 'planner', runner: 'planner', function: 'plan' })
    end

    it 'routes to developer.implement' do
      expect(rel[:action]).to eq({ extension: 'developer', runner: 'developer', function: 'implement' })
    end

    it 'does not allow new chains (inherits from entry)' do
      expect(rel[:allow_new_chains]).to be false
    end
  end

  describe 'relationship 4: developer -> validator (validation enabled)' do
    subject(:rel) { manifest.relationships[3] }

    it 'triggers from developer.implement' do
      expect(rel[:trigger]).to eq({ extension: 'developer', runner: 'developer', function: 'implement' })
    end

    it 'routes to validator.validate' do
      expect(rel[:action]).to eq({ extension: 'validator', runner: 'validator', function: 'validate' })
    end

    it 'conditions on validation.enabled == true' do
      expect(rel[:conditions][:all]).to include(
        { fact: 'results.config.validation.enabled', operator: 'equal', value: true }
      )
    end
  end

  describe 'relationship 4b: developer feedback -> validator (validation enabled)' do
    subject(:rel) { manifest.relationships[4] }

    it 'triggers from developer.incorporate_feedback' do
      expect(rel[:trigger]).to eq({ extension: 'developer', runner: 'developer', function: 'incorporate_feedback' })
    end

    it 'routes to validator.validate' do
      expect(rel[:action]).to eq({ extension: 'validator', runner: 'validator', function: 'validate' })
    end

    it 'conditions on validation.enabled == true' do
      expect(rel[:conditions][:all]).to include(
        { fact: 'results.config.validation.enabled', operator: 'equal', value: true }
      )
    end

    it 'does not allow new chains' do
      expect(rel[:allow_new_chains]).to be false
    end
  end

  describe 'relationship 4c: developer feedback -> escalate (escalate flag)' do
    subject(:rel) { manifest.relationships[5] }

    it 'triggers from developer.incorporate_feedback' do
      expect(rel[:trigger]).to eq({ extension: 'developer', runner: 'developer', function: 'incorporate_feedback' })
    end

    it 'routes to assessor.escalate' do
      expect(rel[:action]).to eq({ extension: 'assessor', runner: 'assessor', function: 'escalate' })
    end

    it 'conditions on results.escalate == true' do
      expect(rel[:conditions][:all]).to include(
        { fact: 'results.escalate', operator: 'equal', value: true }
      )
    end

    it 'does not allow new chains' do
      expect(rel[:allow_new_chains]).to be false
    end
  end

  describe 'relationship 5: developer -> ship (validation disabled)' do
    subject(:rel) { manifest.relationships[6] }

    it 'triggers from developer.implement' do
      expect(rel[:trigger]).to eq({ extension: 'developer', runner: 'developer', function: 'implement' })
    end

    it 'routes to ship.finalize' do
      expect(rel[:action]).to eq({ extension: 'developer', runner: 'ship', function: 'finalize' })
    end

    it 'conditions on validation.enabled == false' do
      expect(rel[:conditions][:all]).to include(
        { fact: 'results.config.validation.enabled', operator: 'equal', value: false }
      )
    end
  end

  describe 'relationship 6: validator -> ship (approved)' do
    subject(:rel) { manifest.relationships[7] }

    it 'triggers from validator.validate' do
      expect(rel[:trigger]).to eq({ extension: 'validator', runner: 'validator', function: 'validate' })
    end

    it 'routes to ship.finalize' do
      expect(rel[:action]).to eq({ extension: 'developer', runner: 'ship', function: 'finalize' })
    end

    it 'conditions on verdict == approved' do
      expect(rel[:conditions][:all]).to include(
        { fact: 'results.pipeline.review_result.verdict', operator: 'equal', value: 'approved' }
      )
    end
  end

  describe 'relationship 7: validator -> developer feedback (rejected, under limit)' do
    subject(:rel) { manifest.relationships[8] }

    it 'routes to developer.incorporate_feedback' do
      expect(rel[:action]).to eq({ extension: 'developer', runner: 'developer', function: 'incorporate_feedback' })
    end

    it 'conditions on verdict == rejected AND attempt < 4' do
      conditions = rel[:conditions][:all]
      expect(conditions).to include(
        { fact: 'results.pipeline.review_result.verdict', operator: 'equal', value: 'rejected' }
      )
      expect(conditions).to include(
        { fact: 'results.pipeline.attempt', operator: 'less_than', value: 4 }
      )
    end

    it 'does not allow new chains (feedback stays in existing chain)' do
      expect(rel[:allow_new_chains]).to be false
    end
  end

  describe 'relationship 8: validator -> escalate (rejected, at limit)' do
    subject(:rel) { manifest.relationships[9] }

    it 'routes to assessor.escalate' do
      expect(rel[:action]).to eq({ extension: 'assessor', runner: 'assessor', function: 'escalate' })
    end

    it 'conditions on verdict == rejected AND attempt >= 4' do
      conditions = rel[:conditions][:all]
      expect(conditions).to include(
        { fact: 'results.pipeline.review_result.verdict', operator: 'equal', value: 'rejected' }
      )
      expect(conditions).to include(
        { fact: 'results.pipeline.attempt', operator: 'greater_or_equal', value: 4 }
      )
    end
  end

  describe 'settings defaults' do
    it 'includes fleet settings' do
      expect(manifest.settings).to include(:fleet)
    end

    it 'enables escalation in LLM routing' do
      expect(manifest.settings.dig(:fleet, :llm, :routing, :escalation, :enabled)).to be true
    end
  end
end
