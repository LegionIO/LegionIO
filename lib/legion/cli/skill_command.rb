# frozen_string_literal: true

require 'thor'
require 'net/http'
require 'json'
require 'uri'

module Legion
  module CLI
    class Skill < Thor
      def self.exit_on_failure?
        true
      end

      include Legion::CLI::Connection

      desc 'list', 'List all registered skills'
      def list
        ensure_settings
        response = daemon_get('/api/skills')
        unless response.is_a?(::Net::HTTPSuccess)
          say "Error fetching skills: #{response.code}", :red
          exit 1
        end

        skills = ::JSON.parse(response.body, symbolize_names: true)[:data] || []
        if skills.empty?
          say 'No skills registered. Start the daemon with legion-llm loaded.'
          return
        end

        skills.each do |s|
          say "  #{s[:namespace]}:#{s[:name]}  [#{s[:trigger]}]  #{s[:description]}", :green
        end
      end

      desc 'show NAMESPACE:NAME', 'Show skill details'
      def show(name)
        ensure_settings
        ns, nm = name.include?(':') ? name.split(':', 2) : ['default', name]
        response = daemon_get("/api/skills/#{ns}/#{nm}")
        unless response.is_a?(::Net::HTTPSuccess)
          say "Skill '#{name}' not found", :red
          exit 1
        end

        result = ::JSON.parse(response.body, symbolize_names: true)
        data   = result[:data] || {}
        say "Name:        #{data[:namespace]}:#{data[:name]}", :green
        say "Description: #{data[:description]}"
        say "Trigger:     #{data[:trigger]}"
        say "Steps:       #{Array(data[:steps]).join(', ')}"
      end

      desc 'create NAME', 'Scaffold a new skill file'
      def create(name)
        require 'fileutils'
        dir = '.legion/skills'
        FileUtils.mkdir_p(dir)
        path = ::File.join(dir, "#{name}.md")

        if ::File.exist?(path)
          say "Skill already exists: #{path}", :red
          return
        end

        content = <<~SKILL
          ---
          name: #{name}
          namespace: local
          description: Describe what this skill does
          trigger: on_demand
          ---

          You are a helpful assistant. Describe the skill's behavior here.
        SKILL

        ::File.write(path, content)
        say "Created: #{path}", :green
      end

      desc 'run NAME', 'Run a skill via the daemon'
      map 'run' => :run_skill
      def run_skill(name)
        ensure_settings
        url     = "#{daemon_base_url}/api/skills/invoke"
        payload = { skill_name: name }.to_json

        response = ::Net::HTTP.post(
          ::URI.parse(url),
          payload,
          'Content-Type' => 'application/json'
        )

        if response.is_a?(::Net::HTTPSuccess)
          result = ::JSON.parse(response.body, symbolize_names: true)
          say result.dig(:data, :content).to_s
        else
          say "Error: #{response.code} #{response.body}", :red
          exit 1
        end
      end

      private

      def daemon_base_url
        host = Legion::Settings.dig(:api, :host) || 'localhost'
        port = Legion::Settings.dig(:api, :port) || 4567
        "http://#{host}:#{port}"
      end

      def daemon_get(path)
        uri = ::URI.parse("#{daemon_base_url}#{path}")
        ::Net::HTTP.get_response(uri)
      end
    end
  end
end
