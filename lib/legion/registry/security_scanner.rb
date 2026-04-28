# frozen_string_literal: true

require 'digest'

module Legion
  module Registry
    class SecurityScanner
      CHECKS = %i[checksum naming_convention gemspec_metadata static_analysis].freeze

      DANGEROUS_PATTERNS = [
        { pattern: /\bKernel\.eval\b|\beval\s*\(/, label: 'eval' },
        { pattern: /\bKernel\.system\b|\bsystem\s*\(/, label: 'system' },
        { pattern: /\bKernel\.exec\b|\bexec\s*\(/, label: 'exec' },
        { pattern: /\bIO\.popen\b/, label: 'IO.popen' },
        { pattern: /\bOpen3\b/, label: 'Open3' },
        { pattern: /`[^`]+`/, label: 'backtick subshell' }
      ].freeze

      def scan(gem_path: nil, name: nil, gemspec: nil, source_path: nil)
        results = CHECKS.map do |check|
          send(check, gem_path: gem_path, name: name, gemspec: gemspec, source_path: source_path)
        end
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

        if name.match?(/\Alex-[a-z][a-z0-9_]*(?:-[a-z][a-z0-9_]*)*\z/)
          { check: :naming_convention, status: :pass, details: name }
        else
          { check: :naming_convention, status: :fail,
            details: "#{name} does not match lex-[a-z][a-z0-9_]*(?:-[a-z][a-z0-9_]*)*" }
        end
      end

      def gemspec_metadata(gemspec:, **_)
        return { check: :gemspec_metadata, status: :skip, details: 'no gemspec' } unless gemspec

        has_caps = gemspec.metadata&.key?('legion.capabilities')
        status = has_caps ? :pass : :warn
        { check: :gemspec_metadata, status: status,
          details: has_caps ? 'capabilities declared' : 'no capabilities declared' }
      end

      def static_analysis(source_path:, **_)
        return { check: :static_analysis, status: :skip, details: 'no source path' } unless source_path && Dir.exist?(source_path.to_s)

        findings = []
        Dir.glob(File.join(source_path, '**', '*.rb')).each do |file|
          relative = file.delete_prefix("#{source_path}/")
          File.foreach(file).with_index(1) do |line, lineno|
            DANGEROUS_PATTERNS.each do |entry|
              findings << "#{relative}:#{lineno} #{entry[:label]}" if line.match?(entry[:pattern])
            end
          end
        end

        if findings.empty?
          { check: :static_analysis, status: :pass, details: 'no dangerous patterns found' }
        else
          { check: :static_analysis, status: :warn, details: findings.join('; ') }
        end
      end
    end
  end
end
