# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'legion/cli/chat_command'

module Legion
  module CLI
    class Chat
      module WebSearch
        MAX_RESULTS   = 5
        TIMEOUT       = 10
        AUTO_FETCH    = true

        class SearchError < StandardError; end

        module_function

        def search(query, max_results: MAX_RESULTS, auto_fetch: AUTO_FETCH)
          results = duckduckgo_html(query, max_results)
          raise SearchError, 'No results found.' if results.empty?

          fetched_content = nil
          fetched_content = fetch_top_result(results.first[:url]) if auto_fetch && !results.empty?

          { query: query, results: results, fetched_content: fetched_content }
        end

        def duckduckgo_html(query, max_results)
          uri = URI('https://html.duckduckgo.com/html/')
          uri.query = URI.encode_www_form(q: query)

          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = true
          http.open_timeout = TIMEOUT
          http.read_timeout = TIMEOUT

          request = Net::HTTP::Get.new(uri)
          request['User-Agent'] = 'LegionIO/1.0 (CLI web search)'
          request['Accept'] = 'text/html'

          response = http.request(request)
          raise SearchError, "Search failed: HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

          body = response.body&.dup&.force_encoding('UTF-8') || ''
          parse_duckduckgo_results(body, max_results)
        rescue SocketError => e
          raise SearchError, "Connection failed: #{e.message}"
        rescue Net::OpenTimeout, Net::ReadTimeout
          raise SearchError, "Search timed out (#{TIMEOUT}s)"
        end

        def parse_duckduckgo_results(html, max_results)
          results = []

          html.scan(%r{<a[^>]+class="result__a"[^>]*href="([^"]*)"[^>]*>(.*?)</a>}mi) do |url, title|
            clean_title = strip_tags(title).strip
            next if clean_title.empty?

            real_url = extract_real_url(url)
            next unless real_url

            results << { title: clean_title, url: real_url }
            break if results.length >= max_results
          end

          # Extract snippets
          snippets = []
          html.scan(%r{<a[^>]+class="result__snippet"[^>]*>(.*?)</a>}mi) do |snippet|
            snippets << strip_tags(snippet.first).strip
          end

          results.each_with_index do |r, i|
            r[:snippet] = snippets[i] || ''
          end

          results
        end

        def extract_real_url(ddg_url)
          uri = URI.parse(ddg_url)
          return ddg_url unless uri.host&.end_with?('.duckduckgo.com') || uri.host == 'duckduckgo.com'

          match = ddg_url.match(/uddg=([^&]+)/)
          return nil unless match

          URI.decode_www_form_component(match[1])
        rescue StandardError => e
          Legion::Logging.debug("WebSearch#extract_real_url failed: #{e.message}") if defined?(Legion::Logging)
          nil
        end

        def strip_tags(html)
          html.gsub(/<[^>]+>/, '').gsub('&amp;', '&').gsub('&lt;', '<').gsub('&gt;', '>')
              .gsub('&quot;', '"').gsub('&#39;', "'").gsub('&nbsp;', ' ')
        end

        def fetch_top_result(url)
          require 'legion/cli/chat/web_fetch'
          WebFetch.fetch(url)
        rescue StandardError => e
          Legion::Logging.debug("WebSearch#fetch_top_result failed for #{url}: #{e.message}") if defined?(Legion::Logging)
          nil
        end
      end
    end
  end
end
