# frozen_string_literal: true

require 'spec_helper'
require 'legion/workflow/manifest'
require 'legion/fleet/settings_defaults'
require 'legion/fleet/conditioner_rules'
require 'legion/cli/output'
require 'legion/cli/fleet_setup'
require 'legion/cli/fleet_command'

RSpec.describe 'Fleet CLI Integration' do
  describe 'manifest + settings + rules coherence' do
    let(:manifest_path) { Legion::CLI::FleetSetup::MANIFEST_PATH }
    let(:manifest) { Legion::Workflow::Manifest.new(path: manifest_path) }
    let(:settings) { Legion::Fleet::SettingsDefaults.defaults }
    let(:rules) { Legion::Fleet::ConditionerRules.rules }

    it 'manifest is valid' do
      expect(manifest).to be_valid
    end

    it 'manifest defines exactly 10 relationships' do
      expect(manifest.relationships.size).to eq(10)
    end

    it 'manifest max_iterations threshold matches settings default' do
      # Relationship 7 (index 8) uses attempt < 4, which means max 5 total runs
      # Settings default max_iterations is 5
      rel7 = manifest.relationships[8]
      threshold = rel7[:conditions][:all].find { |c| c[:fact] == 'results.pipeline.attempt' }[:value]
      max_iter = settings.dig(:fleet, :implementation, :max_iterations)
      # threshold should be max_iter - 1 (because attempt starts at 0)
      expect(threshold).to eq(max_iter - 1)
    end

    it 'all manifest extensions have corresponding gems in fleet_gems' do
      required_extensions = manifest.relationships.flat_map do |rel|
        [rel[:trigger][:extension], rel[:action][:extension]]
      end.uniq

      gem_names = Legion::CLI::FleetSetup::FLEET_GEMS.map { |g| g.sub('lex-', '') }
      required_extensions.each do |ext|
        expect(gem_names).to include(ext),
                             "Extension '#{ext}' in manifest but 'lex-#{ext}' not in FLEET_GEMS"
      end
    end

    it 'conditioner rules reference valid operators' do
      valid_binary = %w[equal not_equal greater_than less_than greater_or_equal
                        less_or_equal between contains starts_with ends_with
                        matches in_set not_in_set size_equal]
      valid_unary = %w[empty not_empty nil not_nil is_true is_false
                       is_array is_string is_integer]
      valid_ops = valid_binary + valid_unary

      rules.each do |rule|
        next unless rule[:conditions]

        conditions = rule[:conditions][:all] || rule[:conditions][:any] || []
        conditions.each do |cond|
          expect(valid_ops).to include(cond[:operator]),
                               "Rule '#{rule[:name]}' uses invalid operator '#{cond[:operator]}'"
        end
      end
    end

    it 'manifest conditions use valid operators' do
      valid_ops = %w[equal not_equal greater_than less_than greater_or_equal
                     less_or_equal between contains starts_with ends_with
                     matches in_set not_in_set size_equal]

      manifest.relationships.each do |rel|
        next unless rel[:conditions]

        conditions = rel[:conditions][:all] || rel[:conditions][:any] || []
        conditions.each do |cond|
          expect(valid_ops).to include(cond[:operator]),
                               "Relationship '#{rel[:name]}' uses invalid operator '#{cond[:operator]}'"
        end
      end
    end

    it 'manifest conditions prefix facts with results.' do
      manifest.relationships.each do |rel|
        next unless rel[:conditions]

        conditions = rel[:conditions][:all] || rel[:conditions][:any] || []
        conditions.each do |cond|
          expect(cond[:fact]).to start_with('results.'),
                                 "Relationship '#{rel[:name]}' fact '#{cond[:fact]}' missing 'results.' prefix"
        end
      end
    end

    it 'entry relationships allow new chains' do
      # Relationships 1 and 2 (assessor -> planner/developer) must allow new chains
      expect(manifest.relationships[0][:allow_new_chains]).to be true
      expect(manifest.relationships[1][:allow_new_chains]).to be true
    end

    it 'non-entry relationships default to no new chains' do
      # Relationships 3-8 plus 4b,4c (indices 2-9) should not allow new chains
      (2..9).each do |idx|
        rel_name = manifest.relationships[idx][:name]
        expect(manifest.relationships[idx][:allow_new_chains]).to be(false),
                                                                  "Relationship at index #{idx} (#{rel_name}) should not allow new chains"
      end
    end

    it 'boolean condition values are actual booleans not strings' do
      manifest.relationships.each do |rel|
        next unless rel[:conditions]

        conditions = rel[:conditions][:all] || rel[:conditions][:any] || []
        conditions.each do |cond|
          next unless [true, false, 'true', 'false'].include?(cond[:value])

          expect(cond[:value]).to satisfy("be a boolean (not string) in '#{rel[:name]}'") { |v|
            v.is_a?(TrueClass) || v.is_a?(FalseClass)
          }
        end
      end
    end
  end

  describe 'FleetCommand class' do
    it 'has all expected commands' do
      expected = %w[status pending approve add config]
      expected.each do |cmd|
        expect(Legion::CLI::FleetCommand.commands).to have_key(cmd),
                                                      "Missing fleet command: #{cmd}"
      end
    end
  end

  describe 'FleetSetup class' do
    it 'fleet_gems includes all required gems' do
      gems = Legion::CLI::FleetSetup.fleet_gems
      expect(gems.size).to be >= 10
    end

    it 'manifest_path points to existing file' do
      expect(File.exist?(Legion::CLI::FleetSetup.manifest_path)).to be true
    end
  end
end
