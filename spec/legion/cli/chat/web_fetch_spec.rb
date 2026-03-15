# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli/chat/web_fetch'

RSpec.describe Legion::CLI::Chat::WebFetch do
  describe '.parse_uri' do
    it 'adds https when no scheme is given' do
      uri = described_class.parse_uri('example.com/page')
      expect(uri.to_s).to eq('https://example.com/page')
    end

    it 'preserves http scheme' do
      uri = described_class.parse_uri('http://example.com')
      expect(uri.scheme).to eq('http')
    end

    it 'preserves https scheme' do
      uri = described_class.parse_uri('https://example.com')
      expect(uri.scheme).to eq('https')
    end

    it 'raises FetchError for invalid URIs' do
      expect { described_class.parse_uri('not a url at all ://') }
        .to raise_error(described_class::FetchError, /Invalid URL/)
    end
  end

  describe '.html?' do
    it 'returns true for text/html content type' do
      expect(described_class.html?('text/html; charset=utf-8')).to be true
    end

    it 'returns false for plain text' do
      expect(described_class.html?('text/plain')).to be false
    end

    it 'returns false for nil' do
      expect(described_class.html?(nil)).to be false
    end
  end

  describe '.html_to_markdown' do
    it 'converts headings' do
      html = '<h1>Title</h1><h2>Subtitle</h2>'
      md = described_class.html_to_markdown(html)
      expect(md).to include('# Title')
      expect(md).to include('## Subtitle')
    end

    it 'converts links' do
      html = '<a href="https://example.com">Click here</a>'
      md = described_class.html_to_markdown(html)
      expect(md).to include('[Click here](https://example.com)')
    end

    it 'converts list items' do
      html = '<ul><li>First</li><li>Second</li></ul>'
      md = described_class.html_to_markdown(html)
      expect(md).to include('- First')
      expect(md).to include('- Second')
    end

    it 'converts bold and italic' do
      html = '<strong>bold</strong> and <em>italic</em>'
      md = described_class.html_to_markdown(html)
      expect(md).to include('**bold**')
      expect(md).to include('*italic*')
    end

    it 'converts code and pre blocks' do
      html = 'Use <code>puts</code> or:<pre>def foo\n  bar\nend</pre>'
      md = described_class.html_to_markdown(html)
      expect(md).to include('`puts`')
      expect(md).to include("```\ndef foo")
    end

    it 'strips script and style tags' do
      html = '<p>Hello</p><script>alert("xss")</script><style>.x{}</style><p>World</p>'
      md = described_class.html_to_markdown(html)
      expect(md).not_to include('alert')
      expect(md).not_to include('.x{}')
      expect(md).to include('Hello')
      expect(md).to include('World')
    end

    it 'strips nav and footer' do
      html = '<nav>Menu</nav><p>Content</p><footer>Copyright</footer>'
      md = described_class.html_to_markdown(html)
      expect(md).not_to include('Menu')
      expect(md).not_to include('Copyright')
      expect(md).to include('Content')
    end

    it 'decodes HTML entities' do
      html = '5 &gt; 3 &amp; 2 &lt; 4 &quot;hi&quot;'
      md = described_class.html_to_markdown(html)
      expect(md).to include('5 > 3 & 2 < 4 "hi"')
    end

    it 'converts paragraphs and line breaks' do
      html = '<p>First paragraph</p><p>Second<br>with break</p>'
      md = described_class.html_to_markdown(html)
      expect(md).to include('First paragraph')
      expect(md).to include("Second\nwith break")
    end

    it 'converts horizontal rules' do
      html = '<p>Above</p><hr><p>Below</p>'
      md = described_class.html_to_markdown(html)
      expect(md).to include('---')
    end
  end

  describe '.truncate' do
    it 'returns short text unchanged' do
      expect(described_class.truncate('hello', 100)).to eq('hello')
    end

    it 'truncates long text with marker' do
      result = described_class.truncate('a' * 200, 50)
      expect(result.length).to be > 50
      expect(result).to include('[... truncated at 50 characters]')
      expect(result).to start_with('a' * 50)
    end
  end

  describe '.fetch' do
    it 'fetches and converts HTML content' do
      html_body = '<html><body><h1>Test Page</h1><p>Hello world</p></body></html>'
      stub_successful_fetch('https://example.com/page', html_body, 'text/html')

      result = described_class.fetch('https://example.com/page')
      expect(result).to include('# Test Page')
      expect(result).to include('Hello world')
    end

    it 'returns plain text without conversion' do
      stub_successful_fetch('https://example.com/api', '{"key":"value"}', 'application/json')

      result = described_class.fetch('https://example.com/api')
      expect(result).to include('{"key":"value"}')
    end

    it 'follows redirects' do
      redirect_response = Net::HTTPFound.allocate
      allow(redirect_response).to receive(:[]).with('content-type').and_return(nil)
      allow(redirect_response).to receive(:[]).with('location').and_return('https://example.com/final')
      allow(redirect_response).to receive(:code).and_return('302')

      final_response = Net::HTTPOK.allocate
      allow(final_response).to receive(:[]).with('content-type').and_return('text/plain')
      allow(final_response).to receive(:body).and_return('Final content')
      allow(final_response).to receive(:code).and_return('200')

      http = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:new).and_return(http)
      allow(http).to receive(:use_ssl=)
      allow(http).to receive(:open_timeout=)
      allow(http).to receive(:read_timeout=)
      allow(http).to receive(:request).and_return(redirect_response, final_response)

      result = described_class.fetch('https://example.com/start')
      expect(result).to eq('Final content')
    end

    it 'raises FetchError on HTTP errors' do
      error_response = Net::HTTPNotFound.allocate
      allow(error_response).to receive(:code).and_return('404')
      allow(error_response).to receive(:message).and_return('Not Found')

      http = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:new).and_return(http)
      allow(http).to receive(:use_ssl=)
      allow(http).to receive(:open_timeout=)
      allow(http).to receive(:read_timeout=)
      allow(http).to receive(:request).and_return(error_response)

      expect { described_class.fetch('https://example.com/missing') }
        .to raise_error(described_class::FetchError, /404/)
    end

    it 'raises FetchError on timeout' do
      http = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:new).and_return(http)
      allow(http).to receive(:use_ssl=)
      allow(http).to receive(:open_timeout=)
      allow(http).to receive(:read_timeout=)
      allow(http).to receive(:request).and_raise(Net::ReadTimeout)

      expect { described_class.fetch('https://example.com/slow') }
        .to raise_error(described_class::FetchError, /timed out/)
    end

    it 'raises FetchError on connection failure' do
      http = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:new).and_return(http)
      allow(http).to receive(:use_ssl=)
      allow(http).to receive(:open_timeout=)
      allow(http).to receive(:read_timeout=)
      allow(http).to receive(:request).and_raise(SocketError, 'getaddrinfo: Name or service not known')

      expect { described_class.fetch('https://nonexistent.invalid') }
        .to raise_error(described_class::FetchError, /Connection failed/)
    end
  end

  def stub_successful_fetch(url, body, content_type)
    uri = URI.parse(url)
    response = Net::HTTPOK.allocate
    allow(response).to receive(:[]).with('content-type').and_return(content_type)
    allow(response).to receive(:body).and_return(body)
    allow(response).to receive(:code).and_return('200')

    http = instance_double(Net::HTTP)
    allow(Net::HTTP).to receive(:new).with(uri.host, uri.port).and_return(http)
    allow(http).to receive(:use_ssl=)
    allow(http).to receive(:open_timeout=)
    allow(http).to receive(:read_timeout=)
    allow(http).to receive(:request).and_return(response)
  end
end
