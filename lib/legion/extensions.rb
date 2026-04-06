# frozen_string_literal: true

require 'legion/extensions/core'
require 'legion/extensions/capability'
require 'legion/extensions/catalog'
require 'legion/extensions/permissions'
require 'legion/runner'

module Legion
  module Extensions
    class << self
      def setup
        hook_extensions
      end

      def hook_extensions
        @timer_tasks = []
        @loop_tasks = []
        @once_tasks = []
        @poll_tasks = []
        @subscription_tasks = []
        @local_tasks = []
        @actors = []
        @running_instances = Concurrent::Array.new
        @pending_actors = Concurrent::Array.new

        find_extensions
        load_extensions
        load_yaml_agents
        hook_all_actors
      end

      attr_reader :local_tasks

      def shutdown # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/AbcSize
        return nil if @loaded_extensions.nil?

        deadline = Legion::Settings.dig(:extensions, :shutdown_timeout) || 15
        shutdown_start = Time.now

        @loaded_extensions.each { |name| Catalog.transition(name, :stopping) }

        if @subscription_pool
          @subscription_pool.shutdown
          @subscription_pool.kill unless @subscription_pool.wait_for_termination(5)
          @subscription_pool = nil
        end

        # Cancel all running instances (real objects, not new instances)
        @running_instances&.each do |instance|
          instance.cancel if instance.respond_to?(:cancel)
        rescue StandardError => e
          Legion::Logging.debug "Extension shutdown cancel failed: #{e.message}" if defined?(Legion::Logging)
        end

        # Wait for in-flight work to drain, up to deadline
        remaining = deadline - (Time.now - shutdown_start)
        if remaining.positive?
          drain_start = Time.now
          loop do
            elapsed = Time.now - drain_start
            break if elapsed >= remaining

            still_active = @running_instances&.any? do |inst|
              (inst.respond_to?(:channel) && inst.instance_variable_get(:@queue)&.channel&.open?) ||
                (inst.instance_variable_get(:@timer).respond_to?(:running?) && inst.instance_variable_get(:@timer).running?) ||
                (inst.instance_variable_get(:@loop) == true)
            end
            break unless still_active

            sleep 0.25
          end
        end

        # Force-close any channels still open after deadline
        elapsed = Time.now - shutdown_start
        if elapsed >= deadline
          Legion::Logging.warn "Shutdown deadline (#{deadline}s) reached, force-closing remaining actors" if defined?(Legion::Logging)
          @running_instances&.each do |inst|
            queue = inst.instance_variable_get(:@queue)
            queue&.channel&.close if queue&.channel.respond_to?(:close) && queue.channel.open?
            timer = inst.instance_variable_get(:@timer)
            timer&.kill if timer.respond_to?(:kill)
            inst.instance_variable_set(:@loop, false) if inst.instance_variable_defined?(:@loop)
          rescue StandardError => e
            Legion::Logging.debug "Force-close failed: #{e.message}" if defined?(Legion::Logging)
          end
        end

        @running_instances&.clear

        Legion::Dispatch.shutdown if defined?(Legion::Dispatch) && Legion::Dispatch.instance_variable_get(:@dispatcher)

        @loaded_extensions.each do |name|
          Catalog.transition(name, :stopped)
          unregister_capabilities(name)
        end
        Legion::Logging.info "Successfully shut down all actors (#{(Time.now - shutdown_start).round(1)}s)"
      end

      def pause_actors
        @running_instances&.each do |inst|
          timer = inst.instance_variable_get(:@timer)
          timer&.shutdown if timer.respond_to?(:shutdown)
        rescue StandardError => e
          Legion::Logging.error "pause_actors: #{e.class}: #{e.message}" if defined?(Legion::Logging)
        end
        Legion::Logging.warn 'All actors paused' if defined?(Legion::Logging)
      end

      def load_extensions
        @extensions ||= []
        @loaded_extensions ||= []

        eligible = @extensions.filter_map do |entry|
          gem_name = entry[:gem_name]
          ext_name = entry[:require_path].split('/').last

          if Legion::Settings[:extensions].key?(ext_name.to_sym) &&
             Legion::Settings[:extensions][ext_name.to_sym].is_a?(Hash) &&
             Legion::Settings[:extensions][ext_name.to_sym].key?(:enabled) &&
             !Legion::Settings[:extensions][ext_name.to_sym][:enabled]
            Legion::Logging.info "Skipping #{gem_name} because it's disabled"
            next
          end

          Catalog.register(gem_name)
          entry
        end

        load_extensions_parallel(eligible)

        Legion::Logging.info(
          "#{@extensions.count} extensions loaded with " \
          "subscription:#{@subscription_tasks.count}," \
          "every:#{@timer_tasks.count}," \
          "poll:#{@poll_tasks.count}," \
          "once:#{@once_tasks.count}," \
          "loop:#{@loop_tasks.count}"
        )
      end

      def load_extensions_parallel(eligible)
        return if eligible.empty?

        if defined?(Legion::Transport::Connection) && Legion::Transport::Connection.respond_to?(:open_build_session)
          Legion::Transport::Connection.open_build_session
        end

        max_threads = Legion::Settings.dig(:extensions, :parallel_pool_size) || 24
        pool_size = [eligible.count, max_threads].min
        executor = Concurrent::FixedThreadPool.new(pool_size)

        futures = eligible.map do |entry|
          Concurrent::Promises.future_on(executor, entry) do |e|
            Thread.current[:legion_build_session] = true
            load_extension(e) ? e : nil
          end
        end

        results = futures.map(&:value)

        executor.shutdown
        executor.wait_for_termination(30)

        if defined?(Legion::Transport::Connection) && Legion::Transport::Connection.respond_to?(:close_build_session)
          Legion::Transport::Connection.close_build_session
        end

        results.each_with_index do |result, idx|
          if result
            Catalog.transition(result[:gem_name], :loaded)
            register_in_registry(gem_name: result[:gem_name], version: result[:version])
            @loaded_extensions.push(result[:gem_name])
          else
            Legion::Logging.warn("#{eligible[idx][:gem_name]} failed to load")
          end
        end
      end

      def load_extension(entry) # rubocop:disable Metrics/PerceivedComplexity, Metrics/CyclomaticComplexity, Metrics/AbcSize, Metrics/MethodLength
        ensure_namespace(entry[:const_path]) if entry[:segments].length > 1
        return unless gem_load(entry)

        extension = Kernel.const_get(entry[:const_path])
        extension.extend Legion::Extensions::Core unless extension.singleton_class.include?(Legion::Extensions::Core)

        ext_name = entry[:segments].join('_')
        ext_settings = Legion::Settings[:extensions][ext_name.to_sym]
        min_version = ext_settings[:min_version] if ext_settings.is_a?(Hash)
        if min_version.is_a?(String)
          begin
            gem_spec = Gem::Specification.find_by_name(entry[:gem_name])
            if Gem::Version.new(gem_spec.version.to_s) < Gem::Version.new(min_version)
              Legion::Logging.warn "#{entry[:gem_name]} v#{gem_spec.version} below min_version #{min_version}, skipping"
              return false
            end
          rescue Gem::MissingSpecError
            Legion::Logging.warn "Could not find gem spec for #{entry[:gem_name]}, skipping min_version check"
          end
        end

        if extension.data_required? && Legion::Settings[:data][:connected] == false
          Legion::Logging.warn "#{ext_name} requires Legion::Data but isn't enabled, skipping"
          return false
        end

        if extension.cache_required? && Legion::Settings[:cache][:connected] == false
          Legion::Logging.warn "#{ext_name} requires Legion::Cache but isn't enabled, skipping"
          return false
        end

        if extension.crypt_required? && Legion::Settings[:crypt][:cs].nil?
          Legion::Logging.warn "#{ext_name} requires Legion::Crypt but isn't ready, skipping"
          return false
        end

        if extension.vault_required? && Legion::Settings[:crypt][:vault][:connected] == false
          Legion::Logging.warn "#{ext_name} requires Legion::Crypt::Vault but isn't enabled, skipping"
          return false
        end

        if extension.llm_required? && (Legion::Settings[:llm].nil? || Legion::Settings[:llm][:connected] == false)
          Legion::Logging.warn "#{ext_name} requires Legion::LLM but isn't enabled, skipping"
          return false
        end

        has_logger = extension.respond_to?(:log)
        extension.autobuild

        require 'legion/transport/messages/lex_register'
        Legion::Transport::Messages::LexRegister.new(function: 'save', opts: extension.runners).publish

        register_capabilities(entry[:gem_name], extension.runners) if extension.respond_to?(:runners)
        write_lex_cli_manifest(entry, extension)
        register_absorber_capabilities(entry[:gem_name], extension.absorbers) if extension.respond_to?(:absorbers)

        if extension.respond_to?(:meta_actors) && extension.meta_actors.is_a?(Hash)
          extension.meta_actors.each_value do |actor|
            extension.log.debug("deferring meta actor: #{actor}") if has_logger
            @pending_actors << actor
          end
        end

        extension.actors.each_value do |actor|
          extension.log.debug("deferring literal actor: #{actor}") if has_logger
          @pending_actors << actor
        end
        extension.log.info "Loaded v#{extension::VERSION}"
        Legion::Events.emit('extension.loaded', name: ext_name, version: entry[:gem_name])

        begin
          if defined?(Legion::Data) && defined?(Legion::Data::Model::DigitalWorker)
            worker_id = "lex-#{ext_name}"
            worker = Legion::Data::Model::DigitalWorker.find_or_create(worker_id: worker_id) do |w|
              w.name            = ext_name
              w.extension_name  = ext_name
              w.lifecycle_state = 'active'
              w.risk_tier       = 'low'
              w.team            = 'extensions'
              w.consent_tier    = 'supervised'
              w.entra_app_id    = worker_id
              w.owner_msid      = 'system'
            end
            worker.update(updated_at: Time.now) if worker.updated_at
          end
        rescue StandardError => e
          Legion::Logging.debug "Extensions#load_extension failed to register digital worker for #{ext_name}: #{e.message}" if defined?(Legion::Logging)
          nil
        end
        true
      rescue StandardError => e
        Legion::Logging.log_exception(e, lex: entry[:gem_name], component_type: :boot)
        false
      end

      def hook_all_actors
        return if @pending_actors.nil? || @pending_actors.empty?

        Legion::Logging.info "Hooking #{@pending_actors.size} deferred actors"

        groups = group_pending_actors

        %i[once poll every loop].each do |type|
          next if groups[type].empty?

          Legion::Logging.info "Starting #{type} actors (#{groups[type].size})"
          groups[type].each { |actor| hook_actor(**actor) }
        end
        unless groups[:subscription].empty?
          Legion::Logging.info "Starting subscription actors (#{groups[:subscription].size})"
          hook_subscription_actors_pooled(groups[:subscription])
        end
        dispatch_local_actors(@local_tasks) unless @local_tasks.empty?

        @pending_actors.clear
        Legion::Logging.info(
          "Actors hooked: subscription:#{@subscription_tasks.count}," \
          "every:#{@timer_tasks.count}," \
          "poll:#{@poll_tasks.count}," \
          "once:#{@once_tasks.count}," \
          "loop:#{@loop_tasks.count}," \
          "local:#{@local_tasks.count}"
        )
        @loaded_extensions&.each { |name| Catalog.transition(name, :running) }
        Catalog.flush_persisted_transitions
      end

      ACTOR_TYPE_MAP = {
        Once:         :once,
        Poll:         :poll,
        Every:        :every,
        Loop:         :loop,
        Subscription: :subscription
      }.freeze

      def group_pending_actors
        groups = { once: [], poll: [], every: [], loop: [], subscription: [] }
        @pending_actors.each do |actor|
          type = resolve_actor_type(actor[:actor_class])
          groups[type] << actor
        end
        groups
      end

      def resolve_actor_type(actor_class)
        anc = actor_class.ancestors
        ACTOR_TYPE_MAP.each do |const, type|
          return type if anc.include?(Legion::Extensions::Actors.const_get(const))
        end
        Legion::Logging.warn "Unknown actor type for #{actor_class}, defaulting to loop"
        :loop
      end

      def hook_actor(extension:, extension_name:, actor_class:, size: 1, **opts)
        size = if Legion::Settings[:extensions].key?(extension_name.to_sym) && Legion::Settings[:extensions][extension_name.to_sym].key?(:workers)
                 Legion::Settings[:extensions][extension_name.to_sym][:workers]
               elsif size.is_a? Integer
                 size
               else
                 1
               end

        extension_hash = {
          extension:       extension,
          extension_name:  extension_name,
          actor_class:     actor_class,
          size:            size,
          fallback_policy: :abort,
          **opts
        }
        extension_hash[:running_class] = if actor_class.ancestors.include? Legion::Extensions::Actors::Subscription
                                           actor_class
                                         else
                                           actor_class.new
                                         end

        return if extension_hash[:running_class].respond_to?(:enabled?) && !extension_hash[:running_class].enabled?

        if actor_class.ancestors.include? Legion::Extensions::Actors::Every
          @timer_tasks.push(extension_hash)
          @running_instances << extension_hash[:running_class]
        elsif actor_class.ancestors.include? Legion::Extensions::Actors::Once
          @once_tasks.push(extension_hash)
          @running_instances << extension_hash[:running_class]
        elsif actor_class.ancestors.include? Legion::Extensions::Actors::Loop
          @loop_tasks.push(extension_hash)
          @running_instances << extension_hash[:running_class]
        elsif actor_class.ancestors.include? Legion::Extensions::Actors::Poll
          @poll_tasks.push(extension_hash)
          @running_instances << extension_hash[:running_class]
        elsif actor_class.ancestors.include? Legion::Extensions::Actors::Subscription
          hook_subscription_actors_pooled([extension_hash])
        else
          Legion::Logging.fatal "#{actor_class} did not match any actor classes (ancestors: #{actor_class.ancestors.first(5).map(&:to_s)})"
        end
      end

      def register_in_registry(gem_name:, version: nil, description: nil)
        return unless defined?(Legion::Registry)
        return if Legion::Registry.lookup(gem_name)

        capabilities = read_gemspec_capabilities(gem_name)
        entry = Legion::Registry::Entry.new(
          name:         gem_name,
          version:      version,
          description:  description,
          capabilities: capabilities,
          airb_status:  'pending',
          risk_tier:    'low'
        )
        Legion::Registry.register(entry)
        register_sandbox_policy(gem_name: gem_name, capabilities: capabilities)
      end

      def register_sandbox_policy(gem_name:, capabilities: [])
        return unless defined?(Legion::Sandbox)

        Legion::Sandbox.register_policy(gem_name, capabilities: capabilities)
      end

      private

      def write_lex_cli_manifest(entry, extension)
        require 'legion/cli/lex_cli_manifest'

        gem_name = entry[:gem_name]
        gem_version = extension.const_defined?(:VERSION) ? extension::VERSION : '0.0.0'

        manifest = Legion::CLI::LexCliManifest.new
        return unless manifest.stale?(gem_name, gem_version)

        alias_name = gem_name.delete_prefix('lex-')
        commands = build_manifest_commands(extension)
        manifest.write_manifest(gem_name: gem_name, gem_version: gem_version,
                                alias_name: alias_name, commands: commands)
      rescue StandardError => e
        Legion::Logging.debug "LexCliManifest write failed for #{gem_name}: #{e.message}" if defined?(Legion::Logging)
      end

      def build_manifest_commands(extension)
        return {} unless extension.respond_to?(:runners)

        extension.runners.each_with_object({}) do |(runner_name, meta), cmds|
          runner_mod = meta[:runner_module]
          next unless runner_mod

          methods = (meta[:class_methods] || {}).each_with_object({}) do |(fn_name, fn_meta), meths|
            next if fn_name.to_s.start_with?('_')

            args = (fn_meta[:args] || []).map { |type, name| "#{name}:#{type}" }
            meths[fn_name.to_s] = { desc: fn_name.to_s.tr('_', ' '), args: args }
          end
          next if methods.empty?

          cmds[runner_name.to_s] = { class_name: runner_mod.to_s, methods: methods }
        end
      end

      def read_gemspec_capabilities(gem_name)
        spec = Gem::Specification.find_by_name(gem_name)
        raw  = spec.metadata['legion.capabilities']
        return [] unless raw

        raw.split(',').map(&:strip)
      rescue Gem::MissingSpecError => e
        Legion::Logging.debug "Extensions#read_gemspec_capabilities could not find spec for #{gem_name}: #{e.message}" if defined?(Legion::Logging)
        []
      end

      def hook_subscription_actors_pooled(sub_actors)
        max_channels = Legion::Settings.dig(:transport, :subscription_pool_size) || 16
        prepared = []

        # Phase 1: Prepare all consumers (parallel, shared pool)
        pool_size = [sub_actors.size, max_channels].min
        @subscription_pool = Concurrent::FixedThreadPool.new(pool_size)

        sub_actors.each do |actor_hash|
          actor_class = actor_hash[:actor_class]
          ext_name = actor_hash[:extension_name]
          size = resolve_subscription_worker_count(actor_hash)

          unless resolve_remote_invocable(ext_name, actor_hash)
            @local_tasks.push(actor_hash)
            next
          end

          size.times do
            entry = { actor_hash: actor_hash, instance: nil }
            prepared << entry
            @subscription_pool.post do
              instance = actor_class.new
              instance.prepare if instance.respond_to?(:prepare)
              entry[:instance] = instance
            rescue StandardError => e
              Legion::Logging.error "Subscription prepare failed for #{ext_name}: #{e.message}" if defined?(Legion::Logging)
            end
          end

          actor_hash[:running_class] = actor_class
          @subscription_tasks.push(actor_hash)
        end

        @subscription_pool.shutdown
        @subscription_pool.wait_for_termination(30)

        # Phase 2: Activate sequentially (one basic.consume at a time)
        prepared.each do |entry|
          next unless entry[:instance]

          begin
            entry[:instance].activate if entry[:instance].respond_to?(:activate)
            @running_instances << entry[:instance]
          rescue StandardError => e
            ext_name = entry[:actor_hash][:extension_name]
            Legion::Logging.error "[Subscription] activate failed for #{ext_name}: #{e.message}" if defined?(Legion::Logging)
          end
        end
      end

      def resolve_subscription_worker_count(actor_hash)
        ext_name = actor_hash[:extension_name]
        ext_settings = Legion::Settings.dig(:extensions, ext_name.to_sym)
        if ext_settings.is_a?(Hash) && ext_settings.key?(:workers)
          ext_settings[:workers]
        elsif actor_hash[:size].is_a?(Integer)
          actor_hash[:size]
        else
          1
        end
      end

      def resolve_remote_invocable(extension_name, opts = {})
        ext_key = extension_name.to_sym
        ext_settings = Legion::Settings.dig(:extensions, ext_key)
        runner_name = opts[:actor_name]&.to_sym

        # 1. Per-runner settings override
        runner_setting = ext_settings&.dig(:runners, runner_name, :remote_invocable)
        return runner_setting unless runner_setting.nil?

        # 2. Extension settings override
        ext_setting = ext_settings&.dig(:remote_invocable)
        return ext_setting unless ext_setting.nil?

        # 3. Runner class method (only if defined directly on the runner, not inherited)
        runner_class = opts[:runner_class]
        if runner_class.respond_to?(:remote_invocable?)
          owner = runner_class.method(:remote_invocable?).owner
          return runner_class.remote_invocable? if owner == runner_class.singleton_class || !owner.singleton_class?
        end

        # 4. Extension module method
        extension = opts[:extension]
        return extension.remote_invocable? if extension.respond_to?(:remote_invocable?)

        # 5. Default
        true
      end

      def dispatch_local_actors(actors)
        require 'legion/dispatch'

        actors.each do |actor_hash|
          ext_name = actor_hash[:extension_name]

          runner_mod = actor_hash[:runner_class]
          unless runner_mod
            actor_str = actor_hash[:actor_class].to_s
            runner_str = actor_str.sub('::Actor::', '::Runners::')
            runner_mod = begin
              Kernel.const_get(runner_str)
            rescue NameError
              Legion::Logging.warn "[LocalDispatch] runner not found for #{ext_name}: #{runner_str}" if defined?(Legion::Logging)
              next
            end
          end

          actor_hash[:runner_module] = runner_mod
          actor_hash[:running_class] = actor_hash[:actor_class]
          @running_instances&.push(actor_hash[:actor_class])

          Legion::Logging.info "[LocalDispatch] registered: #{ext_name}/#{actor_hash[:actor_name]}" if defined?(Legion::Logging)
        end
      end

      public

      def loaded_extension_modules
        constants(false).filter_map do |const_name|
          mod = const_get(const_name, false)
          next nil unless mod.is_a?(Module) && mod.respond_to?(:runner_modules)

          mod
        rescue StandardError => e
          Legion::Logging.warn("[Extensions] loaded_extension_modules: #{e.message}") if defined?(Legion::Logging)
          nil
        end
      end

      def unregister_capabilities(gem_name)
        Extensions::Catalog::Registry.unregister_extension(gem_name)
      end

      def register_absorber_capabilities(gem_name, absorbers)
        absorbers.each_value do |absorber_meta|
          cap = Extensions::Capability.from_absorber(
            extension:   gem_name,
            absorber:    absorber_meta[:absorber_module],
            patterns:    absorber_meta[:patterns],
            description: absorber_meta[:description]
          )
          Extensions::Catalog::Registry.register(cap)
        rescue StandardError => e
          if defined?(Legion::Logging)
            Legion::Logging.warn(
              "Absorber catalog registration error for #{gem_name} " \
              "(#{absorber_meta[:absorber_module]}): #{e.message}"
            )
          end
        end
      end

      def register_capabilities(gem_name, runners)
        runners.each_value do |runner_meta|
          runner_name = runner_meta[:runner_name]
          (runner_meta[:class_methods] || {}).each do |fn_name, fn_meta|
            next if fn_name.to_s.start_with?('_')

            params = {}
            (fn_meta[:args] || []).each do |arg|
              type, name = arg
              params[name] = { type: :string, required: type == :keyreq }
            end

            cap = Extensions::Capability.from_runner(
              extension:  gem_name,
              runner:     runner_name.to_s.split('_').map(&:capitalize).join,
              function:   fn_name.to_s,
              parameters: params,
              tags:       [gem_name.delete_prefix('lex-')]
            )
            Extensions::Catalog::Registry.register(cap)
          end
        rescue StandardError => e
          Legion::Logging.warn("Catalog registration error for #{gem_name}: #{e.message}") if defined?(Legion::Logging)
        end
      end

      def gem_load(entry)
        gem_name     = entry[:gem_name]
        require_path = entry[:require_path]
        gem_dir      = Gem::Specification.find_by_name(gem_name).gem_dir
        require "#{gem_dir}/lib/#{require_path}"
        true
      rescue Gem::MissingSpecError => e
        Legion::Logging.warn "#{gem_name} gem not found: #{e.message}"
        nil
      rescue LoadError => e
        Legion::Logging.warn "#{gem_name} failed to load: #{e.message}"
        nil
      end

      def ensure_namespace(const_path)
        parts   = const_path.split('::')
        current = ::Legion::Extensions
        parts[2...-1].each do |part|
          current.const_set(part, Module.new) unless current.const_defined?(part, false)
          current = current.const_get(part, false)
        end
      end

      def gem_names_for_discovery
        if defined?(Bundler)
          Bundler.load.specs.map { |s| { name: s.name, version: s.version.to_s } }
        else
          Gem::Specification.latest_specs.map { |s| { name: s.name, version: s.version.to_s } }
        end
      end

      def apply_role_filter
        role = Legion::Settings[:role]
        return if role.nil? || role[:profile].nil?

        profile = role[:profile].to_sym
        allowed = allowed_gem_names_for_profile(profile, role)
        return if allowed.nil?

        before = @extensions.count
        @extensions.select! { |entry| allowed.include?(entry[:gem_name]) }
        Legion::Logging.info "Role profile :#{profile} filtered #{before} -> #{@extensions.count} extensions"
      end

      def core_extension_names
        %w[codegen conditioner exec health lex llm-gateway log metering node ping scheduler tasker task_pruner telemetry
           transformer].freeze
      end

      def ai_extension_names
        %w[claude gemini openai].freeze
      end

      def service_extension_names
        %w[consul github http microsoft_teams nomad redis s3 tfe vault].freeze
      end

      def other_extension_names
        %w[chef elastic_app_search elasticsearch influxdb memcached pagerduty pushbullet pushover slack sleepiq smtp
           sonos ssh todoist twilio].freeze
      end

      def dev_agentic_names
        %w[attention coldstart curiosity dream empathy flow habit memory metacognition mood narrator personality
           reflection salience temporal tick volition].freeze
      end

      def agentic_extension_names
        known_gem_names = (core_extension_names + service_extension_names + other_extension_names + ai_extension_names).map { |n| "lex-#{n}" }
        Array(@extensions).reject { |entry| known_gem_names.include?(entry[:gem_name]) }.map { |entry| entry[:gem_name] }
      end

      def categorize_and_order(gem_names)
        ext_settings = ::Legion::Settings[:extensions] || {}
        categories   = ext_settings[:categories] || default_category_registry
        lists        = {
          core: Array(ext_settings[:core]),
          ai:   Array(ext_settings[:ai]),
          gaia: Array(ext_settings[:gaia])
        }
        ctx = {
          blocked:     Array(ext_settings[:blocked]),
          agentic_cfg: ext_settings[:agentic] || {},
          categories:  categories,
          gem_set:     gem_names.to_set,
          ordered:     [],
          claimed:     Set.new
        }

        collect_list_category_gems(lists, ctx)
        collect_prefix_category_gems(gem_names, ctx)

        (gem_names.to_a - ctx[:claimed].to_a - ctx[:blocked]).sort.each do |gn|
          ctx[:ordered] << build_extension_entry(gn, :default, categories, nesting: false)
        end

        ctx[:ordered]
      end

      def check_reserved_words(gem_name, known_org: true)
        return if known_org

        bare          = gem_name.delete_prefix('lex-')
        first_segment = bare.split('-').first

        configured_prefixes = begin
          Array(::Legion::Settings.dig(:extensions, :reserved_prefixes))
        rescue StandardError => e
          Legion::Logging.debug "Extensions#check_reserved_words failed to read reserved_prefixes: #{e.message}" if defined?(Legion::Logging)
          []
        end
        reserved_prefixes = configured_prefixes.empty? ? %w[core ai agentic gaia] : configured_prefixes

        configured_words = begin
          Array(::Legion::Settings.dig(:extensions, :reserved_words))
        rescue StandardError => e
          Legion::Logging.debug "Extensions#check_reserved_words failed to read reserved_words: #{e.message}" if defined?(Legion::Logging)
          []
        end
        reserved_words = configured_words.empty? ? %w[transport cache crypt data settings json logging llm rbac legion] : configured_words

        if reserved_prefixes.include?(first_segment)
          ::Legion::Logging.warn(
            "#{gem_name} uses reserved prefix '#{first_segment}' — " \
            "it will be loaded in the #{first_segment} category namespace"
          )
        elsif reserved_words.include?(first_segment)
          ::Legion::Logging.warn(
            "#{gem_name} uses reserved word '#{first_segment}' as its first segment — " \
            'this may shadow framework modules'
          )
        end
      end

      def find_extensions
        return @extensions if @extensions

        all_specs  = gem_names_for_discovery
        lex_names  = all_specs.select { |s| s[:name].start_with?('lex-') }.map { |s| s[:name] }
        @extensions = categorize_and_order(lex_names)
        apply_role_filter
        @extensions
      end

      def load_yaml_agents
        @load_yaml_agents ||= begin
          require 'legion/settings/agent_loader'
          dir = default_agents_directory
          definitions = Legion::Settings::AgentLoader.load_agents(dir)
          definitions.each { |d| d[:_runner_module] = generate_yaml_runner(d) }
          definitions
        rescue LoadError => e
          Legion::Logging.debug "Extensions#load_yaml_agents failed to load agent loader: #{e.message}" if defined?(Legion::Logging)
          []
        end
      end

      private

      def default_agents_directory
        custom = Legion::Settings.dig(:agents, :directory)
        return custom if custom && Dir.exist?(custom)

        default = File.expand_path('~/.legionio/agents')
        Dir.exist?(default) ? default : nil
      rescue StandardError => e
        Legion::Logging.debug "Extensions#default_agents_directory failed: #{e.message}" if defined?(Legion::Logging)
        nil
      end

      def generate_yaml_runner(definition)
        mod = Module.new
        definition[:runner][:functions].each do |func|
          method_name = func[:name].to_sym
          case func[:type]
          when 'llm'
            prompt_template = func[:prompt]
            model = func[:model]
            mod.define_method(method_name) do |**kwargs|
              prompt = prompt_template.gsub(/\{\{(\w+(?:\.\w+)*)\}\}/) do
                keys = Regexp.last_match(1).split('.').map(&:to_sym)
                kwargs.dig(*keys).to_s
              end
              if defined?(Legion::LLM)
                Legion::LLM.chat(messages: [{ role: 'user', content: prompt }], model: model,
                                 caller: { source: 'extension', command: 'llm_runner' })
              else
                { success: false, reason: :llm_unavailable }
              end
            end
          when 'script'
            command = func[:command]
            mod.define_method(method_name) do |**kwargs|
              require 'open3'
              input = defined?(Legion::JSON) ? Legion::JSON.dump(kwargs) : ::JSON.dump(kwargs)
              stdout, stderr, status = Open3.capture3(command, stdin_data: input)
              { success: status.success?, stdout: stdout, stderr: stderr, exit_code: status.exitstatus }
            end
          when 'http'
            url = func[:url]
            mod.define_method(method_name) do |**kwargs|
              require 'net/http'
              uri = URI(url)
              body = defined?(Legion::JSON) ? Legion::JSON.dump(kwargs) : ::JSON.dump(kwargs)
              response = Net::HTTP.post(uri, body, 'Content-Type' => 'application/json')
              { success: response.is_a?(Net::HTTPSuccess), status: response.code.to_i, body: response.body }
            end
          end
        end
        mod
      end

      public

      def lex_prefix(names)
        names.map { |n| n.start_with?('lex-') ? n : "lex-#{n}" }
      end

      def allowed_gem_names_for_profile(profile, role)
        case profile
        when :core      then lex_prefix(core_extension_names)
        when :cognitive then lex_prefix(core_extension_names + agentic_extension_names)
        when :service   then lex_prefix(core_extension_names + service_extension_names + other_extension_names)
        when :dev       then lex_prefix(core_extension_names + ai_extension_names + dev_agentic_names)
        when :custom    then lex_prefix(Array(role[:extensions]).map(&:to_s))
        end
      end

      def collect_list_category_gems(lists, ctx)
        lists.sort_by { |cat, _| ctx[:categories].dig(cat, :tier) || 99 }.each do |cat_name, gem_list|
          gem_list.each do |gn|
            next unless ctx[:gem_set].include?(gn)
            next if ctx[:blocked].include?(gn)

            ctx[:ordered] << build_extension_entry(gn, cat_name, ctx[:categories], nesting: false)
            ctx[:claimed].add(gn)
          end
        end
      end

      def collect_prefix_category_gems(gem_names, ctx)
        prefix_cats = ctx[:categories].select { |_, v| v[:type].to_s == 'prefix' }
                                      .sort_by { |_, v| v[:tier] || 99 }
                                      .to_h
        prefix_cats.each_key do |cat_name|
          prefix  = "lex-#{cat_name}-"
          matched = gem_names.select { |gn| gn.start_with?(prefix) && !ctx[:claimed].include?(gn) }.sort
          matched.each do |gn|
            next if ctx[:blocked].include?(gn)
            next if cat_name == :agentic && agentic_blocked?(gn, ctx[:agentic_cfg])
            next if cat_name == :agentic && !agentic_allowed?(gn, ctx[:agentic_cfg])

            ctx[:ordered] << build_extension_entry(gn, cat_name, ctx[:categories], nesting: true)
            ctx[:claimed].add(gn)
          end
        end
      end

      def build_extension_entry(gem_name, category, categories, nesting:)
        segments = Helpers::Segments.derive_segments(gem_name)
        tier     = category == :default ? 5 : (categories.dig(category, :tier) || 5)

        # Multi-segment gem names: check if the gem actually uses nested directories
        # (e.g. lex-agentic-memory -> agentic/memory/) or flat underscored naming
        # (e.g. lex-swarm-github -> swarm_github.rb). Probe the gem's lib/ to decide.
        nesting = true if segments.length > 1
        nesting = probe_nesting(gem_name, segments) if nesting && segments.length > 1

        if nesting
          const_path   = Helpers::Segments.derive_const_path(gem_name)
          require_path = Helpers::Segments.derive_require_path(gem_name)
        else
          flat_name    = gem_name.delete_prefix('lex-').tr('-', '_')
          const_path   = "Legion::Extensions::#{flat_name.split('_').map(&:capitalize).join}"
          require_path = "legion/extensions/#{flat_name}"
        end

        { gem_name: gem_name, category: category, tier: tier,
          segments: segments, const_path: const_path, require_path: require_path }
      end

      def probe_nesting(gem_name, segments)
        gem_dir = Gem::Specification.find_by_name(gem_name).gem_dir
        nested_path = "#{gem_dir}/lib/legion/extensions/#{segments.join('/')}.rb"
        return true if File.exist?(nested_path)

        flat_path = "#{gem_dir}/lib/legion/extensions/#{segments.join('_')}.rb"
        return false if File.exist?(flat_path)

        true # default to nested if neither found
      rescue Gem::MissingSpecError
        true
      end

      def default_category_registry
        {
          core:    { type: :list, tier: 1 },
          ai:      { type: :list, tier: 2 },
          gaia:    { type: :list, tier: 3 },
          agentic: { type: :prefix, tier: 4 }
        }
      end

      def agentic_blocked?(gem_name, config)
        Array(config[:blocked]).any? { |pat| File.fnmatch(pat, gem_name) }
      end

      def agentic_allowed?(gem_name, config)
        return true if config[:allowed].nil?

        Array(config[:allowed]).any? { |pat| File.fnmatch(pat, gem_name) }
      end
    end
  end
end
