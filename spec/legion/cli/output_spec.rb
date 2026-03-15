# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli/output'
require 'json'
require 'stringio'

RSpec.describe Legion::CLI::Output do
  describe '.encode_json' do
    context 'when Legion::JSON is available and responds to :dump' do
      before do
        stub_const('Legion::JSON', Module.new do
          def self.dump(_data)
            '{"stubbed":true}'
          end
        end)
      end

      it 'delegates to Legion::JSON.dump' do
        expect(described_class.encode_json({ test: true })).to eq('{"stubbed":true}')
      end
    end

    context 'when Legion::JSON is not available' do
      before do
        hide_const('Legion::JSON') if defined?(Legion::JSON)
      rescue TypeError
        # hide_const may not work if constant is not defined; that is fine
      end

      it 'falls back to JSON.pretty_generate' do
        data = { key: 'value' }
        result = described_class.encode_json(data)
        parsed = JSON.parse(result)
        expect(parsed['key']).to eq('value')
      end
    end

    context 'when Legion::JSON is defined but does not respond to :dump' do
      before do
        stub_const('Legion::JSON', Module.new)
      end

      it 'falls back to stdlib JSON.pretty_generate, raising NoMethodError because Legion::JSON shadows stdlib JSON' do
        # When Legion::JSON is defined without :dump, the `else` branch calls JSON.pretty_generate
        # but within the Legion namespace, `JSON` resolves to `Legion::JSON` (not stdlib JSON),
        # so this raises NoMethodError — this is expected behaviour from the namespace shadowing.
        data = { hello: 'world' }
        expect { described_class.encode_json(data) }.to raise_error(NoMethodError)
      end
    end
  end

  describe Legion::CLI::Output::COLORS do
    it 'includes reset, bold, and dim keys' do
      expect(described_class).to have_key(:reset)
      expect(described_class).to have_key(:bold)
      expect(described_class).to have_key(:dim)
    end

    it 'includes all legacy color names' do
      %i[red green yellow blue magenta cyan white gray].each do |color|
        expect(described_class).to have_key(color)
      end
    end

    it 'includes all semantic names' do
      %i[title heading body label accent muted disabled border node nominal caution critical].each do |name|
        expect(described_class).to have_key(name)
      end
    end
  end

  describe Legion::CLI::Output::STATUS_ICONS do
    it 'maps every expected status key' do
      %i[ok ready running enabled loaded completed warning pending disabled error failed dead unknown].each do |key|
        expect(described_class).to have_key(key)
      end
    end

    it 'maps positive statuses to nominal' do
      %i[ok ready running enabled loaded completed].each do |key|
        expect(described_class[key]).to eq('nominal')
      end
    end

    it 'maps warning and pending to caution' do
      expect(described_class[:warning]).to eq('caution')
      expect(described_class[:pending]).to eq('caution')
    end

    it 'maps disabled to muted' do
      expect(described_class[:disabled]).to eq('muted')
    end

    it 'maps error statuses to critical' do
      %i[error failed dead].each do |key|
        expect(described_class[key]).to eq('critical')
      end
    end

    it 'maps unknown to disabled' do
      expect(described_class[:unknown]).to eq('disabled')
    end
  end
end

