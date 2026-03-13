# frozen_string_literal: true

require 'spec_helper'
require 'legion/runner/log'

RSpec.describe Legion::Runner::Status do
  describe 'it should have things' do
    it { is_expected.to be_a Module }
    it { is_expected.to respond_to :update }
    it { is_expected.to respond_to :update_rmq }
    it { is_expected.to respond_to :update_db }
    it { is_expected.to respond_to :generate_task_id }
  end
end
