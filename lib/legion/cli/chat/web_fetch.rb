# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'legion/cli/chat_command'

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
          %w[script style nav footer].each { |tag| strip_tag_blocks!(text, tag) }
          text.gsub!(/<!--.*?-->/m, '')
        end

        def strip_tag_blocks!(text, tag)
          loop do
            open_idx = text.index(/<#{tag}[\s>]/mi)
            break unless open_idx

            close_pat = %r{</#{tag}\s*>}mi
            close_match = close_pat.match(text, open_idx)
            if close_match
              text[open_idx..(close_match.end(0) - 1)] = ''
            else
              text[open_idx..] = ''
            end
          end
        end

        def replace_tag_blocks!(text, tag)
          loop do
            open_idx = text.index(/<#{tag}[\s>]/mi)
            break unless open_idx

            tag_end = text.index('>', open_idx)
            break unless tag_end

            close_pat = %r{</#{tag}\s*>}mi
            close_match = close_pat.match(text, tag_end)
            if close_match
              inner = text[(tag_end + 1)...close_match.begin(0)]
              replacement = yield(inner)
              text[open_idx..(close_match.end(0) - 1)] = replacement
            else
              text[open_idx..] = ''
            end
          end
        end

        def replace_open_tags!(text, tag, replacement)
          loop do
            idx = text.index(/<#{tag}[\s>]/mi)
            break unless idx

            close = text.index('>', idx)
            break unless close

            text[idx..close] = replacement
          end
        end

        def replace_close_tags!(text, tag, replacement)
          pat = %r{</#{tag}\s*>}mi
          loop do
            match = pat.match(text)
            break unless match

            text[match.begin(0)..(match.end(0) - 1)] = replacement
          end
        end

        def replace_self_closing!(text, tag, replacement)
          loop do
            idx = text.index(%r{<#{tag}[\s>/]}mi)
            break unless idx

            close = text.index('>', idx)
            break unless close

            text[idx..close] = replacement
          end
        end

        def convert_headings!(text)
          (1..6).each do |n|
            prefix = '#' * n
            replace_tag_blocks!(text, "h#{n}") { |inner| "\n#{prefix} #{inner}\n" }
          end
        end

        def convert_links!(text)
          result = String.new
          pos = 0
          while pos < text.length
            open_idx = text.index(/<a[\s>]/mi, pos)
            break unless open_idx

            close_idx = text.index(%r{</a\s*>}mi, open_idx)
            unless close_idx
              result << text[pos..]
              pos = text.length
              break
            end

            result << text[pos...open_idx]

            tag_end = text.index('>', open_idx)
            if tag_end && tag_end < close_idx
              tag = text[open_idx..tag_end]
              href = tag[/href=["']([^"']*)["']/i, 1]
              inner = text[(tag_end + 1)...close_idx]
              result << if href
                          "[#{inner}](#{href})"
                        else
                          inner
                        end
            end

            close_end = text.index('>', close_idx)
            pos = close_end ? close_end + 1 : close_idx + 4
          end
          result << text[pos..] if pos < text.length
          text.replace(result)
        end

        def convert_lists!(text)
          replace_tag_blocks!(text, 'li') { |inner| "\n- #{inner}" }
          replace_open_tags!(text, 'ul', "\n")
          replace_close_tags!(text, 'ul', "\n")
          replace_open_tags!(text, 'ol', "\n")
          replace_close_tags!(text, 'ol', "\n")
        end

        def convert_formatting!(text)
          %w[b strong].each { |t| replace_tag_blocks!(text, t) { |inner| "**#{inner}**" } }
          %w[i em].each { |t| replace_tag_blocks!(text, t) { |inner| "*#{inner}*" } }
          replace_tag_blocks!(text, 'code') { |inner| "`#{inner}`" }
        end

        def convert_blocks!(text)
          replace_tag_blocks!(text, 'pre') { |inner| "\n```\n#{inner}\n```\n" }
          replace_tag_blocks!(text, 'blockquote') { |inner| "\n> #{inner}\n" }
          replace_open_tags!(text, 'p', "\n\n")
          replace_close_tags!(text, 'p', "\n")
          replace_self_closing!(text, 'br', "\n")
          replace_self_closing!(text, 'hr', "\n---\n")
        end

        def strip_remaining_tags!(text)
          result = String.new(capacity: text.length)
          pos = 0
          while pos < text.length
            open_idx = text.index('<', pos)
            unless open_idx
              result << text[pos..]
              break
            end
            result << text[pos...open_idx]
            close_idx = text.index('>', open_idx)
            pos = close_idx ? close_idx + 1 : text.length
          end
          text.replace(result)
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
