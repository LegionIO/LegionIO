# frozen_string_literal: true

require 'spec_helper'
require 'legion/extensions/builders/absorbers'

RSpec.describe Legion::Extensions::Builder::Absorbers do
  let(:dummy_builder) do
    Class.new do
      include Legion::Extensions::Builder::Absorbers

      def lex_name
        'test_lex'
      end

      def lex_class
        'Lex::TestLex'
      end

      def find_files(_dir)
        []
      end

      def require_files(_files); end
    end.new
  end

  let(:absorber_class) do
    Class.new(Legion::Extensions::Absorbers::Base) do
      def self.name
        'Lex::TestLex::Absorbers::WebPage'
      end

      def self.patterns
        [{ type: :url, value: 'example.com/*', priority: 100 }]
      end

      def self.description
        'Absorbs web pages'
      end

      def absorb(url: nil, **_kwargs)
        { url: url }
      end
    end
  end

  describe '#build_absorbers' do
    context 'when Legion::API is not defined' do
      before do
        allow(dummy_builder).to receive(:find_files).with('absorbers').and_return(['/fake/web_page.rb'])
        allow(dummy_builder).to receive(:require_files)
        allow(Kernel).to receive(:const_defined?).and_call_original
        allow(Kernel).to receive(:const_defined?).with('Lex::TestLex::Absorbers::WebPage').and_return(true)
        allow(Kernel).to receive(:const_get).with('Lex::TestLex::Absorbers::WebPage').and_return(absorber_class)
        hide_const('Legion::API') if defined?(Legion::API)
      end

      it 'registers the absorber with PatternMatcher without raising' do
        expect(Legion::Extensions::Absorbers::PatternMatcher).to receive(:register).with(absorber_class)
        expect { dummy_builder.build_absorbers }.not_to raise_error
      end

      it 'populates @absorbers hash' do
        allow(Legion::Extensions::Absorbers::PatternMatcher).to receive(:register)
        dummy_builder.build_absorbers
        expect(dummy_builder.absorbers).to have_key(:web_page)
      end
    end

    context 'when Legion::API is available with a router' do
      let(:mock_router) { instance_double('Legion::API::Router') }

      before do
        allow(dummy_builder).to receive(:find_files).with('absorbers').and_return(['/fake/web_page.rb'])
        allow(dummy_builder).to receive(:require_files)
        allow(Kernel).to receive(:const_defined?).and_call_original
        allow(Kernel).to receive(:const_defined?).with('Lex::TestLex::Absorbers::WebPage').and_return(true)
        allow(Kernel).to receive(:const_get).with('Lex::TestLex::Absorbers::WebPage').and_return(absorber_class)
        allow(Legion::Extensions::Absorbers::PatternMatcher).to receive(:register)

        stub_const('Legion::API', Module.new)
        allow(Legion::API).to receive(:respond_to?).with(:router).and_return(true)
        allow(Legion::API).to receive(:router).and_return(mock_router)
        allow(mock_router).to receive(:register_extension_route)
      end

      it 'calls register_extension_route with component_type absorbers' do
        expect(mock_router).to receive(:register_extension_route).with(
          hash_including(component_type: 'absorbers')
        ).at_least(:once)
        dummy_builder.build_absorbers
      end

      it 'passes the correct lex_name' do
        expect(mock_router).to receive(:register_extension_route).with(
          hash_including(lex_name: 'test_lex')
        ).at_least(:once)
        dummy_builder.build_absorbers
      end

      it 'passes the absorber class as runner_class' do
        expect(mock_router).to receive(:register_extension_route).with(
          hash_including(runner_class: absorber_class)
        ).at_least(:once)
        dummy_builder.build_absorbers
      end

      it 'passes the snake_name as component_name' do
        expect(mock_router).to receive(:register_extension_route).with(
          hash_including(component_name: 'web_page')
        ).at_least(:once)
        dummy_builder.build_absorbers
      end

      it 'passes the default amqp_prefix when amqp_prefix is not defined' do
        expect(mock_router).to receive(:register_extension_route).with(
          hash_including(amqp_prefix: 'lex.test_lex')
        ).at_least(:once)
        dummy_builder.build_absorbers
      end
    end

    context 'when absorber class has no public instance methods' do
      let(:bare_absorber_class) do
        Class.new(Legion::Extensions::Absorbers::Base) do
          def self.name
            'Lex::TestLex::Absorbers::Bare'
          end

          def self.patterns
            []
          end

          def self.description
            nil
          end
        end
      end

      let(:mock_router) { instance_double('Legion::API::Router') }

      before do
        allow(dummy_builder).to receive(:find_files).with('absorbers').and_return(['/fake/bare.rb'])
        allow(dummy_builder).to receive(:require_files)
        allow(Kernel).to receive(:const_defined?).and_call_original
        allow(Kernel).to receive(:const_defined?).with('Lex::TestLex::Absorbers::Bare').and_return(true)
        allow(Kernel).to receive(:const_get).with('Lex::TestLex::Absorbers::Bare').and_return(bare_absorber_class)
        allow(Legion::Extensions::Absorbers::PatternMatcher).to receive(:register)

        stub_const('Legion::API', Module.new)
        allow(Legion::API).to receive(:respond_to?).with(:router).and_return(true)
        allow(Legion::API).to receive(:router).and_return(mock_router)
        allow(mock_router).to receive(:register_extension_route)
      end

      it 'falls back to :absorb as the method_name' do
        expect(mock_router).to receive(:register_extension_route).with(
          hash_including(method_name: 'absorb')
        )
        dummy_builder.build_absorbers
      end
    end

    context 'when absorber files list is empty' do
      before do
        allow(dummy_builder).to receive(:find_files).with('absorbers').and_return([])
      end

      it 'returns early without populating @absorbers' do
        dummy_builder.build_absorbers
        expect(dummy_builder.absorbers).to be_empty
      end
    end
  end

  describe '#absorbers' do
    it 'returns an empty hash before build_absorbers is called' do
      expect(dummy_builder.absorbers).to eq({})
    end
  end
end
