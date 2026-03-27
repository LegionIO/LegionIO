# frozen_string_literal: true

require 'spec_helper'
require 'thor'
require 'legion/cli/output'
require 'legion/cli/generate_command'

RSpec.describe 'legion generate absorber' do
  it 'has the absorber subcommand' do
    expect(Legion::CLI::Generate.instance_methods).to include(:absorber)
  end
end
