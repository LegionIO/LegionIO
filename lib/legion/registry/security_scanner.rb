# frozen_string_literal: true

require 'digest'

module Legion
  module Registry
    class SecurityScanner
      CHECKS = %i[checksum naming_convention gemspec_metadata].freeze

      def scan(gem_path: nil, name: nil, gemspec: nil)
        results = CHECKS.map { |check| send(check, gem_path: gem_path, name: name, gemspec: gemspec) }
        {
          passed:     results.all? { |r| r[:status] != :fail },
          checks:     results,
          scanned_at: Time.now
        }
      end

      private

      def checksum(gem_path:, **_)
        return { check: :checksum, status: :skip, details: 'no gem path' } unless gem_path && File.exist?(gem_path.to_s)

        hash = Digest::SHA256.file(gem_path).hexdigest
        { check: :checksum, status: :pass, details: hash }
      end

      def naming_convention(name:, **_)
        return { check: :naming_convention, status: :skip, details: 'no name' } unless name

        if name.match?(/\Alex-[a-z][a-z0-9_]*\z/)
          { check: :naming_convention, status: :pass, details: name }
        else
          { check: :naming_convention, status: :fail, details: "#{name} does not match lex-[a-z][a-z0-9_]*" }
        end
      end

      def gemspec_metadata(gemspec:, **_)
        return { check: :gemspec_metadata, status: :skip, details: 'no gemspec' } unless gemspec

        has_caps = gemspec.metadata&.key?('legion.capabilities')
        status = has_caps ? :pass : :warn
        { check: :gemspec_metadata, status: status,
          details: has_caps ? 'capabilities declared' : 'no capabilities declared' }
      end
    end
  end
end
