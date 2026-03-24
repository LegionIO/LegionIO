# frozen_string_literal: true

module Legion
  module Audit
    module ColdStorage
      class BackendNotAvailableError < StandardError; end

      module_function

      def backend
        raw = Legion::Settings[:audit]&.dig(:retention, :cold_backend) || 'local'
        raw.to_sym
      end

      def upload(data:, path:)
        case backend
        when :local then local_upload(data: data, path: path)
        when :s3    then s3_upload(data: data, path: path)
        else raise BackendNotAvailableError, "unknown cold_backend: #{backend}"
        end
      end

      def download(path:)
        case backend
        when :local then local_download(path: path)
        when :s3    then s3_download(path: path)
        else raise BackendNotAvailableError, "unknown cold_backend: #{backend}"
        end
      end

      def local_upload(data:, path:)
        ::FileUtils.mkdir_p(::File.dirname(path))
        ::File.binwrite(path, data)
        { path: path, bytes: data.bytesize }
      end

      def local_download(path:)
        ::File.binread(path)
      end

      def s3_client
        raise BackendNotAvailableError, 'aws-sdk-s3 gem is required for :s3 cold_backend' \
          unless defined?(Aws::S3::Client)

        @s3_client ||= Aws::S3::Client.new
      end

      def s3_bucket
        Legion::Settings[:audit]&.dig(:retention, :s3_bucket) ||
          raise(BackendNotAvailableError, 'audit.retention.s3_bucket must be set for :s3 backend')
      end

      def s3_upload(data:, path:)
        s3_client.put_object(bucket: s3_bucket, key: path, body: data,
                             content_type: 'application/gzip',
                             server_side_encryption: 'AES256')
        { path: path, bytes: data.bytesize }
      end

      def s3_download(path:)
        resp = s3_client.get_object(bucket: s3_bucket, key: path)
        resp.body.read
      end
    end
  end
end