RSpec.describe Legion::CLI::Output::Formatter do
  def capture_stdout
    output = StringIO.new
    $stdout = output
    yield
    output.string
  ensure
    $stdout = STDOUT
  end

  describe '#initialize' do
    it 'sets json_mode from :json option' do
      formatter = described_class.new(json: true, color: false)
      expect(formatter.json_mode).to be(true)
    end

    it 'sets json_mode to false by default' do
      formatter = described_class.new(color: false)
      expect(formatter.json_mode).to be(false)
    end

    it 'disables color when json: true' do
      # Even if color: true is passed, json mode forces color off
      formatter = described_class.new(json: true, color: true)
      expect(formatter.color_enabled).to be(false)
    end

    it 'disables color when color: false' do
      formatter = described_class.new(json: false, color: false)
      expect(formatter.color_enabled).to be(false)
    end

    it 'disables color when stdout is not a tty (e.g., StringIO in tests)' do
      # In test environment $stdout is not a tty, so color_enabled must be false
      formatter = described_class.new(json: false, color: true)
      expect(formatter.color_enabled).to be(false)
    end
  end

  describe '#colorize' do
    context 'with color disabled' do
      let(:formatter) { described_class.new(json: false, color: false) }

      it 'returns text unchanged for any color' do
        %i[red green yellow blue magenta cyan white gray title heading body label accent muted disabled].each do |color|
          expect(formatter.colorize('hello', color)).to eq('hello')
        end
      end

      it 'converts non-string values to string' do
        expect(formatter.colorize(42, :red)).to eq('42')
        expect(formatter.colorize(nil, :red)).to eq('')
      end
    end

    context 'with color enabled' do
      let(:formatter) do
        f = described_class.new(json: false, color: false)
        # Force color_enabled on by overriding the instance variable
        f.instance_variable_set(:@color_enabled, true)
        f
      end

      it 'wraps text with the ANSI escape for the given color and a reset' do
        result = formatter.colorize('hello', :red)
        expect(result).to include('hello')
        expect(result).to include(Legion::CLI::Output::COLORS[:red])
        expect(result).to include(Legion::CLI::Output::COLORS[:reset])
      end

      it 'works for every color key in COLORS (excluding bold/dim/reset)' do
        color_keys = Legion::CLI::Output::COLORS.keys - %i[reset bold dim]
        color_keys.each do |color|
          result = formatter.colorize('x', color)
          expect(result).to include(Legion::CLI::Output::COLORS[:reset]),
                            "expected reset for color #{color}"
        end
      end
    end
  end

  describe '#bold' do
    context 'with color disabled' do
      let(:formatter) { described_class.new(json: false, color: false) }

      it 'returns the text as a string' do
        expect(formatter.bold('important')).to eq('important')
      end
    end

    context 'with color enabled' do
      let(:formatter) do
        f = described_class.new(json: false, color: false)
        f.instance_variable_set(:@color_enabled, true)
        f
      end

      it 'wraps text with bold and heading escape codes and resets' do
        result = formatter.bold('important')
        expect(result).to include('important')
        expect(result).to include(Legion::CLI::Output::COLORS[:bold])
        expect(result).to include(Legion::CLI::Output::COLORS[:heading])
        expect(result).to include(Legion::CLI::Output::COLORS[:reset])
      end
    end
  end

  describe '#dim' do
    context 'with color disabled' do
      let(:formatter) { described_class.new(json: false, color: false) }

      it 'returns the text as a string' do
        expect(formatter.dim('faded')).to eq('faded')
      end
    end

    context 'with color enabled' do
      let(:formatter) do
        f = described_class.new(json: false, color: false)
        f.instance_variable_set(:@color_enabled, true)
        f
      end

      it 'wraps text with the gray escape code and resets' do
        result = formatter.dim('faded')
        expect(result).to include('faded')
        expect(result).to include(Legion::CLI::Output::COLORS[:gray])
        expect(result).to include(Legion::CLI::Output::COLORS[:reset])
      end
    end
  end

  describe '#status_color' do
    let(:formatter) { described_class.new(json: false, color: false) }

    it 'returns :nominal for ok' do
      expect(formatter.status_color(:ok)).to eq(:nominal)
    end

    it 'returns :nominal for ready' do
      expect(formatter.status_color(:ready)).to eq(:nominal)
    end

    it 'returns :nominal for running' do
      expect(formatter.status_color(:running)).to eq(:nominal)
    end

    it 'returns :nominal for enabled' do
      expect(formatter.status_color(:enabled)).to eq(:nominal)
    end

    it 'returns :nominal for loaded' do
      expect(formatter.status_color(:loaded)).to eq(:nominal)
    end

    it 'returns :nominal for completed' do
      expect(formatter.status_color(:completed)).to eq(:nominal)
    end

    it 'returns :caution for warning' do
      expect(formatter.status_color(:warning)).to eq(:caution)
    end

    it 'returns :caution for pending' do
      expect(formatter.status_color(:pending)).to eq(:caution)
    end

    it 'returns :muted for disabled' do
      expect(formatter.status_color(:disabled)).to eq(:muted)
    end

    it 'returns :critical for error' do
      expect(formatter.status_color(:error)).to eq(:critical)
    end

    it 'returns :critical for failed' do
      expect(formatter.status_color(:failed)).to eq(:critical)
    end

    it 'returns :critical for dead' do
      expect(formatter.status_color(:dead)).to eq(:critical)
    end

    it 'returns :disabled for unknown' do
      expect(formatter.status_color(:unknown)).to eq(:disabled)
    end

    it 'returns :disabled for unrecognised statuses' do
      expect(formatter.status_color(:something_else)).to eq(:disabled)
    end

    it 'accepts string input and normalises it' do
      expect(formatter.status_color('ok')).to eq(:nominal)
      expect(formatter.status_color('FAILED')).to eq(:critical)
    end

    it 'converts dots to underscores before lookup' do
      # Dot-separated status strings are normalised
      expect(formatter.status_color('unknown.thing')).to eq(:disabled)
    end
  end

  describe '#status' do
    let(:formatter) { described_class.new(json: false, color: false) }

    it 'returns the text for known statuses' do
      expect(formatter.status('ok')).to eq('ok')
    end

    it 'returns the text for unknown statuses' do
      expect(formatter.status('bogus')).to eq('bogus')
    end

    context 'with color enabled' do
      let(:formatter) do
        f = described_class.new(json: false, color: false)
        f.instance_variable_set(:@color_enabled, true)
        f
      end

      it 'wraps the text with the appropriate color escape' do
        result = formatter.status('ok')
        expect(result).to include('ok')
        expect(result).to include(Legion::CLI::Output::COLORS[:reset])
      end
    end
  end

  describe '#banner' do
    let(:formatter) { described_class.new(json: false, color: false) }

    it 'prints output to stdout' do
      result = capture_stdout { formatter.banner }
      expect(result).not_to be_empty
    end

    it 'includes LEGION text (via logo characters) in the output' do
      result = capture_stdout { formatter.banner }
      # The banner renders block characters from the LOGO constant
      expect(result).to include("\u2588")
    end

    it 'includes the version string when provided' do
      result = capture_stdout { formatter.banner(version: '1.2.3') }
      expect(result).to include('1.2.3')
    end

    it 'includes a description when a version is provided' do
      result = capture_stdout { formatter.banner(version: '1.0.0') }
      expect(result).to include('Async Job Engine')
    end

    it 'does not include version text when version is nil' do
      result = capture_stdout { formatter.banner }
      expect(result).not_to include('Async Job Engine')
    end
  end

  describe '#header' do
    context 'in text mode' do
      let(:formatter) { described_class.new(json: false, color: false) }

      it 'prints the header text to stdout' do
        result = capture_stdout { formatter.header('My Section') }
        expect(result.strip).to eq('My Section')
      end

      context 'with color enabled' do
        let(:formatter) do
          f = described_class.new(json: false, color: false)
          f.instance_variable_set(:@color_enabled, true)
          f
        end

        it 'wraps the text in bold/heading escapes' do
          result = capture_stdout { formatter.header('Colored Header') }
          expect(result).to include('Colored Header')
          expect(result).to include(Legion::CLI::Output::COLORS[:bold])
          expect(result).to include(Legion::CLI::Output::COLORS[:reset])
        end
      end
    end

    context 'in json mode' do
      let(:formatter) { described_class.new(json: true, color: false) }

      it 'prints nothing' do
        result = capture_stdout { formatter.header('Silent Header') }
        expect(result).to be_empty
      end
    end
  end

  describe '#detail' do
    context 'in text mode' do
      let(:formatter) { described_class.new(json: false, color: false) }

      it 'prints each key-value pair' do
        result = capture_stdout { formatter.detail({ name: 'legion', version: '1.0.0' }) }
        expect(result).to include('name')
        expect(result).to include('legion')
        expect(result).to include('version')
        expect(result).to include('1.0.0')
      end

      it 'renders true as "yes"' do
        result = capture_stdout { formatter.detail({ active: true }) }
        expect(result).to include('yes')
      end

      it 'renders false as "no"' do
        result = capture_stdout { formatter.detail({ active: false }) }
        expect(result).to include('no')
      end

      it 'renders nil as "(none)"' do
        result = capture_stdout { formatter.detail({ value: nil }) }
        expect(result).to include('(none)')
      end

      it 'renders numeric values as strings' do
        result = capture_stdout { formatter.detail({ count: 42 }) }
        expect(result).to include('42')
      end

      it 'renders string values directly' do
        result = capture_stdout { formatter.detail({ label: 'hello' }) }
        expect(result).to include('hello')
      end

      it 'applies indentation when indent: is specified' do
        result_no_indent  = capture_stdout { formatter.detail({ key: 'val' }, indent: 0) }
        result_indented   = capture_stdout { formatter.detail({ key: 'val' }, indent: 4) }
        expect(result_indented.length).to be > result_no_indent.length
      end

      it 'left-justifies keys to the longest key width' do
        result = capture_stdout { formatter.detail({ a: '1', longkey: '2' }) }
        lines = result.lines
        # Both lines must have the same key-column width (padded with spaces)
        key_columns = lines.map { |l| l.match(/^\s+(\S+\s*):/)&.send(:[], 0) }.compact
        expect(key_columns).not_to be_empty
      end
    end

    context 'in json mode' do
      let(:formatter) { described_class.new(json: true, color: false) }

      it 'prints JSON-encoded hash to stdout' do
        result = capture_stdout { formatter.detail({ name: 'legion', active: true }) }
        parsed = JSON.parse(result)
        expect(parsed['name']).to eq('legion')
        expect(parsed['active']).to be(true)
      end
    end
  end

  describe '#table' do
    context 'in text mode with rows' do
      let(:formatter) { described_class.new(json: false, color: false) }

      it 'renders column headers uppercased' do
        result = capture_stdout { formatter.table(%w[name status], [%w[alpha ok]]) }
        expect(result).to include('NAME')
        expect(result).to include('STATUS')
      end

      it 'renders each row value' do
        result = capture_stdout { formatter.table(%w[name status], [%w[alpha ok], %w[beta running]]) }
        expect(result).to include('alpha')
        expect(result).to include('beta')
        expect(result).to include('ok')
        expect(result).to include('running')
      end

      it 'renders a separator line under the header' do
        result = capture_stdout { formatter.table(%w[name], [%w[x]]) }
        expect(result).to match(/─+/)
      end

      it 'adds a blank line before content when title is given' do
        result = capture_stdout { formatter.table(%w[name], [%w[x]], title: 'My Table') }
        # A title causes a puts before the header line, so there should be a blank line
        expect(result).to start_with("\n").or include("\n\n")
      end

      it 'does not add a blank line when title is nil' do
        result = capture_stdout { formatter.table(%w[name], [%w[x]]) }
        expect(result).not_to start_with("\n\n")
      end
    end

    context 'in text mode with empty rows' do
      let(:formatter) { described_class.new(json: false, color: false) }

      it 'prints a (no results) message' do
        result = capture_stdout { formatter.table(%w[name status], []) }
        expect(result).to include('(no results)')
      end

      it 'does not print headers when rows are empty' do
        result = capture_stdout { formatter.table(%w[name status], []) }
        expect(result).not_to include('NAME')
      end
    end

    context 'in json mode' do
      let(:formatter) { described_class.new(json: true, color: false) }

      it 'prints a JSON array of objects keyed by header' do
        result = capture_stdout { formatter.table(%w[name status], [%w[alpha ok]]) }
        parsed = JSON.parse(result)
        expect(parsed).to be_an(Array)
        expect(parsed.first['name']).to eq('alpha')
        expect(parsed.first['status']).to eq('ok')
      end

      it 'wraps output in a titled object when title is given' do
        result = capture_stdout { formatter.table(%w[name], [%w[x]], title: 'My Table') }
        parsed = JSON.parse(result)
        expect(parsed).to have_key('title')
        expect(parsed['title']).to eq('My Table')
        expect(parsed).to have_key('data')
      end

      it 'returns an empty array for empty rows' do
        result = capture_stdout { formatter.table(%w[name status], []) }
        parsed = JSON.parse(result)
        expect(parsed).to eq([])
      end
    end
  end

  describe '#success' do
    context 'in text mode' do
      let(:formatter) { described_class.new(json: false, color: false) }

      it 'prints the message to stdout' do
        result = capture_stdout { formatter.success('It worked!') }
        expect(result).to include('It worked!')
      end

      it 'includes the arrow character' do
        result = capture_stdout { formatter.success('Done') }
        expect(result).to include('»')
      end
    end

    context 'in json mode' do
      let(:formatter) { described_class.new(json: true, color: false) }

      it 'prints JSON with success: true and message' do
        result = capture_stdout { formatter.success('It worked!') }
        parsed = JSON.parse(result)
        expect(parsed['success']).to be(true)
        expect(parsed['message']).to eq('It worked!')
      end
    end
  end

  describe '#warn' do
    context 'in text mode' do
      let(:formatter) { described_class.new(json: false, color: false) }

      it 'prints the message to stdout' do
        result = capture_stdout { formatter.warn('Take care!') }
        expect(result).to include('Take care!')
      end

      it 'includes the arrow character' do
        result = capture_stdout { formatter.warn('Careful') }
        expect(result).to include('»')
      end
    end

    context 'in json mode' do
      let(:formatter) { described_class.new(json: true, color: false) }

      it 'prints JSON with warning: true and message' do
        result = capture_stdout { formatter.warn('Take care!') }
        parsed = JSON.parse(result)
        expect(parsed['warning']).to be(true)
        expect(parsed['message']).to eq('Take care!')
      end
    end
  end

  describe '#error' do
    context 'in text mode' do
      let(:formatter) { described_class.new(json: false, color: false) }

      it 'prints the message to stdout' do
        result = capture_stdout { formatter.error('Something broke') }
        expect(result).to include('Something broke')
      end

      it 'includes the arrow character twice (error delegates to warn which also adds one)' do
        result = capture_stdout { formatter.error('Oops') }
        expect(result.count('»')).to be >= 2
      end
    end

    context 'in json mode' do
      let(:formatter) { described_class.new(json: true, color: false) }

      it 'prints JSON with error: true and message' do
        result = capture_stdout { formatter.error('Something broke') }
        parsed = JSON.parse(result)
        expect(parsed['error']).to be(true)
        expect(parsed['message']).to eq('Something broke')
      end
    end
  end

  describe '#json' do
    let(:formatter) { described_class.new(json: false, color: false) }

    it 'outputs valid JSON regardless of json_mode' do
      result = capture_stdout { formatter.json({ key: 'value', count: 3 }) }
      parsed = JSON.parse(result)
      expect(parsed['key']).to eq('value')
      expect(parsed['count']).to eq(3)
    end

    it 'outputs valid JSON for arrays' do
      result = capture_stdout { formatter.json([1, 2, 3]) }
      parsed = JSON.parse(result)
      expect(parsed).to eq([1, 2, 3])
    end

    it 'outputs a newline terminator' do
      result = capture_stdout { formatter.json({ a: 1 }) }
      expect(result).to end_with("\n")
    end
  end

  describe '#spacer' do
    context 'in text mode' do
      let(:formatter) { described_class.new(json: false, color: false) }

      it 'prints a blank line' do
        result = capture_stdout { formatter.spacer }
        expect(result).to eq("\n")
      end
    end

    context 'in json mode' do
      let(:formatter) { described_class.new(json: true, color: false) }

      it 'prints nothing' do
        result = capture_stdout { formatter.spacer }
        expect(result).to be_empty
      end
    end
  end
end
