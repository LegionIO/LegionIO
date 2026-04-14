#!/usr/bin/env ruby
# frozen_string_literal: true

# Fleet Pipeline Smoke Test
# =========================
# Runs against a live RabbitMQ instance to verify exchange/queue topology
# and basic message flow.
#
# Prerequisites:
#   - RabbitMQ running on localhost:5672 (or set RABBITMQ_URL)
#   - Legion gems installed: legion-transport, legion-settings, legion-json
#   - Fleet extensions deployed: lex-assessor, lex-planner, lex-developer, lex-validator
#
# Usage:
#   ruby scripts/fleet_smoke_test.rb
#   RABBITMQ_URL=amqp://user:pass@host:5672 ruby scripts/fleet_smoke_test.rb

require 'json'
require 'securerandom'
require 'timeout'

# Suppress legion logging noise
ENV['LEGION_LOG_LEVEL'] ||= 'error'

class FleetSmokeTest
  FLEET_EXCHANGES = %w[
    lex.assessor lex.planner lex.developer lex.validator
  ].freeze

  FLEET_QUEUES = %w[
    lex.assessor.runners.assessor
    lex.planner.runners.planner
    lex.developer.runners.developer
    lex.developer.runners.ship
    lex.validator.runners.validator
  ].freeze

  ABSORBER_QUEUES = %w[
    lex.github.absorbers.issues.absorb
  ].freeze

  attr_reader :results

  def initialize
    @results = []
    @passed = 0
    @failed = 0
  end

  def run
    puts '=' * 60
    puts 'Fleet Pipeline Smoke Test'
    puts '=' * 60
    puts

    check_dependencies
    setup_transport
    check_exchanges
    check_queues
    check_absorber_queues
    test_publish_consume
    teardown

    report
  end

  private

  def check_dependencies
    section('Checking dependencies')

    %w[legion-transport legion-settings legion-json].each do |gem_name|
      Gem::Specification.find_by_name(gem_name)
      pass("#{gem_name} installed")
    rescue Gem::MissingSpecError
      fail_test("#{gem_name} not installed")
    end
  end

  def setup_transport
    section('Connecting to RabbitMQ')

    require 'legion/settings'
    require 'legion/logging'
    require 'legion/transport'

    Legion::Logging.setup(log_level: 'error', level: 'error', trace: false)
    Legion::Settings.load

    if ENV['RABBITMQ_URL']
      Legion::Settings.loader.settings[:transport] ||= {}
      Legion::Settings.loader.settings[:transport][:url] = ENV.fetch('RABBITMQ_URL', nil)
    end

    Legion::Settings.merge_settings('transport', Legion::Transport::Settings.default)
    Legion::Transport::Connection.setup
    pass('Connected to RabbitMQ')
  rescue StandardError => e
    fail_test("RabbitMQ connection failed: #{e.message}")
    puts "\n  Set RABBITMQ_URL or configure transport in ~/.legionio/settings/"
    exit 1
  end

  def check_exchanges
    section('Checking fleet exchanges')

    channel = Legion::Transport::Connection.session.create_channel
    FLEET_EXCHANGES.each do |name|
      check_or_create_exchange(channel, name)
      channel = Legion::Transport::Connection.session.create_channel
    end
  end

  def check_or_create_exchange(channel, name)
    channel.exchange_declare(name, 'topic', passive: true)
    pass("Exchange #{name} exists")
  rescue Bunny::NotFound
    channel = Legion::Transport::Connection.session.create_channel
    channel.exchange_declare(name, 'topic', durable: true)
    pass("Exchange #{name} created")
  rescue StandardError => e
    fail_test("Exchange #{name} check failed: #{e.message}")
  end

  def check_queues
    section('Checking fleet queues')

    channel = Legion::Transport::Connection.session.create_channel
    FLEET_QUEUES.each do |name|
      check_or_create_queue(channel, name)
      channel = Legion::Transport::Connection.session.create_channel
    end
  end

  def check_absorber_queues
    section('Checking absorber queues')

    channel = Legion::Transport::Connection.session.create_channel
    ABSORBER_QUEUES.each do |name|
      check_or_create_queue(channel, name, prefix: 'Absorber queue')
      channel = Legion::Transport::Connection.session.create_channel
    end
  end

  def check_or_create_queue(channel, name, prefix: 'Queue')
    q = channel.queue(name, durable: true, passive: true)
    pass("#{prefix} #{name} exists (depth: #{q.message_count})")
  rescue Bunny::NotFound
    channel = Legion::Transport::Connection.session.create_channel
    channel.queue(name, durable: true)
    pass("#{prefix} #{name} created")
  rescue StandardError => e
    fail_test("#{prefix} #{name} check failed: #{e.message}")
  end

  def test_publish_consume
    section('Testing publish/consume round-trip')

    channel = Legion::Transport::Connection.session.create_channel
    test_queue_name = "fleet.smoke_test.#{SecureRandom.hex(4)}"

    exchange = channel.topic('lex.assessor', durable: true)
    queue = channel.queue(test_queue_name, durable: false, auto_delete: true)
    queue.bind(exchange, routing_key: "#{test_queue_name}.#")

    test_payload = {
      work_item_id: SecureRandom.uuid,
      source:       'smoke_test',
      title:        'Fleet smoke test message',
      timestamp:    Time.now.utc.iso8601
    }

    exchange.publish(
      JSON.generate(test_payload),
      routing_key:  "#{test_queue_name}.test",
      content_type: 'application/json',
      persistent:   false
    )

    received = nil
    Timeout.timeout(5) do
      _, _, body = queue.pop
      received = body ? JSON.parse(body, symbolize_names: true) : nil
    end

    if received && received[:work_item_id] == test_payload[:work_item_id]
      pass('Publish/consume round-trip successful')
    else
      fail_test('Message not received or payload mismatch')
    end
  rescue Timeout::Error
    fail_test('Publish/consume timed out after 5 seconds')
  rescue StandardError => e
    fail_test("Publish/consume failed: #{e.message}")
  ensure
    queue&.delete
  end

  def teardown
    Legion::Transport::Connection.shutdown
  rescue StandardError
    nil
  end

  def section(title)
    puts
    puts "--- #{title} ---"
  end

  def pass(message)
    @passed += 1
    @results << { status: :pass, message: message }
    puts "  [PASS] #{message}"
  end

  def fail_test(message)
    @failed += 1
    @results << { status: :fail, message: message }
    puts "  [FAIL] #{message}"
  end

  def report
    puts
    puts '=' * 60
    total = @passed + @failed
    if @failed.zero?
      puts "ALL #{total} CHECKS PASSED"
    else
      puts "#{@passed}/#{total} passed, #{@failed} FAILED"
    end
    puts '=' * 60

    exit(@failed.zero? ? 0 : 1)
  end
end

FleetSmokeTest.new.run if $PROGRAM_NAME == __FILE__
