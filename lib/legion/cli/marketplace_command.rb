# frozen_string_literal: true

require 'thor'

module Legion
  module CLI
    class Marketplace < Thor
      def self.exit_on_failure?
        true
      end

      desc 'search QUERY', 'Search extension registry'
      def search(query)
        require 'legion/registry'
        results = Legion::Registry.search(query)
        if results.empty?
          say "No extensions found matching '#{query}'", :yellow
          return
        end

        say "Found #{results.size} extension(s):", :green
        results.each do |e|
          status = e.approved? ? '[approved]' : "[#{e.airb_status}]"
          say "  #{e.name.ljust(25)} #{e.version.to_s.ljust(10)} #{status} #{e.description}"
        end
      end

      desc 'info NAME', 'Show extension details'
      def info(name)
        require 'legion/registry'
        entry = Legion::Registry.lookup(name)
        unless entry
          say "Extension '#{name}' not found", :red
          return
        end

        entry.to_h.each { |k, v| say "  #{k}: #{v}" }
      end

      desc 'list', 'List all registered extensions'
      option :approved, type: :boolean, desc: 'Show only approved extensions'
      option :tier, type: :string, desc: 'Filter by risk tier'
      def list
        require 'legion/registry'
        extensions = if options[:approved]
                       Legion::Registry.approved
                     elsif options[:tier]
                       Legion::Registry.by_risk_tier(options[:tier])
                     else
                       Legion::Registry.all
                     end

        if extensions.empty?
          say 'No extensions registered', :yellow
          return
        end

        say "#{extensions.size} extension(s):", :green
        extensions.each do |e|
          say "  #{e.name.ljust(25)} #{e.version.to_s.ljust(10)} [#{e.risk_tier}]"
        end
      end

      desc 'scan NAME', 'Run security scan on extension'
      def scan(name)
        require 'legion/registry/security_scanner'
        scanner = Legion::Registry::SecurityScanner.new
        result = scanner.scan(name: name)

        result[:checks].each do |check|
          color = check[:status] == :fail ? :red : :green
          say "  #{check[:check]}: #{check[:status]} - #{check[:details]}", color
        end

        say result[:passed] ? 'PASSED' : 'FAILED', result[:passed] ? :green : :red
      end
    end
  end
end
