# frozen_string_literal: true

module Legion
  class Cli
    module Lex
      class Message < Thor
        include Thor::Actions

        def self.source_root
          File.dirname(__FILE__)
        end

        no_commands do
          def lex
            Dir.pwd.split('/').last.split('-').last
          end
        end

        desc 'create :name', 'creates a new message'
        def create(name)
          template('templates/message.erb', "lib/legion/extensions/#{lex}/transport/messages/#{name}.rb", { name: name, lex: lex })
          template('templates/message_spec.erb', "spec/messages/#{name}_spec.rb", { name: name, lex: lex })
        end

        desc 'delete :name', 'deletes a message class'
        def delete(name)
          remove_file("lib/legion/extensions/#{lex}/transport/messages/#{name}.rb")
          remove_file("spec/messages/#{name}_spec.rb")
          remove_file("spec/transport/messages/#{name}_spec.rb")
        end
      end
    end
  end
end
