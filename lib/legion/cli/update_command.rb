# frozen_string_literal: true

require 'English'
require 'thor'
require 'rbconfig'
require 'concurrent'
require 'net/http'
require 'json'
require 'rubygems/uninstaller'

module Legion
  module CLI
    class Update < Thor
      namespace 'update'

      def self.exit_on_failure?
        true
      end

      class_option :json, type: :boolean, default: false, desc: 'Output as JSON'
      class_option :no_color, type: :boolean, default: false, desc: 'Disable color output'

      desc 'gems', 'Update Legion gems to latest versions (default)'
      default_task :gems
      option :dry_run, type: :boolean, default: false, desc: 'Show what would be updated without installing'
      option :cleanup, type: :boolean, default: false, desc: 'Remove old gem versions after update'
      def gems
        out = formatter
        gem_bin = File.join(RbConfig::CONFIG['bindir'], 'gem')

        unless File.executable?(gem_bin)
          out.error("Gem binary not found at #{gem_bin}")
          raise SystemExit, 1
        end

        target_gems = discover_legion_gems
        out.header('Checking for updates') unless options[:json]

        before = snapshot_versions(target_gems)
        results = update_gems(target_gems, gem_bin, dry_run: options[:dry_run])
        Gem::Specification.reset unless options[:dry_run]
        after = options[:dry_run] ? before : snapshot_versions(target_gems)

        if options[:json]
          out.json(gems: results, dry_run: options[:dry_run])
        else
          display_results(out, results, before, after)
        end

        cleanup_old_gems(out, target_gems) if options[:cleanup] && !options[:dry_run]
      end

      no_commands do
        def formatter
          @formatter ||= Output::Formatter.new(
            json:  options[:json],
            color: !options[:no_color]
          )
        end

        private

        def discover_legion_gems
          gems = ['legionio']
          Gem::Specification.each do |spec|
            gems << spec.name if spec.name.start_with?('legion-') || spec.name.start_with?('lex-')
          end
          gems.uniq.sort
        end

        def snapshot_versions(gem_names)
          gem_names.each_with_object({}) do |name, hash|
            specs = Gem::Specification.find_all_by_name(name)
            hash[name] = if specs.empty?
                           nil
                         else
                           specs.map(&:version).max.to_s
                         end
          end
        end

        def update_gems(gem_names, gem_bin, dry_run: false)
          local_versions = snapshot_versions(gem_names)
          remote_versions = fetch_remote_versions_parallel(gem_names)

          outdated = gem_names.select do |name|
            remote = remote_versions[name]
            local = local_versions[name]
            remote && local && Gem::Version.new(remote) > Gem::Version.new(local)
          end

          return dry_run_results(gem_names, local_versions, remote_versions, outdated) if dry_run

          return current_results(gem_names, remote_versions) if outdated.empty?

          install_results(gem_names, gem_bin, remote_versions, outdated)
        end

        def dry_run_results(gem_names, local_versions, remote_versions, outdated)
          gem_names.map do |name|
            remote = remote_versions[name]
            status = if outdated.include?(name) then 'available'
                     elsif remote then 'current'
                     else 'check_failed'
                     end
            { name: name, from: local_versions[name], to: remote, status: status }
          end
        end

        def current_results(gem_names, remote_versions)
          gem_names.map do |name|
            { name: name, status: remote_versions[name] ? 'current' : 'check_failed', remote: remote_versions[name] }
          end
        end

        def install_results(gem_names, gem_bin, remote_versions, outdated)
          output = `#{gem_bin} install #{outdated.join(' ')} --no-document 2>&1`
          success = $CHILD_STATUS.success?
          gem_names.map do |name|
            if outdated.include?(name)
              { name: name, status: success ? 'installed' : 'failed', remote: remote_versions[name], output: output.strip }
            else
              { name: name, status: remote_versions[name] ? 'current' : 'check_failed', remote: remote_versions[name] }
            end
          end
        end

        def fetch_remote_versions_parallel(gem_names)
          results = Concurrent::Hash.new
          pool = Concurrent::FixedThreadPool.new([gem_names.size, 24].min)
          latch = Concurrent::CountDownLatch.new(gem_names.size)

          gem_names.each do |name|
            pool.post do
              version = fetch_remote_version(name)
              results[name] = version if version
            rescue StandardError => e
              Legion::Logging.debug("UpdateCommand#fetch_remote_version #{name}: #{e.message}") if defined?(Legion::Logging)
            ensure
              latch.count_down
            end
          end

          latch.wait(30)
          pool.shutdown
          results
        end

        def fetch_remote_version(name)
          uri = URI("https://rubygems.org/api/v1/versions/#{name}/latest.json")
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = true
          http.open_timeout = 5
          http.read_timeout = 10
          response = http.request(Net::HTTP::Get.new(uri))
          return nil unless response.is_a?(Net::HTTPSuccess)

          data = ::JSON.parse(response.body)
          data['version']
        end

        def display_results(out, results, before, after)
          updated = []
          failed = []
          check_failures = 0

          results.each do |r|
            name = r[:name]
            case r[:status]
            when 'available'
              puts "  #{name}: #{r[:from]} -> #{r[:to]}"
              updated << name
            when 'current'
              local = r[:from] || before[name]
              puts "  #{name}: #{local || '?'} (already latest)"
            when 'check_failed'
              puts "  #{name}: #{before[name]} (remote check failed)"
              check_failures += 1
            when 'installed'
              old_v = before[name]
              new_v = after[name]
              if old_v == new_v
                out.error("  #{name}: #{old_v} (install may have failed)")
                failed << name
              else
                out.success("  #{name}: #{old_v} -> #{new_v}")
                updated << name
              end
            when 'failed'
              out.error("  #{name}: update failed")
              failed << name
            end
          end

          out.spacer
          if updated.any?
            out.success("Updated #{updated.size} gem(s)")
          elsif check_failures.positive?
            puts "#{check_failures} gem(s) could not be checked - retry or use --dry-run for details"
          else
            puts 'All gems are up to date'
          end
          out.error("#{failed.size} gem(s) failed to update") if failed.any?

          suggest_detect(out)
        end

        def cleanup_old_gems(out, gem_names)
          Gem::Specification.reset
          cleaned = 0

          gem_names.each do |name|
            specs = Gem::Specification.find_all_by_name(name).sort_by(&:version)
            next if specs.size <= 1

            latest = specs.pop
            specs.each do |old_spec|
              Gem::Uninstaller.new(
                old_spec.name,
                version:            old_spec.version,
                ignore:             true,
                executables:        false,
                force:              true,
                abort_on_dependent: false
              ).uninstall
              out.success("  Cleaned #{old_spec.name}-#{old_spec.version} (keeping #{latest.version})")
              cleaned += 1
            rescue StandardError => e
              out.error("  Failed to clean #{old_spec.name}-#{old_spec.version}: #{e.message}")
            end
          end

          out.spacer
          if cleaned.positive?
            out.success("Cleaned #{cleaned} old gem version(s)")
          else
            puts 'No old gem versions to clean'
          end
        end

        def suggest_detect(out)
          require 'legion/extensions/detect'
          missing = Legion::Extensions::Detect.missing
          return if missing.empty?

          out.spacer
          puts "  #{missing.size} new extension(s) recommended based on your environment:"
          missing.each { |name| puts "    gem install #{name}" }
          puts "  Run 'legionio detect --install' to install them"
        rescue LoadError => e
          Legion::Logging.debug("UpdateCommand#suggest_detect lex-detect not available: #{e.message}") if defined?(Legion::Logging)
          nil
        end
      end
    end
  end
end
