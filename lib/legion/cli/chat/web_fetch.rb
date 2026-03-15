# frozen_string_literal: true

require 'net/http'
require 'uri'

module Legion
  module CLI
    class Chat
      module WebFetch
        MAX_BODY      = 1_048_576 # 1 MB
        MAX_REDIRECTS = 5
        TIMEOUT       = 15
        CONTEXT_LIMIT = 12_000 # chars injected into conversation

        class FetchError < StandardError; end

        module_function

        def fetch(url)
          uri = parse_uri(url)
          body, content_type = follow_redirects(uri)

          text = if html?(content_type)
                   html_to_markdown(body)
                 else
                   body
                 end

          truncate(text.strip, CONTEXT_LIMIT)
        end

        def parse_uri(url)
          url = "https://#{url}" unless url.match?(%r{\Ahttps?://})
          uri = URI.parse(url)
          raise FetchError, "Invalid URL: #{url}" unless uri.is_a?(URI::HTTP)

          uri
        rescue URI::InvalidURIError
          raise FetchError, "Invalid URL: #{url}"
        end

        def follow_redirects(uri, limit = MAX_REDIRECTS)
          raise FetchError, 'Too many redirects' if limit.zero?

          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = (uri.scheme == 'https')
          http.open_timeout = TIMEOUT
          http.read_timeout = TIMEOUT

          request = Net::HTTP::Get.new(uri.request_uri)
          request['User-Agent'] = 'LegionIO/1.0 (CLI web fetch)'
          request['Accept']     = 'text/html, text/plain, application/json'

          response = http.request(request)

          case response
          when Net::HTTPRedirection
            location = response['location']
            new_uri = URI.parse(location)
            new_uri = URI.join(uri, location) unless new_uri.host
            follow_redirects(new_uri, limit - 1)
          when Net::HTTPSuccess
            body = response.body&.dup&.force_encoding('UTF-8') || ''
            raise FetchError, "Response too large (#{body.bytesize} bytes)" if body.bytesize > MAX_BODY

            [body, response['content-type']]
          else
            raise FetchError, "HTTP #{response.code}: #{response.message}"
          end
        rescue SocketError => e
          raise FetchError, "Connection failed: #{e.message}"
        rescue Net::OpenTimeout, Net::ReadTimeout
          raise FetchError, "Request timed out (#{TIMEOUT}s)"
        rescue OpenSSL::SSL::SSLError => e
          raise FetchError, "SSL error: #{e.message}"
        end

        def html?(content_type)
          content_type&.include?('text/html') || false
        end

        def html_to_markdown(html)
          text = html.dup
          strip_invisible!(text)
          convert_headings!(text)
          convert_links!(text)
          convert_lists!(text)
          convert_formatting!(text)
          convert_blocks!(text)
          strip_remaining_tags!(text)
          clean_whitespace(text)
        end

        def strip_invisible!(text)
          text.gsub!(%r{<script[^>]*>.*?</script>}mi, '')
          text.gsub!(%r{<style[^>]*>.*?</style>}mi, '')
          text.gsub!(%r{<nav[^>]*>.*?</nav>}mi, '')
          text.gsub!(%r{<footer[^>]*>.*?</footer>}mi, '')
          text.gsub!(/<!--.*?-->/m, '')
        end

        def convert_headings!(text)
          (1..6).each do |n|
            prefix = '#' * n
            text.gsub!(%r{<h#{n}[^>]*>(.*?)</h#{n}>}mi, "\n#{prefix} \\1\n")
          end
        end

        def convert_links!(text)
          text.gsub!(%r{<a[^>]*href=["']([^"']*)["'][^>]*>(.*?)</a>}mi, '[\\2](\\1)')
        end

        def convert_lists!(text)
          text.gsub!(%r{<li[^>]*>(.*?)</li>}mi, "\n- \\1")
          text.gsub!(%r{</?[ou]l[^>]*>}mi, "\n")
        end

        def convert_formatting!(text)
          text.gsub!(%r{<(b|strong)[^>]*>(.*?)</\1>}mi, '**\\2**')
          text.gsub!(%r{<(i|em)[^>]*>(.*?)</\1>}mi, '*\\2*')
          text.gsub!(%r{<code[^>]*>(.*?)</code>}mi, '`\\1`')
        end

        def convert_blocks!(text)
          text.gsub!(%r{<pre[^>]*>(.*?)</pre>}mi, "\n```\n\\1\n```\n")
          text.gsub!(%r{<blockquote[^>]*>(.*?)</blockquote>}mi, "\n> \\1\n")
          text.gsub!(/<p[^>]*>/mi, "\n\n")
          text.gsub!(%r{</p>}mi, "\n")
          text.gsub!(%r{<br\s*/?>}, "\n")
          text.gsub!(%r{<hr\s*/?>}, "\n---\n")
        end

        def strip_remaining_tags!(text)
          text.gsub!(/<[^>]+>/, '')
        end

        def clean_whitespace(text)
          text = text.gsub('&nbsp;', ' ')
                     .gsub('&amp;', '&')
                     .gsub('&lt;', '<')
                     .gsub('&gt;', '>')
                     .gsub('&quot;', '"')
                     .gsub('&#39;', "'")
          text.gsub(/\n{3,}/, "\n\n").gsub(/ +/, ' ').strip
        end

        def truncate(text, limit)
          return text if text.length <= limit

          text[0, limit] + "\n\n[... truncated at #{limit} characters]"
        end
      end
    end
  end
end
