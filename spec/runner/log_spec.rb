# frozen_string_literal: true

require 'spec_helper'
require 'legion/runner/log'

RSpec.describe Legion::Runner::Log do
  describe 'it should have things' do
    it { is_expected.to be_a Module }
    it { is_expected.to respond_to :exception }
  end
end
