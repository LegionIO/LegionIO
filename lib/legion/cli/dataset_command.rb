# frozen_string_literal: true

require 'thor'

module Legion
  module CLI
    class Dataset < Thor
      def self.exit_on_failure?
        true
      end

      class_option :json,       type: :boolean, default: false, desc: 'Output as JSON'
      class_option :no_color,   type: :boolean, default: false, desc: 'Disable color output'
      class_option :verbose,    type: :boolean, default: false, aliases: ['-V'], desc: 'Verbose logging'
      class_option :config_dir, type: :string,                  desc: 'Config directory path'

      desc 'list', 'List all datasets'
      def list
        out = formatter
        with_dataset_client do |client|
          datasets = client.list_datasets
          if options[:json]
            out.json(datasets)
          elsif datasets.empty?
            out.warn('No datasets found')
          else
            rows = datasets.map do |d|
              [d[:name].to_s, (d[:description] || '').to_s,
               (d[:latest_version] || '-').to_s, (d[:row_count] || 0).to_s]
            end
            out.table(%w[name description version row_count], rows)
          end
        end
      end
      default_task :list

      desc 'show NAME', 'Show dataset info and first 10 rows'
      option :version, type: :numeric, desc: 'Specific version number'
      def show(name)
        out = formatter
        with_dataset_client do |client|
          kwargs = { name: name }
          kwargs[:version] = options[:version] if options[:version]
          result = client.get_dataset(**kwargs)
          if result[:error]
            out.error("Dataset '#{name}': #{result[:error]}")
            raise SystemExit, 1
          end

          if options[:json]
            out.json(result)
          else
            out.header("Dataset: #{result[:name]}")
            out.spacer
            out.detail({ version: result[:version], row_count: result[:row_count] })
            out.spacer
            preview = (result[:rows] || []).first(10)
            if preview.empty?
              out.warn('No rows in this dataset version')
            else
              rows = preview.map do |r|
                [r[:row_index].to_s, r[:input].to_s.slice(0, 60), (r[:expected_output] || '').to_s.slice(0, 60)]
              end
              out.table(%w[index input expected_output], rows)
              remaining = result[:row_count].to_i - preview.size
              out.warn("... #{remaining} more rows not shown") if remaining.positive?
            end
          end
        end
      end

      desc 'import NAME PATH', 'Import a dataset from a file'
      option :format,      type: :string, default: 'json', enum: %w[json csv jsonl], desc: 'File format'
      option :description, type: :string, desc: 'Dataset description'
      def import(name, path)
        out = formatter
        with_dataset_client do |client|
          unless File.exist?(path)
            out.error("File not found: #{path}")
            raise SystemExit, 1
          end

          result = client.import_dataset(
            name:        name,
            path:        path,
            format:      options[:format],
            description: options[:description]
          )
          if options[:json]
            out.json(result)
          else
            out.success("Imported '#{result[:name]}' v#{result[:version]} (#{result[:row_count]} rows)")
          end
        end
      end

      desc 'export NAME PATH', 'Export a dataset to a file'
      option :format,  type: :string,  default: 'json', enum: %w[json csv jsonl], desc: 'File format'
      option :version, type: :numeric, desc: 'Version to export'
      def export(name, path)
        out = formatter
        with_dataset_client do |client|
          kwargs = { name: name, path: path, format: options[:format] }
          kwargs[:version] = options[:version] if options[:version]
          result = client.export_dataset(**kwargs)
          if options[:json]
            out.json(result)
          else
            out.success("Exported #{result[:row_count]} rows to #{result[:path]}")
          end
        end
      end

      no_commands do
        def formatter
          @formatter ||= Output::Formatter.new(
            json:  options[:json],
            color: !options[:no_color]
          )
        end

        def with_dataset_client
          Connection.config_dir = options[:config_dir] if options[:config_dir]
          Connection.log_level  = options[:verbose] ? 'debug' : 'error'
          Connection.ensure_data

          begin
            require 'legion/extensions/dataset'
            require 'legion/extensions/dataset/runners/dataset'
            require 'legion/extensions/dataset/client'
          rescue LoadError
            formatter.error('lex-dataset gem is not installed (gem install lex-dataset)')
            raise SystemExit, 1
          end

          db = Legion::Data.db
          client = Legion::Extensions::Dataset::Client.new(db: db)
          yield client
        rescue CLI::Error => e
          formatter.error(e.message)
          raise SystemExit, 1
        ensure
          Connection.shutdown
        end
      end
    end
  end
end
