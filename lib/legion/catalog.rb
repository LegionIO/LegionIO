# frozen_string_literal: true

require 'net/http'
require 'uri'

module Legion
  module Catalog
    class << self
      def register_tools(catalog_url:, api_key:)
        tools = collect_mcp_tools
        Legion::Logging.info "[Catalog] registering #{tools.size} tools to #{catalog_url}" if defined?(Legion::Logging)
        post_json("#{catalog_url}/api/tools", { tools: tools }, api_key)
      end

      def register_workers(catalog_url:, api_key:, workers:)
        entries = workers.map do |w|
          { id: w[:worker_id], status: w[:status], capabilities: w[:capabilities] || [] }
        end
        Legion::Logging.info "[Catalog] registering #{entries.size} workers to #{catalog_url}" if defined?(Legion::Logging)
        post_json("#{catalog_url}/api/workers", { workers: entries }, api_key)
      end

      def collect_mcp_tools
        return [] unless defined?(Legion::MCP) && Legion::MCP.respond_to?(:tools)

        Legion::MCP.tools.map { |t| { name: t[:name], description: t[:description] } }
      rescue StandardError
        []
      end

      private

      def post_json(url, body, api_key)
        uri = URI(url)
        req = Net::HTTP::Post.new(uri)
        req['Authorization'] = "Bearer #{api_key}"
        req['Content-Type'] = 'application/json'
        req.body = Legion::JSON.dump(body)

        response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|
          http.request(req)
        end
        { status: response.code.to_i, body: response.body }
      rescue StandardError => e
        { error: e.message }
      end
    end
  end
end
