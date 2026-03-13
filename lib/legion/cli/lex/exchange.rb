# frozen_string_literal: true

module Legion
  class Cli
    module Lex
      class Exchange < Thor
        include Thor::Actions

        def self.source_root
          File.dirname(__FILE__)
        end

        no_commands do
          def lex
            Dir.pwd.split('/').last.split('-').last
          end
        end

        desc 'create :name', 'creates a new exchange class'
        def create(name)
          template('templates/queue.erb', "lib/legion/extensions/#{lex}/transport/exchanges/#{name}.rb", { name: name, lex: lex })
          template('templates/queue_spec.erb', "spec/exchanges/#{name}_spec.rb", { name: name, lex: lex })
        end

        desc 'delete :name', 'deletes an exchange class'
        def delete(name)
          remove_file("lib/legion/extensions/#{lex}/transport/exchanges/#{name}.rb")
          remove_file("spec/exchanges/#{name}_spec.rb")
          remove_file("spec/transport/exchanges/#{name}_spec.rb")
        end
      end
    end
  end
end
