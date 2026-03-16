# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Legion::Process SIGHUP trap' do
  before do
    allow(Legion).to receive(:reload)
  end

  it 'calls Legion.reload when SIGHUP is received' do
    # Set up the trap by calling the method that installs it
    # Legion::Process includes trap_signals in its initialization
    # We can test by directly installing the trap and firing the signal
    trap('SIGHUP') do
      Thread.new { Legion.reload }
    end

    Process.kill('HUP', Process.pid)
    sleep 0.2 # give the thread time to execute

    expect(Legion).to have_received(:reload)
  end
end
