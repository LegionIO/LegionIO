# frozen_string_literal: true

require_relative 'api_spec_helper'

RSpec.describe 'Old route systems removed' do
  before(:all) { ApiSpecSetup.configure_settings }

  describe 'Legion::API class methods' do
    it 'does not respond to hook_registry' do
      expect(Legion::API).not_to respond_to(:hook_registry)
    end

    it 'does not respond to register_hook' do
      expect(Legion::API).not_to respond_to(:register_hook)
    end

    it 'does not respond to find_hook' do
      expect(Legion::API).not_to respond_to(:find_hook)
    end

    it 'does not respond to find_hook_by_path' do
      expect(Legion::API).not_to respond_to(:find_hook_by_path)
    end

    it 'does not respond to registered_hooks' do
      expect(Legion::API).not_to respond_to(:registered_hooks)
    end

    it 'does not respond to route_registry' do
      expect(Legion::API).not_to respond_to(:route_registry)
    end

    it 'does not respond to register_route' do
      expect(Legion::API).not_to respond_to(:register_route)
    end

    it 'does not respond to find_route_by_path' do
      expect(Legion::API).not_to respond_to(:find_route_by_path)
    end

    it 'does not respond to registered_routes' do
      expect(Legion::API).not_to respond_to(:registered_routes)
    end

    it 'responds to router' do
      expect(Legion::API).to respond_to(:router)
    end
  end
end
