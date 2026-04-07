# frozen_string_literal: true

require 'thor'

module Legion
  module CLI
    class Marketplace < Thor
      def self.exit_on_failure?
        true
      end

      class_option :json,     type: :boolean, default: false, desc: 'Output as JSON'
      class_option :no_color, type: :boolean, default: false, desc: 'Disable color output'

      # ──────────────────────────────────────────────────────────
      # search
      # ──────────────────────────────────────────────────────────

      desc 'search QUERY', 'Search extension registry'
      def search(query)
        require 'legion/registry'
        out = formatter
        results = Legion::Registry.search(query)

        if results.empty?
          out.warn("No extensions found matching '#{query}'")
          return
        end

        if options[:json]
          out.json(results.map(&:to_h))
        else
          rows = results.map do |e|
            status_label = e.approved? ? 'approved' : (e.status || e.airb_status).to_s
            [e.name, e.version.to_s, status_label, (e.description || '')[0..60]]
          end
          out.table(%w[Name Version Status Description], rows)
        end
      end

      # ──────────────────────────────────────────────────────────
      # info
      # ──────────────────────────────────────────────────────────

      desc 'info NAME', 'Show extension details'
      def info(name)
        require 'legion/registry'
        out = formatter
        entry = Legion::Registry.lookup(name)

        unless entry
          out.error("Extension '#{name}' not found")
          return
        end

        if options[:json]
          out.json(entry.to_h)
        else
          out.header("Extension: #{entry.name}")
          out.spacer
          out.detail(entry.to_h.compact)
        end
      end

      # ──────────────────────────────────────────────────────────
      # list
      # ──────────────────────────────────────────────────────────

      desc 'list', 'List all registered extensions'
      option :approved, type: :boolean, desc: 'Show only approved extensions'
      option :tier,     type: :string,  desc: 'Filter by risk tier'
      option :status,   type: :string,  desc: 'Filter by review status'
      def list
        require 'legion/registry'
        out = formatter
        extensions = build_extension_list

        if extensions.empty?
          out.warn('No extensions registered')
          return
        end

        if options[:json]
          out.json(extensions.map(&:to_h))
        else
          rows = extensions.map { |e| [e.name, e.version.to_s, e.status.to_s, e.risk_tier] }
          out.table(%w[Name Version Status Tier], rows)
          puts "  #{extensions.size} extension(s)"
        end
      end

      # ──────────────────────────────────────────────────────────
      # scan
      # ──────────────────────────────────────────────────────────

      desc 'scan NAME', 'Run security scan on extension'
      def scan(name)
        require 'legion/registry/security_scanner'
        out = formatter
        scanner = Legion::Registry::SecurityScanner.new
        result  = scanner.scan(name: name)

        if options[:json]
          out.json(result)
        else
          result[:checks].each do |check|
            color = check[:status] == :fail ? :critical : :nominal
            puts "  #{out.colorize(check[:check].to_s.ljust(25), color)} #{check[:status]} - #{check[:details]}"
          end
          if result[:passed]
            out.success('Scan PASSED')
          else
            out.error('Scan FAILED')
          end
        end
      end

      # ──────────────────────────────────────────────────────────
      # submit
      # ──────────────────────────────────────────────────────────

      desc 'submit NAME', 'Submit extension for review'
      def submit(name)
        require 'legion/registry'
        out = formatter

        Legion::Registry.submit_for_review(name)

        if options[:json]
          out.json(success: true, name: name, status: 'pending_review')
        else
          out.success("'#{name}' submitted for review")
        end
      rescue ArgumentError => e
        out.error(e.message)
      end

      # ──────────────────────────────────────────────────────────
      # review
      # ──────────────────────────────────────────────────────────

      desc 'review', 'List extensions pending review'
      def review
        require 'legion/registry'
        out = formatter
        pending = Legion::Registry.pending_reviews

        if pending.empty?
          out.warn('No extensions pending review')
          return
        end

        if options[:json]
          out.json(pending.map(&:to_h))
        else
          rows = pending.map { |e| [e.name, e.version.to_s, e.author.to_s, e.submitted_at.to_s] }
          out.table(%w[Name Version Author Submitted], rows)
          puts "  #{pending.size} pending review(s)"
        end
      end

      # ──────────────────────────────────────────────────────────
      # approve
      # ──────────────────────────────────────────────────────────

      desc 'approve NAME', 'Approve an extension'
      option :notes, type: :string, desc: 'Reviewer notes'
      def approve(name)
        require 'legion/registry'
        out = formatter

        Legion::Registry.approve(name, notes: options[:notes])

        if options[:json]
          out.json(success: true, name: name, status: 'approved')
        else
          out.success("'#{name}' approved")
          out.detail({ 'Notes' => options[:notes] }) if options[:notes]
        end
      rescue ArgumentError => e
        out.error(e.message)
      end

      # ──────────────────────────────────────────────────────────
      # reject
      # ──────────────────────────────────────────────────────────

      desc 'reject NAME', 'Reject an extension'
      option :reason, type: :string, desc: 'Rejection reason'
      def reject(name)
        require 'legion/registry'
        out = formatter

        Legion::Registry.reject(name, reason: options[:reason])

        if options[:json]
          out.json(success: true, name: name, status: 'rejected')
        else
          out.success("'#{name}' rejected")
          out.detail({ 'Reason' => options[:reason] }) if options[:reason]
        end
      rescue ArgumentError => e
        out.error(e.message)
      end

      # ──────────────────────────────────────────────────────────
      # deprecate
      # ──────────────────────────────────────────────────────────

      desc 'deprecate NAME', 'Mark an extension as deprecated'
      option :successor,   type: :string, desc: 'Replacement extension name'
      option :sunset_date, type: :string, desc: 'Sunset date (YYYY-MM-DD)'
      def deprecate(name)
        require 'legion/registry'
        out = formatter

        sunset = parse_sunset_date(options[:sunset_date])
        Legion::Registry.deprecate(name, successor: options[:successor], sunset_date: sunset)

        if options[:json]
          out.json(success: true, name: name, status: 'deprecated',
                   successor: options[:successor], sunset_date: options[:sunset_date])
        else
          out.success("'#{name}' marked as deprecated")
          detail_hash = {}
          detail_hash['Successor']   = options[:successor]   if options[:successor]
          detail_hash['Sunset Date'] = options[:sunset_date] if options[:sunset_date]
          out.detail(detail_hash) unless detail_hash.empty?
        end
      rescue ArgumentError => e
        out.error(e.message)
      end

      # ──────────────────────────────────────────────────────────
      # install
      # ──────────────────────────────────────────────────────────

      desc 'install NAME', 'Install a lex extension gem'
      option :source, type: :string, desc: 'Gem source URL (overrides configured sources)'
      def install(name)
        require 'legion/registry'
        require 'legion/extensions/gem_source'
        out = formatter

        unless name.start_with?('lex-')
          out.error("Extension name must start with 'lex-'")
          return
        end

        begin
          Connection.ensure_settings(resolve_secrets: false)
          Legion::Extensions::GemSource.setup!
        rescue StandardError => e
          Legion::Logging.debug("marketplace install: settings not available: #{e.message}") if defined?(Legion::Logging)
        end

        result = if options[:source]
                   Legion::Extensions::GemSource.install_gem(name, source_override: options[:source])
                 else
                   Legion::Extensions::GemSource.install_gem(name)
                 end

        if result[:success]
          entry = Legion::Registry::Entry.new(name: name, status: :active, airb_status: 'pending')
          Legion::Registry.register(entry)
          out.success("'#{name}' installed successfully")
        else
          out.error("Failed to install '#{name}'")
          puts result[:output] if result[:output]
        end
      end

      # ──────────────────────────────────────────────────────────
      # publish
      # ──────────────────────────────────────────────────────────

      desc 'publish', 'Publish current extension to rubygems'
      def publish
        require 'legion/registry'
        require 'legion/registry/security_scanner'
        out = formatter

        gemspec_files = Dir.glob('*.gemspec')
        if gemspec_files.empty?
          out.error('No gemspec found — publish aborted')
          return
        end

        gemspec_path = gemspec_files.first
        gem_name = File.basename(gemspec_path, '.gemspec')

        unless Kernel.system('bundle', 'exec', 'rspec')
          out.error('Specs failed — publish aborted')
          return
        end

        unless Kernel.system('bundle', 'exec', 'rubocop')
          out.error('Rubocop failed — publish aborted')
          return
        end

        unless Kernel.system('gem', 'build', gemspec_path)
          out.error("Failed to build gem '#{gem_name}'")
          return
        end

        gem_files = Dir.glob("#{gem_name}-*.gem")
        if gem_files.empty?
          out.error('No built gem file found after build')
          return
        end

        gem_file = gem_files.max_by { |f| File.mtime(f) }

        unless Kernel.system('gem', 'push', gem_file)
          out.error("Failed to push '#{gem_file}'")
          return
        end

        scanner = Legion::Registry::SecurityScanner.new
        scan_result = scanner.scan(name: gem_file)

        version = gem_file.sub("#{gem_name}-", '').sub('.gem', '')
        entry = Legion::Registry::Entry.new(name: gem_name, version: version,
                                            status: :active, airb_status: 'pending')
        Legion::Registry.register(entry)

        out.success("'#{gem_name}' v#{version} published — security: #{scan_result[:passed] ? 'passed' : 'failed'}")
      end

      # ──────────────────────────────────────────────────────────
      # stats
      # ──────────────────────────────────────────────────────────

      desc 'stats NAME', 'Show usage statistics for an extension'
      def stats(name)
        require 'legion/registry'
        out = formatter
        data = Legion::Registry.usage_stats(name)

        unless data
          out.error("Extension '#{name}' not found")
          return
        end

        if options[:json]
          out.json(data)
        else
          out.header("Usage Stats: #{name}")
          out.spacer
          out.detail({
                       'Install Count'    => data[:install_count].to_s,
                       'Active Instances' => data[:active_instances].to_s,
                       'Downloads (7d)'   => data[:downloads_7d].to_s,
                       'Downloads (30d)'  => data[:downloads_30d].to_s,
                       'Last Updated'     => data[:last_updated].to_s
                     })
        end
      end

      no_commands do
        def formatter
          @formatter ||= Output::Formatter.new(
            json:  options[:json],
            color: !options[:no_color]
          )
        end

        def build_extension_list
          if options[:approved]
            Legion::Registry.approved
          elsif options[:tier]
            Legion::Registry.by_risk_tier(options[:tier])
          elsif options[:status]
            Legion::Registry.all.select { |e| e.status.to_s == options[:status] }
          else
            Legion::Registry.all
          end
        end

        def parse_sunset_date(date_str)
          return nil if date_str.nil? || date_str.empty?

          Date.parse(date_str)
        rescue ArgumentError => e
          Legion::Logging.debug("MarketplaceCommand#parse_sunset_date failed to parse '#{date_str}': #{e.message}") if defined?(Legion::Logging)
          nil
        end
      end
    end
  end
end
