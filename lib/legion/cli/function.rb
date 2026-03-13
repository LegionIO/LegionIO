# frozen_string_literal: true

module Legion
  class Cli
    class Function < Thor
      desc 'find', 'find'
      option :internal, type: :boolean, default: false
      def find
        Legion::Service.new(cache: false, crypt: false, extensions: false, log_level: 'error')
        response = ask 'trigger extension?', limited_to: Legion::Data::Model::Extension.map(:name)
        trigger_extension = Legion::Data::Model::Extension.where(name: response).first
        runners = Legion::Data::Model::Runner.where(extension_id: trigger_extension.values[:id])
        if runners.one?
          trigger_runner = runners.first
          say "Auto selecting #{trigger_runner.values[:name]} since it is the only option"
        else
          response = ask 'trigger runner?', limited_to: runners.map(:name)
          trigger_runner = Legion::Data::Model::Runner.where(name: response).where(extension_id: trigger_extension.values[:id]).first
        end

        functions = Legion::Data::Model::Function.where(runner_id: trigger_runner.values[:id])

        if functions.one?
          trigger_function = functions.first
          say "Auto selecting #{trigger_function.values[:name]} since it is the only option"
        else
          response = ask 'trigger function?', limited_to: Legion::Data::Model::Function.where(runner_id: trigger_runner.values[:id]).map(:name)
          trigger_function = trigger_runner.functions(name: response).first
        end
        # say "#{trigger_runner.values[:namespace]}.#{trigger_function.values[:name]} selected as trigger", :green, :italicized
        # mute { trigger_function.values[:id] }
        say trigger_function.values[:id]
        # puts self.methods(false)
      end

      desc 'delete', 'delete'
      def delete; end

      desc 'activate', 'activate'
      def activate; end
    end
  end
end
