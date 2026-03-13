# frozen_string_literal: true

module Legion
  class Cli
    module Lex
      class Queue < Thor
        include Thor::Actions

        def self.source_root
          File.dirname(__FILE__)
        end

        no_commands do
          def lex
            Dir.pwd.split('/').last.split('-').last
          end
        end

        desc 'create :name', 'creates a new queue'
        def create(name)
          template('templates/queue_helper.erb', 'spec/queue_helper.rb')
          template('templates/queue.erb',
                   "lib/legion/extensions/#{lex}/transport/queues/#{name}.rb",
                   { name: name, lex: lex })
          template('templates/queue_spec.erb', "spec/queues/#{name}_spec.rb", { name: name, lex: lex })
        end

        desc 'delete :name', 'deletes a queue config file'
        def delete(name)
          remove_file("lib/legion/extensions/#{lex}/transport/queues/#{name}.rb")
          remove_file("spec/queues/#{name}_spec.rb")
          remove_file("spec/transport/queues/#{name}_spec.rb")

          if Dir.exist? "#{Dir.pwd}/lib/legion/extensions/#{lex}/transport/queues/"
            remove_dir("#{Dir.pwd}/lib/legion/extensions/#{lex}/transport/queues") if Dir.empty?("#{Dir.pwd}/lib/legion/extensions/#{lex}/transport/queues/")
            remove_dir("#{Dir.pwd}/lib/legion/extensions/#{lex}/transport") if Dir.empty?("#{Dir.pwd}/lib/legion/extensions/#{lex}/transport")
          end

          remove_dir("#{Dir.pwd}/spec/queues") if Dir.exist?("#{Dir.pwd}/spec/queues") && Dir.empty?("#{Dir.pwd}/spec/queues")

          nil
        end
      end
    end
  end
end
