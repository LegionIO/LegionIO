# frozen_string_literal: true

require 'thor'

module Legion
  module CLI
    class Team < Thor
      def self.exit_on_failure?
        true
      end

      desc 'list', 'List all teams'
      def list
        require 'legion/settings'
        require 'legion/team'
        teams = Legion::Team.list
        if teams.empty?
          say 'No teams configured.', :yellow
          return
        end
        say 'Teams', :green
        say '-' * 20
        teams.each { |t| say "  #{t}" }
      end

      desc 'show TEAM', 'Show team details and members'
      def show(name)
        require 'legion/settings'
        require 'legion/team'
        team = Legion::Team.find(name)
        if team.nil?
          say "Team '#{name}' not found.", :red
          return
        end
        say "Team: #{name}", :green
        say '-' * 20
        members = team[:members] || []
        if members.empty?
          say '  No members.'
        else
          members.each { |m| say "  #{m}" }
        end
      end

      desc 'current', 'Show the current active team'
      def current
        require 'legion/settings'
        require 'legion/team'
        say Legion::Team.current
      end

      desc 'set TEAM', 'Set the active team in settings'
      def set(name)
        require 'legion/settings'
        require 'legion/team'
        Legion::Settings.load unless Legion::Settings.instance_variable_get(:@loader)
        Legion::Settings.loader.settings[:team] ||= {}
        Legion::Settings.loader.settings[:team][:name] = name
        say "Active team set to '#{name}'.", :green
      end

      desc 'create TEAM', 'Create a new team'
      def create(name)
        require 'legion/settings'
        require 'legion/team'
        Legion::Settings.load unless Legion::Settings.instance_variable_get(:@loader)
        teams = Legion::Settings.loader.settings[:teams] || {}
        if teams.key?(name.to_sym)
          say "Team '#{name}' already exists.", :yellow
          return
        end
        teams[name.to_sym] = { name: name, members: [] }
        Legion::Settings.loader.settings[:teams] = teams
        say "Team '#{name}' created.", :green
      end

      desc 'add-member TEAM USER', 'Add a member to a team'
      map 'add-member' => :add_member
      def add_member(team_name, user)
        require 'legion/settings'
        require 'legion/team'
        Legion::Settings.load unless Legion::Settings.instance_variable_get(:@loader)
        teams = Legion::Settings.loader.settings[:teams] || {}
        sym = team_name.to_sym
        unless teams.key?(sym)
          say "Team '#{team_name}' not found.", :red
          return
        end
        teams[sym][:members] ||= []
        if teams[sym][:members].include?(user)
          say "#{user} is already a member of '#{team_name}'.", :yellow
          return
        end
        teams[sym][:members] << user
        Legion::Settings.loader.settings[:teams] = teams
        say "Added #{user} to team '#{team_name}'.", :green
      end
    end
  end
end
