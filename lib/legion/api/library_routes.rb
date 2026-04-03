# frozen_string_literal: true

module Legion
  class API < Sinatra::Base
    # Register a library gem's route module with the tier-aware router and mount it
    # on this Sinatra app.
    #
    # Call from the library gem's boot/start method:
    #   Legion::API.register_library_routes('llm', Legion::LLM::Routes) if defined?(Legion::API)
    #
    # @param gem_name [String] short name for the library (e.g. 'llm', 'apollo')
    # @param routes_module [Module] a Sinatra::Extension module to register
    def self.register_library_routes(gem_name, routes_module)
      existing = router.library_routes[gem_name.to_s]
      return routes_module if existing == routes_module

      router.register_library(gem_name, routes_module)
      register routes_module
    end
  end
end
