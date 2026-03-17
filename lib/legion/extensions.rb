# frozen_string_literal: true

require 'legion/extensions/core'
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
        @actors = []

        find_extensions
        load_extensions
      end

      def shutdown
        return nil if @loaded_extensions.nil?

        @subscription_tasks.each do |task|
          task[:threadpool].shutdown
          task[:threadpool].kill unless task[:threadpool].wait_for_termination(5)
        end

        @loop_tasks.each { |task| task[:running_class].cancel if task[:running_class].respond_to?(:cancel) }
        @once_tasks.each { |task| task[:running_class].cancel if task[:running_class].respond_to?(:cancel) }
        @timer_tasks.each { |task| task[:running_class].cancel if task[:running_class].respond_to?(:cancel) }
        @poll_tasks.each { |task| task[:running_class].cancel if task[:running_class].respond_to?(:cancel) }

        Legion::Logging.info 'Successfully shut down all actors'
      end

      def load_extensions
        @extensions ||= {}
        @loaded_extensions ||= []
        @extensions.each do |extension, values|
          if values.key(:enabled) && !values[:enabled]
            Legion::Logging.info "Skipping #{extension} because it's disabled"
            next
          end

          if Legion::Settings[:extensions].key?(extension.to_sym) && Legion::Settings[:extensions][extension.to_sym].key?(:enabled) && !Legion::Settings[:extensions][extension.to_sym][:enabled] # rubocop:disable Layout/LineLength
            next
          end

          unless load_extension(extension, values)
            Legion::Logging.warn("#{extension} failed to load")
            next
          end
          @loaded_extensions.push(extension)
        end
        Legion::Logging.info(
          "#{@extensions.count} extensions loaded with " \
          "subscription:#{@subscription_tasks.count}," \
          "every:#{@timer_tasks.count}," \
          "poll:#{@poll_tasks.count}," \
          "once:#{@once_tasks.count}," \
          "loop:#{@loop_tasks.count}"
        )
      end

      def load_extension(extension, values) # rubocop:disable Metrics/PerceivedComplexity, Metrics/CyclomaticComplexity, Metrics/AbcSize, Metrics/MethodLength
        return unless gem_load(values[:gem_name], extension)

        extension = Kernel.const_get(values[:extension_class])
        extension.extend Legion::Extensions::Core unless extension.singleton_class.include?(Legion::Extensions::Core)

        ext_settings = Legion::Settings[:extensions][values[:extension_name]]
        min_version = ext_settings[:min_version] if ext_settings.is_a?(Hash)
        Legion::Logging.fatal values if min_version.is_a?(String) && Gem::Version.new(values[:version]) >= Gem::Version.new(min_version)

        if extension.data_required? && Legion::Settings[:data][:connected] == false
          Legion::Logging.warn "#{values[:extension_name]} requires Legion::Data but isn't enabled, skipping"
          return false
        end

        if extension.cache_required? && Legion::Settings[:cache][:connected] == false
          Legion::Logging.warn "#{values[:extension_name]} requires Legion::Cache but isn't enabled, skipping"
          return false
        end

        if extension.crypt_required? && Legion::Settings[:crypt][:cs].nil?
          Legion::Logging.warn "#{values[:extension_name]} requires Legion::Crypt but isn't ready, skipping"
          return false
        end

        if extension.vault_required? && Legion::Settings[:crypt][:vault][:connected] == false
          Legion::Logging.warn "#{values[:extension_name]} requires Legion::Crypt::Vault but isn't enabled, skipping"
          return false
        end

        if extension.llm_required? && (!Legion::Settings.key?(:llm) || Legion::Settings[:llm][:connected] == false)
          Legion::Logging.warn "#{values[:extension_name]} requires Legion::LLM but isn't enabled, skipping"
          return false
        end

        has_logger = extension.respond_to?(:log)
        extension.autobuild

        require 'legion/transport/messages/lex_register'
        Legion::Transport::Messages::LexRegister.new(function: 'save', opts: extension.runners).publish

        if extension.respond_to?(:meta_actors) && extension.meta_actors.is_a?(Hash)
          extension.meta_actors.each_value do |actor|
            extension.log.debug("hooking meta actor: #{actor}") if has_logger
            hook_actor(**actor)
          end
        end

        extension.actors.each_value do |actor|
          extension.log.debug("hooking literal actor: #{actor}") if has_logger
          hook_actor(**actor)
        end
        extension.log.info "Loaded v#{extension::VERSION}"
        Legion::Events.emit('extension.loaded', name: values[:extension_name], version: values[:version])

        begin
          if defined?(Legion::Data) && defined?(Legion::Data::Model::DigitalWorker)
            worker_id = "lex-#{values[:extension_name]}"
            worker = Legion::Data::Model::DigitalWorker.find_or_create(worker_id: worker_id) do |w|
              w.name            = values[:extension_name]
              w.extension_name  = values[:extension_name]
              w.lifecycle_state = 'active'
              w.risk_tier       = 'low'
              w.team            = 'extensions'
              w.consent_tier    = 'supervised'
              w.entra_app_id    = worker_id
              w.owner_msid      = 'system'
            end
            worker.update(updated_at: Time.now) if worker.updated_at
          end
        rescue StandardError
          nil
        end
        true
      rescue StandardError => e
        Legion::Logging.error e.message
        Legion::Logging.error e.backtrace
        false
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
        elsif actor_class.ancestors.include? Legion::Extensions::Actors::Once
          @once_tasks.push(extension_hash)
        elsif actor_class.ancestors.include? Legion::Extensions::Actors::Loop
          @loop_tasks.push(extension_hash)
        elsif actor_class.ancestors.include? Legion::Extensions::Actors::Poll
          @poll_tasks.push(extension_hash)
        elsif actor_class.ancestors.include? Legion::Extensions::Actors::Subscription
          extension_hash[:threadpool] = Concurrent::FixedThreadPool.new(size)
          size.times do
            extension_hash[:threadpool].post do
              klass = actor_class.new
              if klass.respond_to?(:async)
                klass.async.subscribe
              else
                klass.subscribe
              end
            end
          end
          @subscription_tasks.push(extension_hash)
        else
          Legion::Logging.fatal 'did not match any actor classes'
        end
      end

      def gem_load(gem_name, name)
        gem_dir = Gem::Specification.find_by_name(gem_name).gem_dir
        require "#{gem_dir}/lib/legion/extensions/#{name}"
        true
      rescue LoadError => e
        Legion::Logging.error e.message
        Legion::Logging.error e.backtrace
        Legion::Logging.error "gem_path: #{gem_dir}" if defined?(gem_dir) && gem_dir
        false
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
        allowed = case profile
                  when :core      then core_extension_names
                  when :cognitive then core_extension_names + agentic_extension_names
                  when :service   then core_extension_names + service_extension_names + other_extension_names
                  when :dev       then core_extension_names + ai_extension_names + dev_agentic_names
                  when :custom    then Array(role[:extensions]).map(&:to_s)
                  else return
                  end

        before = @extensions.count
        @extensions.select! { |name, _| allowed.include?(name) }
        Legion::Logging.info "Role profile :#{profile} filtered #{before} -> #{@extensions.count} extensions"
      end

      def core_extension_names
        %w[codegen conditioner exec health lex log metering node ping scheduler tasker task_pruner telemetry
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
        known = core_extension_names + service_extension_names + other_extension_names + ai_extension_names
        @extensions.keys.reject { |name| known.include?(name) }
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
        rescue StandardError
          []
        end
        reserved_prefixes = configured_prefixes.empty? ? %w[core ai agentic gaia] : configured_prefixes

        configured_words = begin
          Array(::Legion::Settings.dig(:extensions, :reserved_words))
        rescue StandardError
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
        @extensions ||= {}
        gem_names_for_discovery.each do |spec|
          next unless spec[:name].start_with?('lex-')

          ext_name = spec[:name].delete_prefix('lex-').tr('-', '_')
          @extensions[ext_name] = { full_gem_name:   "#{spec[:name]}-#{spec[:version]}",
                                    gem_name:        spec[:name],
                                    extension_name:  ext_name,
                                    version:         spec[:version],
                                    extension_class: "Legion::Extensions::#{ext_name.split('_').collect(&:capitalize).join}" }
        end

        apply_role_filter

        enabled = 0
        requested = 0

        Legion::Settings[:extensions].each do |extension, values|
          next if @extensions.key? extension.to_s
          next if values[:enabled] == false

          requested += 1
          next if values[:auto_install] == false
          next if ENV['_'].include? 'bundle'

          Legion::Logging.warn "#{extension} is missing, attempting to install automatically.."
          install = Gem.install("lex-#{extension}", values[:version])
          Legion::Logging.debug(install)
          lex = Gem::Specification.find_by_name("lex-#{extension}")

          @extensions[extension.to_s] = {
            full_gem_name:   "lex-#{extension}-#{lex.version}",
            gem_name:        "lex-#{extension}",
            extension_name:  extension.to_s,
            version:         lex.version,
            extension_class: "Legion::Extensions::#{extension.to_s.split('_').collect(&:capitalize).join}"
          }

          enabled += 1
        rescue StandardError, Gem::MissingSpecError => e
          Legion::Logging.error "Failed to auto install #{extension}, e: #{e.message}"
        end
        return true if requested == enabled

        Legion::Logging.warn "A total of #{requested - enabled} where skipped"
        if ENV.key?('_') && ENV['_'].include?('bundle')
          Legion::Logging.warn 'Please add them to your Gemfile since you are using bundler'
        else
          Legion::Logging.warn 'You must have auto_install_missing_lex set to true to auto install missing extensions'
        end
      end

      private

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
