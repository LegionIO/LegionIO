# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli/auth_command'

RSpec.describe Legion::CLI::Auth do
  it 'registers kerberos as a Thor command' do
    expect(described_class.commands).to have_key('kerberos')
  end

  it 'has the correct description for kerberos' do
    expect(described_class.commands['kerberos'].description).to eq('Authenticate using Kerberos TGT from your workstation')
  end
end
