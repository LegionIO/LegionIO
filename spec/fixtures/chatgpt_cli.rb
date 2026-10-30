# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'
require 'socket'
require 'timeout'
require 'open3'
require 'rbconfig'
require 'uri'
require 'base64'
require 'legion/extensions/llm/openai/chatgpt/auth'

# Executes the shipped binaries against an isolated home and a real local OAuth peer.
class ChatgptCliFixture
  attr_reader :home, :requests, :credential_root
  attr_accessor :mode

  def initialize(mode: :success)
    @home = File.realpath(Dir.mktmpdir('legion-chatgpt-cli-'))
    @credential_root = File.join(@home, '.legionio', 'auth', 'llm', 'openai')
    @mode = mode
    @requests = []
    @server = TCPServer.new('127.0.0.1', 0)
    @thread = Thread.new { loop { serve(socket: @server.accept) } }
    @thread.report_on_exception = false
  end

  def close
    @thread.kill
    @thread.join
    @server.close
    FileUtils.remove_entry(@home)
  end

  def run(args:, binary: 'legion', missing: false, &interaction)
    root = File.expand_path('../..', __dir__)
    preload = File.join(__dir__, 'chatgpt_oauth_transport.rb')
    environment = { 'HOME' => @home, 'OPENAI_API_KEY' => nil, 'CODEX_API_KEY' => nil,
                    'LEGION_CHATGPT_FIXTURE_PORT' => @server.addr[1].to_s,
                    'LEGION_CHATGPT_FIXTURE_MISSING' => missing.to_s }
    command = [RbConfig.ruby, '-Ilib', '-r', preload, File.join(root, 'exe', binary), 'connect', *args]
    Open3.popen3(environment, *command, chdir: root) do |stdin, stdout, stderr, child|
      stdin.close
      errors = Thread.new { stderr.read }
      output = read_output(stdout: stdout, child: child, &interaction)
      { stdout: output, stderr: errors.value, exitstatus: child.value.exitstatus }
    ensure
      if child.alive?
        ::Process.kill('TERM', child.pid)
        child.join
      end
    end
  end

  def approve_browser(line:)
    return unless line.start_with?('https://auth.openai.com/oauth/authorize?')

    state = URI.decode_www_form(URI(line.strip).query).to_h.fetch('state')
    query = URI.encode_www_form(state: state, code: 'fixture-authorization-code-secret')
    TCPSocket.open('127.0.0.1', 1455) do |socket|
      socket.write("GET /auth/callback?#{query} HTTP/1.1\r\nHost: localhost:1455\r\n\r\n")
      socket.read
    end
  end

  def store
    Legion::Extensions::Llm::Openai::Chatgpt::CredentialStore.new(root: @credential_root)
  end

  def seed(instance:, expires_at: Time.now.to_f + 3600)
    generation = store.begin_login(instance: instance)
    store.complete_login(instance: instance, generation: generation,
                         bundle: { access_token: access_token, refresh_token: 'fixture-refresh-secret',
                                   expires_at: expires_at, account_id: 'fixture-cli-account',
                                   workspace_id: nil, residency: nil })
  end

  def secrets
    [access_token, 'fixture-refresh-secret', 'fixture-id-secret', 'fixture-authorization-code-secret',
     'fixture-private-oauth-error', 'fixture-private-dependency-error']
  end

  private

  def read_output(stdout:, child:)
    output = +''
    Timeout.timeout(15) do
      stdout.each_line do |line|
        output << line
        yield(line, child.pid) if block_given?
      end
      child.value
    end
    output
  end

  def serve(socket:)
    request = read_request(socket: socket)
    return unless request

    @requests << request
    status, payload = response(request: request)
    body = Legion::JSON.dump(payload)
    socket.write("HTTP/1.1 #{status} Fixture\r\nContent-Type: application/json\r\n" \
                 "Content-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}")
  rescue Errno::EPIPE, Errno::ECONNRESET
    Legion::Logging.debug('ChatGPT CLI fixture client disconnected during cancellation')
  ensure
    socket.close
  end

  def read_request(socket:)
    first = socket.gets("\r\n")
    return unless first

    headers = {}
    while (line = socket.gets("\r\n")) && line != "\r\n"
      key, value = line.split(':', 2)
      headers[key.downcase] = value.strip
    end
    size = headers.fetch('content-length', '0').to_i
    body = socket.read(size)
    return unless body && body.bytesize == size

    { path: first.split[1], body: body }
  end

  def response(request:)
    case request[:path]
    when '/api/accounts/deviceauth/usercode'
      [200, { device_auth_id: 'fixture-device', user_code: 'FIXTURE-USER-CODE', interval: 0.01 }]
    when '/api/accounts/deviceauth/token'
      device_response
    when '/oauth/token'
      File.chmod(0o755, @credential_root) if @mode == :storage_failure
      [200, { access_token: access_token, refresh_token: 'fixture-refresh-secret', id_token: 'fixture-id-secret',
              expires_in: 3600, token_type: 'Bearer' }]
    else
      raise "Unexpected fixture OAuth path: #{request[:path]}"
    end
  end

  def device_response
    return [403, { error: 'access_denied', error_description: 'fixture-private-oauth-error' }] if @mode == :denied
    return [403, {}] if @mode == :pending

    [200, { authorization_code: 'fixture-authorization-code-secret', code_verifier: 'fixture-code-verifier' }]
  end

  def access_token
    claims = { 'https://api.openai.com/auth': { chatgpt_account_id: 'fixture-cli-account' } }
    "fixture.#{Base64.urlsafe_encode64(Legion::JSON.dump(claims), padding: false)}.signature"
  end
end
