# frozen_string_literal: true

require 'open3'

module Legion
  module CLI
    class Doctor
      class BundleCheck
        def name
          'Bundle status'
        end

        def run
          gemfile = find_gemfile
          return Result.new(name: name, status: :skip, message: 'No Gemfile found') unless gemfile

          stdout, stderr, status = Open3.capture3('bundle check')
          if status.success?
            Result.new(name: name, status: :pass, message: 'All gems installed')
          else
            detail = (stdout + stderr).strip
            Result.new(
              name:         name,
              status:       :fail,
              message:      "Gems missing or outdated: #{detail.lines.first&.strip}",
              prescription: 'Run `bundle install`',
              auto_fixable: true
            )
          end
        rescue Errno::ENOENT
          Result.new(
            name:         name,
            status:       :fail,
            message:      'bundler not found',
            prescription: 'Install bundler: `gem install bundler`'
          )
        end

        def fix
          system('bundle install')
        end

        private

        def find_gemfile
          %w[Gemfile].map { |f| File.expand_path(f) }.find { |f| File.exist?(f) }
        end
      end
    end
  end
end
