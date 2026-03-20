# frozen_string_literal: true

require 'spec_helper'
require 'legion/extensions/builders/routes'

RSpec.describe Legion::Extensions::Builder::Routes do
  let(:dummy_builder) do
    Class.new do
      include Legion::Extensions::Builder::Routes

      def extension_name
        'test_lex'
      end

      def lex_name
        'test_lex'
      end

      def lex_class
        'Lex::TestLex'
      end

      def settings
        {}
      end
    end.new
  end

  let(:simple_runner_module) do
    Module.new do
      def process_item; end

      def fetch_data; end
    end
  end

  let(:runner_with_skip) do
    mod = Module.new do
      def process_item; end

      def internal_helper; end

      def self.skip_routes
        %i[internal_helper]
      end
    end
    mod
  end

  let(:empty_runner_module) do
    Module.new
  end

  def setup_runners(builder, runners_hash)
    builder.instance_variable_set(:@runners, runners_hash)
  end

  before do
    allow(Legion::Settings).to receive(:dig).with(:api, :lex_routes).and_return(nil)
  end

  describe '#build_routes' do
    context 'with a simple runner module' do
      before do
        setup_runners(dummy_builder, {
                        runner1: {
                          runner_name:   'runner1',
                          runner_class:  'TestLex::Runners::Runner1',
                          runner_module: simple_runner_module
                        }
                      })
        dummy_builder.build_routes
      end

      it 'populates @routes' do
        expect(dummy_builder.routes).not_to be_empty
      end

      it 'creates route entries for each public instance method' do
        methods = dummy_builder.routes.values.map { |r| r[:function] }
        expect(methods).to include(:process_item)
        expect(methods).to include(:fetch_data)
      end

      it 'includes required keys in each route entry' do
        route = dummy_builder.routes.values.first
        expect(route).to have_key(:lex_name)
        expect(route).to have_key(:runner_name)
        expect(route).to have_key(:function)
        expect(route).to have_key(:runner_class)
        expect(route).to have_key(:route_path)
      end

      it 'sets lex_name to the extension name' do
        route = dummy_builder.routes.values.first
        expect(route[:lex_name]).to eq('test_lex')
      end

      it 'sets runner_name from the runner entry' do
        route = dummy_builder.routes.values.first
        expect(route[:runner_name]).to eq('runner1')
      end

      it 'sets runner_class from the runner entry' do
        route = dummy_builder.routes.values.first
        expect(route[:runner_class]).to eq('TestLex::Runners::Runner1')
      end

      it 'builds route_path as lex_name/runner_name/function' do
        route = dummy_builder.routes.values.find { |r| r[:function] == :process_item }
        expect(route[:route_path]).to eq('test_lex/runner1/process_item')
      end
    end

    context 'with no runners' do
      before do
        setup_runners(dummy_builder, {})
        dummy_builder.build_routes
      end

      it 'results in empty routes' do
        expect(dummy_builder.routes).to be_empty
      end
    end

    context 'with an empty runner module' do
      before do
        setup_runners(dummy_builder, {
                        empty_runner: {
                          runner_name:   'empty_runner',
                          runner_class:  'TestLex::Runners::EmptyRunner',
                          runner_module: empty_runner_module
                        }
                      })
        dummy_builder.build_routes
      end

      it 'produces no route entries' do
        expect(dummy_builder.routes).to be_empty
      end
    end

    context 'with skip_routes DSL on runner module' do
      before do
        setup_runners(dummy_builder, {
                        runner1: {
                          runner_name:   'runner1',
                          runner_class:  'TestLex::Runners::Runner1',
                          runner_module: runner_with_skip
                        }
                      })
        dummy_builder.build_routes
      end

      it 'excludes methods listed in skip_routes' do
        methods = dummy_builder.routes.values.map { |r| r[:function] }
        expect(methods).not_to include(:internal_helper)
      end

      it 'includes methods not in skip_routes' do
        methods = dummy_builder.routes.values.map { |r| r[:function] }
        expect(methods).to include(:process_item)
      end
    end

    context 'when globally disabled via settings' do
      before do
        allow(Legion::Settings).to receive(:dig).with(:api, :lex_routes).and_return({ enabled: false })
        setup_runners(dummy_builder, {
                        runner1: {
                          runner_name:   'runner1',
                          runner_class:  'TestLex::Runners::Runner1',
                          runner_module: simple_runner_module
                        }
                      })
        dummy_builder.build_routes
      end

      it 'returns empty routes' do
        expect(dummy_builder.routes).to be_empty
      end
    end

    context 'when extension is disabled in settings' do
      before do
        allow(Legion::Settings).to receive(:dig).with(:api, :lex_routes).and_return({
                                                                                      enabled:    true,
                                                                                      extensions: { test_lex: { enabled: false } }
                                                                                    })
        setup_runners(dummy_builder, {
                        runner1: {
                          runner_name:   'runner1',
                          runner_class:  'TestLex::Runners::Runner1',
                          runner_module: simple_runner_module
                        }
                      })
        dummy_builder.build_routes
      end

      it 'skips the disabled extension' do
        expect(dummy_builder.routes).to be_empty
      end
    end

    context 'when a runner is in exclude_runners settings' do
      before do
        allow(Legion::Settings).to receive(:dig).with(:api, :lex_routes).and_return({
                                                                                      enabled:    true,
                                                                                      extensions: { test_lex: { exclude_runners: ['runner1'] } }
                                                                                    })
        setup_runners(dummy_builder, {
                        runner1: {
                          runner_name:   'runner1',
                          runner_class:  'TestLex::Runners::Runner1',
                          runner_module: simple_runner_module
                        }
                      })
        dummy_builder.build_routes
      end

      it 'skips excluded runners' do
        expect(dummy_builder.routes).to be_empty
      end
    end

    context 'when a function is in exclude_functions settings' do
      before do
        allow(Legion::Settings).to receive(:dig).with(:api, :lex_routes).and_return({
                                                                                      enabled:    true,
                                                                                      extensions: { test_lex: { exclude_functions: ['fetch_data'] } }
                                                                                    })
        setup_runners(dummy_builder, {
                        runner1: {
                          runner_name:   'runner1',
                          runner_class:  'TestLex::Runners::Runner1',
                          runner_module: simple_runner_module
                        }
                      })
        dummy_builder.build_routes
      end

      it 'excludes the specified function' do
        methods = dummy_builder.routes.values.map { |r| r[:function] }
        expect(methods).not_to include(:fetch_data)
      end

      it 'keeps other functions from the same runner' do
        methods = dummy_builder.routes.values.map { |r| r[:function] }
        expect(methods).to include(:process_item)
      end
    end

    context 'with multiple runners' do
      let(:second_runner_module) do
        Module.new do
          def execute; end
        end
      end

      before do
        setup_runners(dummy_builder, {
                        runner1: {
                          runner_name:   'runner1',
                          runner_class:  'TestLex::Runners::Runner1',
                          runner_module: simple_runner_module
                        },
                        runner2: {
                          runner_name:   'runner2',
                          runner_class:  'TestLex::Runners::Runner2',
                          runner_module: second_runner_module
                        }
                      })
        dummy_builder.build_routes
      end

      it 'registers routes from all runners' do
        methods = dummy_builder.routes.values.map { |r| r[:function] }
        expect(methods).to include(:process_item)
        expect(methods).to include(:fetch_data)
        expect(methods).to include(:execute)
      end

      it 'uses unique route_path keys' do
        paths = dummy_builder.routes.keys
        expect(paths.uniq.length).to eq(paths.length)
      end
    end

    context 'only includes instance_methods(false)' do
      let(:derived_runner_module) do
        parent = Module.new do
          def inherited_method; end
        end
        mod = Module.new do
          include parent

          def own_method; end
        end
        mod
      end

      before do
        setup_runners(dummy_builder, {
                        runner1: {
                          runner_name:   'runner1',
                          runner_class:  'TestLex::Runners::Runner1',
                          runner_module: derived_runner_module
                        }
                      })
        dummy_builder.build_routes
      end

      it 'does not register inherited methods' do
        methods = dummy_builder.routes.values.map { |r| r[:function] }
        expect(methods).not_to include(:inherited_method)
      end

      it 'does register directly defined methods' do
        methods = dummy_builder.routes.values.map { |r| r[:function] }
        expect(methods).to include(:own_method)
      end
    end
  end

  describe '#routes attr_reader' do
    it 'returns nil before build_routes is called' do
      expect(dummy_builder.routes).to be_nil
    end
  end
end
