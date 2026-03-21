# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli'
require 'legion/cli/team_command'

RSpec.describe Legion::CLI::Team do
  let(:settings_store) { { teams: {}, team: {} } }
  let(:loader_double) { double('loader') }

  before do
    allow(loader_double).to receive(:settings).and_return(settings_store)
    allow(Legion::Settings).to receive(:dig).and_call_original
    allow(Legion::Settings).to receive(:load)
    allow(Legion::Settings).to receive(:instance_variable_get).with(:@loader).and_return(true)
    allow(Legion::Settings).to receive(:loader).and_return(loader_double)
  end

  def build_command
    described_class.new([], {})
  end

  describe '#list' do
    it 'shows all configured teams' do
      allow(Legion::Settings).to receive(:dig).with(:teams).and_return({ ops: {}, dev: {} })
      cmd = build_command
      expect { cmd.list }.to output(/ops/).to_stdout
    end

    it 'shows a message when no teams are configured' do
      allow(Legion::Settings).to receive(:dig).with(:teams).and_return(nil)
      cmd = build_command
      expect { cmd.list }.to output(/No teams configured/i).to_stdout
    end
  end

  describe '#show' do
    it 'shows team members when team exists' do
      teams = { engineering: { members: %w[alice bob] } }
      allow(Legion::Settings).to receive(:dig).with(:teams).and_return(teams)
      cmd = build_command
      expect { cmd.show('engineering') }.to output(/alice/).to_stdout
    end

    it 'shows error when team does not exist' do
      allow(Legion::Settings).to receive(:dig).with(:teams).and_return({})
      cmd = build_command
      expect { cmd.show('unknown') }.to output(/not found/i).to_stdout
    end

    it 'shows "No members" when team has no members' do
      teams = { empty_team: { members: [] } }
      allow(Legion::Settings).to receive(:dig).with(:teams).and_return(teams)
      cmd = build_command
      expect { cmd.show('empty_team') }.to output(/No members/i).to_stdout
    end
  end

  describe '#current' do
    it 'prints the current team name' do
      allow(Legion::Settings).to receive(:dig).with(:team, :name).and_return('ops')
      cmd = build_command
      expect { cmd.current }.to output(/ops/).to_stdout
    end

    it 'prints "default" when no team is set' do
      allow(Legion::Settings).to receive(:dig).with(:team, :name).and_return(nil)
      cmd = build_command
      expect { cmd.current }.to output(/default/).to_stdout
    end
  end

  describe '#set' do
    it 'updates the active team in settings' do
      settings_hash = { team: {}, teams: {} }
      allow(loader_double).to receive(:settings).and_return(settings_hash)
      cmd = build_command
      expect { cmd.set('platform') }.to output(/set to 'platform'/i).to_stdout
      expect(settings_hash[:team][:name]).to eq('platform')
    end
  end

  describe '#create' do
    it 'creates a new team in settings' do
      teams_hash = {}
      settings_hash = { teams: teams_hash }
      allow(loader_double).to receive(:settings).and_return(settings_hash)
      cmd = build_command
      expect { cmd.create('new-team') }.to output(/created/i).to_stdout
      expect(teams_hash[:'new-team']).to include(name: 'new-team', members: [])
    end

    it 'warns when team already exists' do
      settings_hash = { teams: { ops: { name: 'ops', members: [] } } }
      allow(loader_double).to receive(:settings).and_return(settings_hash)
      cmd = build_command
      expect { cmd.create('ops') }.to output(/already exists/i).to_stdout
    end
  end

  describe '#add_member' do
    it 'adds a user to an existing team' do
      settings_hash = { teams: { ops: { name: 'ops', members: [] } } }
      allow(loader_double).to receive(:settings).and_return(settings_hash)
      cmd = build_command
      expect { cmd.add_member('ops', 'alice') }.to output(/Added alice/i).to_stdout
      expect(settings_hash[:teams][:ops][:members]).to include('alice')
    end

    it 'warns when user is already a member' do
      settings_hash = { teams: { ops: { name: 'ops', members: ['alice'] } } }
      allow(loader_double).to receive(:settings).and_return(settings_hash)
      cmd = build_command
      expect { cmd.add_member('ops', 'alice') }.to output(/already a member/i).to_stdout
    end

    it 'shows error when team does not exist' do
      settings_hash = { teams: {} }
      allow(loader_double).to receive(:settings).and_return(settings_hash)
      cmd = build_command
      expect { cmd.add_member('missing', 'alice') }.to output(/not found/i).to_stdout
    end
  end
end
