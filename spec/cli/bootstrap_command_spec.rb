# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli'
require 'legion/cli/bootstrap_command'
require 'legion/cli/config_import'
require 'legion/cli/config_scaffold'
require 'legion/cli/setup_command'

RSpec.describe Legion::CLI::Bootstrap do
  let(:out) do
    instance_double(
      Legion::CLI::Output::Formatter,
      success: nil, warn: nil, error: nil,
      header: nil, spacer: nil, json: nil
    )
  end
  let(:cli) { described_class.new }

  before do
    allow(cli).to receive(:formatter).and_return(out)
    allow(cli).to receive(:options).and_return(default_options)
  end

  let(:default_options) do
    { json: false, no_color: true, skip_packs: false, start: false, force: false }
  end

  # ---------------------------------------------------------------------------
  # Class structure / Thor registration
  # ---------------------------------------------------------------------------

  describe 'Thor registration' do
    it 'has an execute command' do
      expect(described_class.commands).to have_key('execute')
    end

    it 'sets exit_on_failure? to true' do
      expect(described_class.exit_on_failure?).to be true
    end

    it 'declares --skip-packs class option' do
      expect(described_class.class_options).to have_key(:skip_packs)
    end

    it 'declares --start class option' do
      expect(described_class.class_options).to have_key(:start)
    end

    it 'declares --force class option' do
      expect(described_class.class_options).to have_key(:force)
    end

    it 'declares --json class option' do
      expect(described_class.class_options).to have_key(:json)
    end
  end

  describe 'Main registration' do
    it 'registers bootstrap on Legion::CLI::Main' do
      expect(Legion::CLI::Main.subcommand_classes).to have_key('bootstrap')
    end

    it 'maps bootstrap to Legion::CLI::Bootstrap' do
      expect(Legion::CLI::Main.subcommand_classes['bootstrap']).to eq(described_class)
    end
  end

  # ---------------------------------------------------------------------------
  # Pre-flight check helpers
  # ---------------------------------------------------------------------------

  describe 'pre-flight checks' do
    let(:warns) { [] }

    describe '#check_klist' do
      context 'when klist succeeds with a principal in output' do
        before do
          allow(cli).to receive(:shell_capture).with('klist').and_return(
            ['Default principal: user@UHG.COM', true]
          )
        end

        it 'returns status :ok' do
          result = cli.send(:check_klist, out, warns)
          expect(result[:status]).to eq(:ok)
        end

        it 'does not add any warnings' do
          cli.send(:check_klist, out, warns)
          expect(warns).to be_empty
        end
      end

      context 'when klist exit status is failure' do
        before do
          allow(cli).to receive(:shell_capture).with('klist').and_return(['', false])
        end

        it 'returns status :warn' do
          result = cli.send(:check_klist, out, warns)
          expect(result[:status]).to eq(:warn)
        end

        it 'adds a warning message' do
          cli.send(:check_klist, out, warns)
          expect(warns).not_to be_empty
        end

        it 'message mentions kinit' do
          cli.send(:check_klist, out, warns)
          expect(warns.first).to include('kinit')
        end
      end

      context 'when klist exits ok but output has no principal/credentials string' do
        before do
          allow(cli).to receive(:shell_capture).with('klist').and_return(['no matching output', true])
        end

        it 'returns status :warn' do
          result = cli.send(:check_klist, out, warns)
          expect(result[:status]).to eq(:warn)
        end
      end

      context 'when shell_capture raises an exception' do
        before do
          allow(cli).to receive(:shell_capture).with('klist').and_raise(Errno::ENOENT, 'klist not found')
        end

        it 'returns status :warn' do
          result = cli.send(:check_klist, out, warns)
          expect(result[:status]).to eq(:warn)
        end

        it 'adds a message mentioning klist check failed' do
          cli.send(:check_klist, out, warns)
          expect(warns.first).to include('klist check failed')
        end
      end
    end

    describe '#check_brew' do
      context 'when brew is available' do
        before do
          allow(cli).to receive(:shell_capture).with('brew --version').and_return(['Homebrew 4.0.0', true])
        end

        it 'returns status :ok' do
          result = cli.send(:check_brew, out, warns)
          expect(result[:status]).to eq(:ok)
        end

        it 'does not add warnings' do
          cli.send(:check_brew, out, warns)
          expect(warns).to be_empty
        end
      end

      context 'when brew is not available' do
        before do
          allow(cli).to receive(:shell_capture).with('brew --version').and_return(['', false])
        end

        it 'returns status :warn' do
          result = cli.send(:check_brew, out, warns)
          expect(result[:status]).to eq(:warn)
        end

        it 'message mentions brew.sh' do
          cli.send(:check_brew, out, warns)
          expect(warns.first).to include('brew.sh')
        end
      end

      context 'when shell_capture raises an exception' do
        before do
          allow(cli).to receive(:shell_capture).with('brew --version').and_raise(Errno::ENOENT, 'brew not found')
        end

        it 'returns status :warn and captures the error' do
          result = cli.send(:check_brew, out, warns)
          expect(result[:status]).to eq(:warn)
          expect(warns.first).to include('brew check failed')
        end
      end
    end

    describe '#check_legionio_binary' do
      context 'when legionio works' do
        before do
          allow(cli).to receive(:shell_capture).with('legionio version').and_return(['legionio 1.6.4', true])
        end

        it 'returns status :ok' do
          result = cli.send(:check_legionio_binary, out, warns)
          expect(result[:status]).to eq(:ok)
        end
      end

      context 'when legionio binary fails' do
        before do
          allow(cli).to receive(:shell_capture).with('legionio version').and_return(['', false])
        end

        it 'returns status :warn' do
          result = cli.send(:check_legionio_binary, out, warns)
          expect(result[:status]).to eq(:warn)
        end

        it 'message mentions reinstall' do
          cli.send(:check_legionio_binary, out, warns)
          expect(warns.first).to include('reinstall')
        end
      end

      context 'when shell_capture raises an exception' do
        before do
          allow(cli).to receive(:shell_capture).with('legionio version').and_raise(Errno::ENOENT, 'not found')
        end

        it 'returns status :warn' do
          result = cli.send(:check_legionio_binary, out, warns)
          expect(result[:status]).to eq(:warn)
        end
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Pack extraction from config JSON
  # ---------------------------------------------------------------------------

  describe 'pack extraction' do
    it 'removes :packs key from config before writing' do
      config = { packs: ['agentic'], llm: { enabled: true } }
      pack_names = Array(config.delete(:packs)).map(&:to_s).reject(&:empty?)
      expect(config).not_to have_key(:packs)
      expect(pack_names).to eq(['agentic'])
    end

    it 'handles missing packs key gracefully' do
      config = { llm: { enabled: true } }
      pack_names = Array(config.delete(:packs)).map(&:to_s).reject(&:empty?)
      expect(pack_names).to eq([])
    end

    it 'handles empty packs array' do
      config = { packs: [], llm: { enabled: true } }
      pack_names = Array(config.delete(:packs)).map(&:to_s).reject(&:empty?)
      expect(pack_names).to eq([])
    end

    it 'handles multiple packs' do
      config = { packs: %w[agentic llm], llm: { enabled: true } }
      pack_names = Array(config.delete(:packs)).map(&:to_s).reject(&:empty?)
      expect(pack_names).to eq(%w[agentic llm])
    end
  end

  # ---------------------------------------------------------------------------
  # Shared stubs used by execute integration tests
  # ---------------------------------------------------------------------------

  def stub_happy_path(opts = {})
    allow(Legion::CLI::ConfigImport).to receive(:fetch_source)
      .and_return(opts.fetch(:body, '{}'))
    allow(Legion::CLI::ConfigImport).to receive(:parse_payload)
      .and_return(opts.fetch(:config, {}))
    allow(Legion::CLI::ConfigImport).to receive(:write_config)
      .and_return(opts.fetch(:paths, ['/tmp/bootstrapped_settings.json']))
    allow(Legion::CLI::ConfigScaffold).to receive(:run).and_return(0)
    allow(cli).to receive(:run_preflight_checks).and_return({})
    allow(cli).to receive(:install_packs).and_return([])
    allow(cli).to receive(:print_summary)
  end

  # ---------------------------------------------------------------------------
  # Config fetch delegation
  # ---------------------------------------------------------------------------

  describe 'config fetch delegation' do
    it 'delegates to ConfigImport.fetch_source for HTTP URLs' do
      expect(Legion::CLI::ConfigImport).to receive(:fetch_source)
        .with('https://example.com/demo.json').and_return('{}')
      stub_happy_path(body: '{}')
      cli.execute('https://example.com/demo.json')
    end

    it 'delegates to ConfigImport.fetch_source for local file paths' do
      expect(Legion::CLI::ConfigImport).to receive(:fetch_source)
        .with('/tmp/bootstrap.json').and_return('{}')
      stub_happy_path(body: '{}')
      cli.execute('/tmp/bootstrap.json')
    end
  end

  # ---------------------------------------------------------------------------
  # Config write delegation
  # ---------------------------------------------------------------------------

  describe 'config write delegation' do
    it 'delegates to ConfigImport.write_config with force: true when --force is set' do
      allow(cli).to receive(:options).and_return(default_options.merge(force: true))
      allow(Legion::CLI::ConfigImport).to receive(:fetch_source).and_return('{}')
      allow(Legion::CLI::ConfigImport).to receive(:parse_payload).and_return({ llm: { enabled: true } })
      expect(Legion::CLI::ConfigImport).to receive(:write_config)
        .with({ llm: { enabled: true } }, force: true).and_return(['/tmp/llm.json'])
      allow(Legion::CLI::ConfigScaffold).to receive(:run).and_return(0)
      allow(cli).to receive(:run_preflight_checks).and_return({})
      allow(cli).to receive(:install_packs).and_return([])
      allow(cli).to receive(:print_summary)
      cli.execute('/tmp/bootstrap.json')
    end

    it 'passes force: false by default' do
      allow(Legion::CLI::ConfigImport).to receive(:fetch_source).and_return('{}')
      allow(Legion::CLI::ConfigImport).to receive(:parse_payload).and_return({})
      expect(Legion::CLI::ConfigImport).to receive(:write_config)
        .with({}, force: false).and_return([])
      allow(Legion::CLI::ConfigScaffold).to receive(:run).and_return(0)
      allow(cli).to receive(:run_preflight_checks).and_return({})
      allow(cli).to receive(:install_packs).and_return([])
      allow(cli).to receive(:print_summary)
      cli.execute('/tmp/bootstrap.json')
    end
  end

  # ---------------------------------------------------------------------------
  # Pack install invocation
  # ---------------------------------------------------------------------------

  describe 'pack install invocation' do
    before do
      allow(cli).to receive(:options).and_return(default_options.merge(skip_packs: false))
      allow(Legion::CLI::ConfigImport).to receive(:fetch_source).and_return('{"packs":["agentic"]}')
      allow(Legion::CLI::ConfigImport).to receive(:parse_payload)
        .and_return({ packs: ['agentic'], llm: { enabled: true } })
      allow(Legion::CLI::ConfigImport).to receive(:write_config).and_return(['/tmp/llm.json'])
      allow(Legion::CLI::ConfigScaffold).to receive(:run).and_return(0)
      allow(cli).to receive(:run_preflight_checks).and_return({})
      allow(cli).to receive(:print_summary)
    end

    it 'calls install_packs with the extracted pack names' do
      expect(cli).to receive(:install_packs).with(['agentic'], out).and_return([])
      cli.execute('/tmp/bootstrap.json')
    end

    context 'when --skip-packs is set' do
      before { allow(cli).to receive(:options).and_return(default_options.merge(skip_packs: true)) }

      it 'does not call install_packs' do
        expect(cli).not_to receive(:install_packs)
        cli.execute('/tmp/bootstrap.json')
      end
    end
  end

  # ---------------------------------------------------------------------------
  # install_packs helper
  # ---------------------------------------------------------------------------

  describe '#install_packs' do
    before do
      allow(RbConfig::CONFIG).to receive(:[]).with('bindir').and_return('/usr/bin')
    end

    it 'warns and skips unknown pack names' do
      expect(out).to receive(:warn).with(a_string_including('Unknown pack'))
      result = cli.send(:install_packs, ['nonexistent_pack'], out)
      expect(result).to be_empty
    end

    it 'returns empty array for empty pack_names' do
      result = cli.send(:install_packs, [], out)
      expect(result).to eq([])
    end

    it 'returns a result entry per known pack' do
      allow(cli).to receive(:install_pack_gems).and_return([{ name: 'legion-llm', status: 'installed' }])
      allow(Gem::Specification).to receive(:reset)
      result = cli.send(:install_packs, ['llm'], out)
      expect(result.size).to eq(1)
      expect(result.first[:pack]).to eq('llm')
    end
  end

  # ---------------------------------------------------------------------------
  # install_single_gem helper
  # ---------------------------------------------------------------------------

  describe '#install_single_gem' do
    let(:gem_bin) { '/usr/bin/gem' }

    context 'when gem installs successfully' do
      before do
        allow(cli).to receive(:shell_capture)
          .with('/usr/bin/gem install lex-foo --no-document')
          .and_return(['Successfully installed lex-foo-0.1.0', true])
      end

      it 'returns installed status' do
        result = cli.send(:install_single_gem, 'lex-foo', gem_bin, out)
        expect(result).to eq({ name: 'lex-foo', status: 'installed' })
      end
    end

    context 'when gem install fails' do
      before do
        allow(cli).to receive(:shell_capture)
          .with('/usr/bin/gem install lex-foo --no-document')
          .and_return(["ERROR: Could not find gem 'lex-foo'", false])
      end

      it 'returns failed status with error message' do
        result = cli.send(:install_single_gem, 'lex-foo', gem_bin, out)
        expect(result[:status]).to eq('failed')
        expect(result[:error]).to be_a(String)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # build_summary
  # ---------------------------------------------------------------------------

  describe '#build_summary' do
    let(:config)  { { llm: { enabled: true } } }
    let(:results) { { packs_requested: ['agentic'], packs_installed: [], preflight: {} } }
    let(:warns)   { ['test warning'] }

    before do
      Legion::CLI::ConfigScaffold::SUBSYSTEMS.each do |s|
        path = File.join(Legion::CLI::ConfigImport::SETTINGS_DIR, "#{s}.json")
        allow(File).to receive(:exist?).with(path).and_return(true)
      end
    end

    it 'includes config_sections' do
      summary = cli.send(:build_summary, config, results, warns)
      expect(summary[:config_sections]).to include('llm')
    end

    it 'includes packs_requested' do
      summary = cli.send(:build_summary, config, results, warns)
      expect(summary[:packs_requested]).to eq(['agentic'])
    end

    it 'includes warnings' do
      summary = cli.send(:build_summary, config, results, warns)
      expect(summary[:warnings]).to eq(['test warning'])
    end

    it 'includes subsystem_files hash keyed by subsystem names' do
      summary = cli.send(:build_summary, config, results, warns)
      expect(summary[:subsystem_files]).to be_a(Hash)
      expect(summary[:subsystem_files].keys).to include(*Legion::CLI::ConfigScaffold::SUBSYSTEMS)
    end
  end

  # ---------------------------------------------------------------------------
  # build_scaffold_opts
  # ---------------------------------------------------------------------------

  describe '#build_scaffold_opts' do
    it 'returns a hash with force: false' do
      opts = cli.send(:build_scaffold_opts)
      expect(opts[:force]).to be false
    end

    it 'returns a hash with json: false' do
      opts = cli.send(:build_scaffold_opts)
      expect(opts[:json]).to be false
    end
  end

  # ---------------------------------------------------------------------------
  # --skip-packs flag
  # ---------------------------------------------------------------------------

  describe '--skip-packs flag' do
    before do
      allow(cli).to receive(:options).and_return(default_options.merge(skip_packs: true))
      stub_happy_path(config: { packs: ['agentic'], llm: { enabled: true } })
      allow(Legion::CLI::ConfigImport).to receive(:parse_payload)
        .and_return({ packs: ['agentic'], llm: { enabled: true } })
    end

    it 'skips pack installation' do
      expect(cli).not_to receive(:install_packs)
      cli.execute('/tmp/bootstrap.json')
    end

    it 'sets packs_installed to empty array in results' do
      results_captured = nil
      allow(cli).to receive(:build_summary) do |_config, results, _warns|
        results_captured = results
        {}
      end
      allow(cli).to receive(:print_summary)
      cli.execute('/tmp/bootstrap.json')
      expect(results_captured[:packs_installed]).to eq([])
    end
  end

  # ---------------------------------------------------------------------------
  # --start flag
  # ---------------------------------------------------------------------------

  describe '--start flag' do
    before do
      allow(cli).to receive(:options).and_return(default_options.merge(start: true))
      stub_happy_path
    end

    it 'calls start_services when --start is set' do
      expect(cli).to receive(:start_services).with(out).and_return({ redis: true, legionio: true })
      cli.execute('/tmp/bootstrap.json')
    end

    it 'does not call start_services when --start is false' do
      allow(cli).to receive(:options).and_return(default_options.merge(start: false))
      expect(cli).not_to receive(:start_services)
      cli.execute('/tmp/bootstrap.json')
    end
  end

  # ---------------------------------------------------------------------------
  # --json output mode
  # ---------------------------------------------------------------------------

  describe '--json output mode' do
    before do
      allow(cli).to receive(:options).and_return(default_options.merge(json: true))
      stub_happy_path
      allow(cli).to receive(:build_summary).and_return({ config_sections: [] })
      allow(cli).to receive(:print_summary)
    end

    it 'calls out.json with the results hash containing config_written array' do
      expect(out).to receive(:json).with(hash_including(config_written: ['/tmp/bootstrapped_settings.json']))
      cli.execute('/tmp/bootstrap.json')
    end

    it 'does not call out.header' do
      expect(out).not_to receive(:header)
      cli.execute('/tmp/bootstrap.json')
    end
  end

  # ---------------------------------------------------------------------------
  # Error handling
  # ---------------------------------------------------------------------------

  describe 'error handling' do
    context 'when fetch_source raises CLI::Error (bad URL / 404)' do
      before do
        allow(Legion::CLI::ConfigImport).to receive(:fetch_source)
          .and_raise(Legion::CLI::Error, 'HTTP 404: Not Found')
        allow(cli).to receive(:run_preflight_checks).and_return({})
      end

      it 'outputs the error message' do
        expect(out).to receive(:error).with('HTTP 404: Not Found')
        expect { cli.execute('https://example.com/missing.json') }.to raise_error(SystemExit)
      end
    end

    context 'when parse_payload raises CLI::Error (invalid JSON)' do
      before do
        allow(Legion::CLI::ConfigImport).to receive(:fetch_source).and_return('not json')
        allow(Legion::CLI::ConfigImport).to receive(:parse_payload)
          .and_raise(Legion::CLI::Error, 'Source is not valid JSON or base64-encoded JSON')
        allow(cli).to receive(:run_preflight_checks).and_return({})
      end

      it 'outputs the error and raises SystemExit' do
        expect(out).to receive(:error).with(a_string_including('not valid JSON'))
        expect { cli.execute('/tmp/bad.json') }.to raise_error(SystemExit)
      end
    end

    context 'when fetch_source raises CLI::Error (network / 503)' do
      before do
        allow(Legion::CLI::ConfigImport).to receive(:fetch_source)
          .and_raise(Legion::CLI::Error, 'HTTP 503: Service Unavailable')
        allow(cli).to receive(:run_preflight_checks).and_return({})
      end

      it 'outputs error and raises SystemExit' do
        expect(out).to receive(:error).with(a_string_including('503'))
        expect { cli.execute('https://example.com/bootstrap.json') }.to raise_error(SystemExit)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # run_brew_service helper
  # ---------------------------------------------------------------------------

  describe '#run_brew_service' do
    context 'when brew services start succeeds' do
      before do
        allow(cli).to receive(:shell_capture)
          .with('brew services start redis').and_return(['Successfully started redis', true])
      end

      it 'returns true' do
        result = cli.send(:run_brew_service, 'redis', out)
        expect(result).to be true
      end
    end

    context 'when brew services start fails' do
      before do
        allow(cli).to receive(:shell_capture)
          .with('brew services start redis').and_return(['Error: redis not installed', false])
      end

      it 'returns false' do
        result = cli.send(:run_brew_service, 'redis', out)
        expect(result).to be false
      end
    end

    context 'when shell_capture raises an exception' do
      before do
        allow(cli).to receive(:shell_capture)
          .with('brew services start redis').and_raise(Errno::ENOENT, 'brew not found')
      end

      it 'returns false without raising' do
        result = cli.send(:run_brew_service, 'redis', out)
        expect(result).to be false
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Summary output (print_summary smoke)
  # ---------------------------------------------------------------------------

  describe '#print_summary' do
    let(:summary) do
      {
        config_sections: %w[llm transport],
        packs_requested: ['agentic'],
        packs_installed: [{ pack: 'agentic', results: [{ name: 'legion-llm', status: 'installed' }] }],
        subsystem_files: { 'transport' => true, 'data' => false },
        warnings:        [],
        preflight:       {}
      }
    end

    it 'calls out.header with Bootstrap Summary' do
      expect(out).to receive(:header).with('Bootstrap Summary')
      cli.send(:print_summary, out, summary)
    end

    it 'calls out.success for successfully installed packs' do
      expect(out).to receive(:success).with(a_string_including('agentic'))
      cli.send(:print_summary, out, summary)
    end

    it 'prints warnings section when warnings are present' do
      summary_with_warn = summary.merge(warnings: ['something went wrong'])
      expect(out).to receive(:warn).with('something went wrong')
      cli.send(:print_summary, out, summary_with_warn)
    end

    it 'is a no-op in json mode' do
      allow(cli).to receive(:options).and_return(default_options.merge(json: true))
      expect(out).not_to receive(:header)
      cli.send(:print_summary, out, summary)
    end
  end
end
