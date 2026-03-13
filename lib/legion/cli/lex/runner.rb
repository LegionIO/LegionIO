# frozen_string_literal: true

module Legion
  class Cli
    module Lex
      class Runner < Thor
        include Thor::Actions

        def self.source_root
          File.dirname(__FILE__)
        end

        no_commands do
          def lex
            Dir.pwd.split('/').last.split('-').last
          end
        end

        desc 'delete :runner', 'deletes a runner'
        def delete(name)
          remove_file("lib/legion/extensions/#{lex}/runners/#{name}.rb")
          remove_file("spec/runners/#{name}_spec.rb")
        end

        desc 'create name type', 'creates a new runner'
        def create(name)
          template('templates/runner.erb', "lib/legion/extensions/#{lex}/runners/#{name}.rb", { name: name, lex: lex })
          template('templates/runner_spec.erb', "spec/runners/#{name}_spec.rb", { name: name, lex: lex })
        end

        desc 'add_function new_function_name *args', 'adds new function to runner, args optional'
        def add_function(name, function, args = nil)
          @arg_keys = []

          if args.nil?
            args = '**'
          else
            option_args = ''
            required_args = ''
            args.split(',').each do |arg|
              key, value = arg.split('=')
              @arg_keys.push key.to_s
              if value.nil? || value.empty?
                required_args.concat("#{key}:, ")
              else
                option_args.concat("#{key}: '#{value}', ")
              end
            end
            args = required_args.concat(option_args, '**')
          end
          insert_into_file "lib/legion/extensions/#{lex}/runners/#{name}.rb",
                           after: "extend Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined? 'Helpers::Lex'\n" do
            "
          def #{function}(#{args})
            { success: true }
          end\n"
          end

          insert_into_file("spec/runners/#{name}_spec.rb", after: "it { should be_a Module }\n") do
            result = "  it { is_expected.to respond_to(:#{function}).with_any_keywords }\n"
            result.concat "  it { is_expected.to respond_to(:#{function}).with_keywords(:#{@arg_keys.join(', :')}) }\n" if @arg_keys.any?
            result
          end

          insert_into_file("spec/runners/#{name}_spec.rb", before: "  end\n") do
            "    it('#{function} returns a success') { expect(test_class.#{function}[:success]).to eq true }\n"
          end
        end
      end
    end
  end
end
