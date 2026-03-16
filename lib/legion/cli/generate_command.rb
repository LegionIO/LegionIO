# frozen_string_literal: true

require 'fileutils'

module Legion
  module CLI
    class Generate < Thor
      ACTOR_PARENTS = {
        'subscription' => 'Legion::Extensions::Actors::Subscription',
        'every'        => 'Legion::Extensions::Actors::Every',
        'poll'         => 'Legion::Extensions::Actors::Poll',
        'once'         => 'Legion::Extensions::Actors::Once',
        'loop'         => 'Legion::Extensions::Actors::Loop'
      }.freeze

      def self.exit_on_failure?
        true
      end

      desc 'runner NAME', 'Add a runner to the current LEX'
      option :functions, type: :string, desc: 'Comma-separated function names to scaffold'
      def runner(name)
        out = formatter
        lex = detect_lex(out)

        runner_path = "lib/legion/extensions/#{lex}/runners/#{name}.rb"
        spec_path = "spec/runners/#{name}_spec.rb"

        ensure_dir(File.dirname(runner_path))
        ensure_dir(File.dirname(spec_path))

        class_name = name.split('_').map(&:capitalize).join
        lex_class = lex.split('_').map(&:capitalize).join

        functions = (options[:functions] || 'execute').split(',').map(&:strip)

        File.write(runner_path, runner_template(lex, lex_class, name, class_name, functions))
        File.write(spec_path, runner_spec_template(lex, lex_class, name, class_name, functions))

        out.success("Created #{runner_path}")
        out.success("Created #{spec_path}")

        return unless functions.any?

        out.spacer
        puts "  Functions scaffolded: #{functions.join(', ')}"
        puts "  Add actors with: legion generate actor #{name} --type subscription"
      end

      desc 'actor NAME', 'Add an actor to the current LEX'
      option :type, type: :string, default: 'subscription',
                    enum: %w[subscription every poll once loop],
                    desc: 'Actor execution type'
      option :runner, type: :string, desc: 'Associated runner name'
      option :interval, type: :numeric, default: 60, desc: 'Interval in seconds (for every/poll types)'
      def actor(name)
        out = formatter
        lex = detect_lex(out)

        actor_path = "lib/legion/extensions/#{lex}/actors/#{name}.rb"
        spec_path = "spec/actors/#{name}_spec.rb"

        ensure_dir(File.dirname(actor_path))
        ensure_dir(File.dirname(spec_path))

        class_name = name.split('_').map(&:capitalize).join
        lex_class = lex.split('_').map(&:capitalize).join
        actor_type = options[:type]
        runner_name = options[:runner] || name
        interval = options[:interval]

        actor_opts = { lex_class: lex_class, class_name: class_name, type: actor_type,
                       runner_name: runner_name, interval: interval }
        File.write(actor_path, actor_template(**actor_opts))
        File.write(spec_path, actor_spec_template(**actor_opts))

        out.success("Created #{actor_path}")
        out.success("Created #{spec_path}")
        puts "  Actor type: #{actor_type}"
      end

      desc 'exchange NAME', 'Add a transport exchange to the current LEX'
      def exchange(name)
        out = formatter
        lex = detect_lex(out)

        exchange_path = "lib/legion/extensions/#{lex}/transport/exchanges/#{name}.rb"
        ensure_dir(File.dirname(exchange_path))

        class_name = name.split('_').map(&:capitalize).join
        lex_class = lex.split('_').map(&:capitalize).join

        File.write(exchange_path, exchange_template(lex, lex_class, name, class_name))
        out.success("Created #{exchange_path}")
      end

      desc 'queue NAME', 'Add a transport queue to the current LEX'
      option :exchange, type: :string, desc: 'Exchange to bind to'
      def queue(name)
        out = formatter
        lex = detect_lex(out)

        queue_path = "lib/legion/extensions/#{lex}/transport/queues/#{name}.rb"
        ensure_dir(File.dirname(queue_path))

        class_name = name.split('_').map(&:capitalize).join
        lex_class = lex.split('_').map(&:capitalize).join

        File.write(queue_path, queue_template(lex, lex_class, name, class_name))
        out.success("Created #{queue_path}")
      end

      desc 'message NAME', 'Add a transport message to the current LEX'
      def message(name)
        out = formatter
        lex = detect_lex(out)

        message_path = "lib/legion/extensions/#{lex}/transport/messages/#{name}.rb"
        ensure_dir(File.dirname(message_path))

        class_name = name.split('_').map(&:capitalize).join
        lex_class = lex.split('_').map(&:capitalize).join

        File.write(message_path, message_template(lex, lex_class, name, class_name))
        out.success("Created #{message_path}")
      end

      desc 'tool NAME', 'Add a chat tool to the current LEX'
      def tool(name)
        out = formatter
        lex = detect_lex(out)

        tool_path = "lib/legion/extensions/#{lex}/tools/#{name}.rb"
        spec_path = "spec/tools/#{name}_spec.rb"

        ensure_dir(File.dirname(tool_path))
        ensure_dir(File.dirname(spec_path))

        class_name = name.split('_').map(&:capitalize).join
        lex_class = lex.split('_').map(&:capitalize).join

        File.write(tool_path, tool_template(lex, lex_class, name, class_name))
        File.write(spec_path, tool_spec_template(lex, lex_class, name, class_name))

        out.success("Created #{tool_path}")
        out.success("Created #{spec_path}")
      end

      no_commands do # rubocop:disable Metrics/BlockLength
        def formatter
          @formatter ||= Output::Formatter.new
        end

        def detect_lex(out)
          pwd = Dir.pwd
          dir_name = File.basename(pwd)
          unless dir_name.start_with?('lex-')
            out.error("Not inside a LEX directory (expected lex-* directory, got '#{dir_name}')")
            out.spacer
            puts '  Run this command from inside a LEX project directory:'
            puts '    cd lex-myextension'
            puts '    legion generate runner my_runner'
            raise SystemExit, 1
          end
          dir_name.sub('lex-', '')
        end

        def ensure_dir(path)
          FileUtils.mkdir_p(path)
        end

        # --- Templates ---

        def runner_template(_lex, lex_class, _name, class_name, functions)
          func_methods = functions.map do |func|
            <<~RUBY.gsub(/^/, '          ')
              def #{func}(**)
                { success: true }
              end
            RUBY
          end.join("\n")

          <<~RUBY
            # frozen_string_literal: true

            module Legion
              module Extensions
                module #{lex_class}
                  module Runners
                    module #{class_name}
                      extend Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined? 'Helpers::Lex'

            #{func_methods}
                    end
                  end
                end
              end
            end
          RUBY
        end

        def runner_spec_template(_lex, lex_class, _name, class_name, functions)
          func_specs = functions.map do |func|
            "  it { is_expected.to respond_to(:#{func}).with_any_keywords }"
          end.join("\n")

          <<~RUBY
            # frozen_string_literal: true

            RSpec.describe Legion::Extensions::#{lex_class}::Runners::#{class_name} do
              subject { described_class }

              it { should be_a Module }
            #{func_specs}
            end
          RUBY
        end

        def actor_template(lex_class:, class_name:, type:, runner_name:, interval:, **) # rubocop:disable Metrics/ParameterLists
          parent = ACTOR_PARENTS[type]
          interval_line = %w[every poll].include?(type) ? "\n        INTERVAL = #{interval}\n" : ''
          runner_class = runner_name.split('_').map(&:capitalize).join

          <<~RUBY
            # frozen_string_literal: true

            module Legion
              module Extensions
                module #{lex_class}
                  module Actors
                    class #{class_name} < #{parent}#{interval_line}
                      include Legion::Extensions::#{lex_class}::Runners::#{runner_class}
                    end
                  end
                end
              end
            end
          RUBY
        end

        def actor_spec_template(lex_class:, class_name:, type:, **)
          parent = ACTOR_PARENTS[type]

          <<~RUBY
            # frozen_string_literal: true

            RSpec.describe Legion::Extensions::#{lex_class}::Actors::#{class_name} do
              it { expect(described_class.ancestors).to include(#{parent}) }
            end
          RUBY
        end

        def exchange_template(_lex, lex_class, _name, class_name)
          <<~RUBY
            # frozen_string_literal: true

            module Legion
              module Extensions
                module #{lex_class}
                  module Transport
                    module Exchanges
                      class #{class_name} < Legion::Transport::Exchange
                      end
                    end
                  end
                end
              end
            end
          RUBY
        end

        def queue_template(_lex, lex_class, _name, class_name)
          <<~RUBY
            # frozen_string_literal: true

            module Legion
              module Extensions
                module #{lex_class}
                  module Transport
                    module Queues
                      class #{class_name} < Legion::Transport::Queue
                      end
                    end
                  end
                end
              end
            end
          RUBY
        end

        def message_template(_lex, lex_class, _name, class_name)
          <<~RUBY
            # frozen_string_literal: true

            module Legion
              module Extensions
                module #{lex_class}
                  module Transport
                    module Messages
                      class #{class_name} < Legion::Transport::Message
                      end
                    end
                  end
                end
              end
            end
          RUBY
        end

        def tool_template(lex, lex_class, _name, class_name)
          <<~RUBY
            # frozen_string_literal: true

            require 'ruby_llm'
            require 'legion/cli/chat/extension_tool'

            module Legion
              module Extensions
                module #{lex_class}
                  module Tools
                    class #{class_name} < RubyLLM::Tool
                      include Legion::CLI::Chat::ExtensionTool

                      description 'TODO: Describe what this tool does'
                      param :example, type: 'string', desc: 'TODO: Describe this parameter'

                      permission_tier :write

                      def execute(example:)
                        settings = Legion::Settings[:extensions][:#{lex}] || {}
                        client = Legion::Extensions::#{lex_class}::Client.new(**settings)
                        # TODO: implement
                        'Not yet implemented'
                      rescue StandardError => e
                        "Error: \#{e.message}"
                      end
                    end
                  end
                end
              end
            end
          RUBY
        end

        def tool_spec_template(_lex, lex_class, _name, class_name)
          <<~RUBY
            # frozen_string_literal: true

            RSpec.describe Legion::Extensions::#{lex_class}::Tools::#{class_name} do
              subject(:tool) { described_class.new }

              it 'has a description' do
                expect(described_class.description).not_to include('TODO')
              end

              it 'executes successfully' do
                result = tool.execute(example: 'test')
                expect(result).to be_a(String)
              end
            end
          RUBY
        end
      end
    end
  end
end
