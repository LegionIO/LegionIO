# frozen_string_literal: true

require 'json'
require 'fileutils'

module Legion
  module CLI
    class LexCliManifest
      attr_reader :cache_dir

      def initialize(cache_dir: File.expand_path('~/.legionio/cache/cli'))
        @cache_dir = cache_dir
        FileUtils.mkdir_p(@cache_dir)
      end

      def write_manifest(gem_name:, gem_version:, alias_name:, commands:)
        data = { 'gem' => gem_name, 'version' => gem_version, 'alias' => alias_name,
                 'commands' => serialize_commands(commands) }
        File.write(manifest_path(gem_name), ::JSON.pretty_generate(data))
      end

      def read_manifest(gem_name)
        path = manifest_path(gem_name)
        return nil unless File.exist?(path)

        ::JSON.parse(File.read(path))
      end

      def resolve_alias(name)
        all_manifests.each do |m|
          return m['gem'] if m['alias'] == name
        end
        nil
      end

      def all_manifests
        Dir.glob(File.join(@cache_dir, 'lex-*.json')).map do |path|
          ::JSON.parse(File.read(path))
        rescue StandardError
          nil
        end.compact
      end

      def stale?(gem_name, current_version)
        m = read_manifest(gem_name)
        return true unless m

        m['version'] != current_version
      end

      private

      def manifest_path(gem_name)
        File.join(@cache_dir, "#{gem_name}.json")
      end

      def serialize_commands(commands)
        commands.transform_values do |cmd|
          {
            'class'   => cmd[:class_name],
            'methods' => cmd[:methods].transform_values { |m| { 'desc' => m[:desc], 'args' => m[:args] } }
          }
        end
      end
    end
  end
end
