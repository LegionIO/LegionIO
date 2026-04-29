# frozen_string_literal: true

module Legion
  module Extensions
    module Helpers
      module Segments
        module_function

        COMPOUND_SUFFIXES = {
          %w[llm azure foundry] => %w[llm azure_foundry]
        }.freeze

        def derive_segments(gem_name)
          segments = gem_name.delete_prefix('lex-').split('-')
          COMPOUND_SUFFIXES.fetch(segments, segments)
        end

        def derive_namespace(gem_name)
          derive_segments(gem_name).map { |s| s.split('_').map(&:capitalize).join }
        end

        def derive_const_path(gem_name)
          "Legion::Extensions::#{derive_namespace(gem_name).join('::')}"
        end

        def derive_require_path(gem_name)
          "legion/extensions/#{derive_segments(gem_name).join('/')}"
        end

        def segments_to_log_tag(segments)
          segments.map { |s| "[#{s}]" }.join
        end

        def segments_to_amqp_prefix(segments)
          "lex.#{segments.join('.')}"
        end

        def segments_to_settings_path(segments)
          segments.map(&:to_sym)
        end

        def segments_to_table_prefix(segments)
          segments.join('_')
        end

        def categorize_gem(gem_name, categories:, lists:)
          # Check defined lists first (list membership takes priority)
          lists.each do |cat_name, gem_list|
            next unless categories.key?(cat_name)

            return { category: cat_name, tier: categories[cat_name][:tier] } if gem_list.include?(gem_name)
          end

          # Check prefix-matched categories
          bare = gem_name.delete_prefix('lex-')
          categories.each do |cat_name, cat_config|
            next unless cat_config[:type] == :prefix

            return { category: cat_name, tier: cat_config[:tier] } if bare.start_with?("#{cat_name}-")
          end

          { category: :default, tier: 5 }
        end
      end
    end
  end
end
