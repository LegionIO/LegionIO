# frozen_string_literal: true

require 'legion/extensions/data/migrator'
require 'legion/extensions/data/model'

module Legion
  module Extensions
    module Data
      include Legion::Extensions::Helpers::Data
      include Legion::Extensions::Helpers::Logger

      def build
        @models = []
        @migrations = []
        if Dir[File.expand_path("#{data_path}/migrations/*.rb")].any?
          log.debug('Has migrations, checking status')
          run
        end

        models = Dir[File.expand_path("#{data_path}/models/*.rb")]
        if models.any?
          log.debug('Including LEX models')
          models.each do |file|
            require file
          end

          models_class.constants.select do |model|
            models_class.const_get(model).extend Legion::Extensions::Data::Model
          end
        end

        true
      end

      def extension_model
        Legion::Data::Model::Extension[namespace: lex_class.to_s]
      end

      def schema_version
        extension_model.values[:schema_version]
      end

      def migrations_path
        "#{data_path}/migrations/"
      end

      def migrate_class
        @migrate_class ||= Legion::Extensions::Data::Migrator.new(migrations_path, lex_class.to_s, lex_name)
      end

      def run
        return true if migrate_class.is_current?

        log.debug('Running LEX schema migrator')
        results = migrate_class.run
        extension_model.update(schema_version: results)
      end
    end
  end
end
