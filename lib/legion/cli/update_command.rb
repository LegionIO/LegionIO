# frozen_string_literal: true

require 'English'
require 'thor'
require 'rbconfig'
require 'rubygems/uninstaller'
require 'legion/extensions/gem_source'

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

        Connection.ensure_settings
        Legion::Extensions::GemSource.setup!

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
          outdated_map = fetch_outdated(gem_bin, gem_names)

          results = gem_names.map do |name|
            info = outdated_map[name]
            if info
              { name: name, from: local_versions[name], to: info[:remote], status: dry_run ? 'available' : 'pending' }
            else
              { name: name, from: local_versions[name], status: 'current' }
            end
          end

          return results if dry_run

          pending = results.select { |r| r[:status] == 'pending' }
          return results.each { |r| r[:status] = 'current' if r[:status] == 'pending' } if pending.empty?

          install_outdated(gem_bin, pending, results)
        end

        def fetch_outdated(gem_bin, gem_names)
          output = `#{gem_bin} outdated 2>&1`
          return {} unless $CHILD_STATUS.success?

          parse_outdated(output, gem_names)
        end

        def parse_outdated(output, gem_names)
          allowed = gem_names.to_set
          output.each_line.with_object({}) do |line, map|
            match = line.match(/^(\S+) \((\S+) < (\S+)\)/)
            next unless match && allowed.include?(match[1])

            map[match[1]] = { local: match[2], remote: match[3] }
          end
        end

        def install_outdated(gem_bin, pending, results)
          names = pending.map { |r| r[:name] }
          source_args = Legion::Extensions::GemSource.source_args_for_cli
          `#{gem_bin} install #{names.join(' ')} --no-document #{source_args} 2>&1`
          success = $CHILD_STATUS.success?
          pending_set = names.to_set
          results.each do |r|
            r[:status] = if pending_set.include?(r[:name])
                           success ? 'installed' : 'failed'
                         else
                           'current'
                         end
          end
          results
        end

        def display_results(out, results, before, after)
          updated = []
          failed = []

          results.each do |r|
            name = r[:name]
            case r[:status]
            when 'available'
              puts "  #{name}: #{r[:from]} -> #{r[:to]}"
              updated << name
            when 'current'
              puts "  #{name}: #{r[:from] || before[name] || '?'} (already latest)"
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
