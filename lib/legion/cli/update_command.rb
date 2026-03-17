# frozen_string_literal: true

require 'English'
require 'thor'
require 'rbconfig'

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
        after = options[:dry_run] ? before : snapshot_versions(target_gems)

        if options[:json]
          out.json(gems: results, dry_run: options[:dry_run])
        else
          display_results(out, results, before, after)
        end
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
            spec = Gem::Specification.find_by_name(name)
            hash[name] = spec.version.to_s
          rescue Gem::MissingSpecError
            hash[name] = nil
          end
        end

        def update_gems(gem_names, gem_bin, dry_run: false)
          gem_names.map do |name|
            if dry_run
              remote = fetch_remote_version(name)
              local = begin
                Gem::Specification.find_by_name(name).version.to_s
              rescue Gem::MissingSpecError
                nil
              end
              { name: name, from: local, to: remote, status: remote && remote != local ? 'available' : 'current' }
            else
              output = `#{gem_bin} install #{name} --no-document 2>&1`
              success = $CHILD_STATUS.success?
              { name: name, status: success ? 'updated' : 'failed', output: output.strip }
            end
          end
        end

        def fetch_remote_version(name)
          output = `gem search ^#{name}$ --remote --no-verbose 2>/dev/null`.strip
          match = output.match(/#{Regexp.escape(name)}\s+\(([^)]+)\)/)
          match ? match[1] : nil
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
              puts "  #{name}: #{r[:from] || '?'} (current)"
            when 'updated'
              old_v = before[name]
              new_v = after[name]
              if old_v == new_v
                puts "  #{name}: #{old_v} (already latest)"
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
        end
      end
    end
  end
end
