# frozen_string_literal: true

module Legion
  class Cli
    module Lex
      class Actor < Thor
        include Thor::Actions

        def self.source_root
          File.dirname(__FILE__)
        end

        no_commands do
          def lex
            Dir.pwd.split('/').last.split('-').last
          end
        end

        desc 'create :name', 'creates a new actor'
        method_option :type, enum: %w[subscription every poll once loop], default: 'subscription'
        def create(name)
          template('templates/actor.erb', "#{lex}/lib/actors/#{name}.rb", { name: name, lex: lex, type: options[:type] })
        end

        desc 'delete :name', 'deletes an actor'
        def delete(name)
          remove_file("lib/legion/extensions/#{lex}/actors/#{name}.rb")
          remove_file("spec/actors/#{name}_spec.rb")
        end
      end
    end
  end
end
