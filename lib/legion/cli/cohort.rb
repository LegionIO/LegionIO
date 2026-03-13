# frozen_string_literal: true

module Legion
  class Cli
    class Cohort < Thor
      desc 'import :id', 'imports a cohort for usage'
      def import(id)
        say "Importing Cohort #{id}", :green
      end
    end
  end
end
