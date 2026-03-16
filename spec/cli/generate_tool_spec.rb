# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'legion/cli'

RSpec.describe 'legion generate tool' do
  let(:generator) { Legion::CLI::Generate.new }
  let(:tmpparent) { Dir.mktmpdir }
  let(:tmpdir) { File.join(tmpparent, 'lex-redis').tap { |d| FileUtils.mkdir_p(d) } }

  before { Dir.chdir(tmpdir) }

  after do
    Dir.chdir(File.expand_path('../../..', __dir__))
    FileUtils.rm_rf(tmpparent)
  end

  it 'creates the tool file' do
    generator.tool('get_key')
    path = File.join(tmpdir, 'lib/legion/extensions/redis/tools/get_key.rb')
    expect(File.exist?(path)).to be true
  end

  it 'creates the spec file' do
    generator.tool('get_key')
    path = File.join(tmpdir, 'spec/tools/get_key_spec.rb')
    expect(File.exist?(path)).to be true
  end

  it 'generates valid Ruby in the tool file' do
    generator.tool('get_key')
    path = File.join(tmpdir, 'lib/legion/extensions/redis/tools/get_key.rb')
    content = File.read(path)
    expect(content).to include('class GetKey < RubyLLM::Tool')
    expect(content).to include('permission_tier :write')
    expect(content).to include('def execute')
    expect(content).to include('Legion::Extensions::Redis::Client')
  end

  it 'generates valid Ruby in the spec file' do
    generator.tool('get_key')
    path = File.join(tmpdir, 'spec/tools/get_key_spec.rb')
    content = File.read(path)
    expect(content).to include('RSpec.describe Legion::Extensions::Redis::Tools::GetKey')
    expect(content).to include('be_a(String)')
  end
end
