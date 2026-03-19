# frozen_string_literal: true

module Legion
  module Extensions
    module Permissions
      SANDBOX_BASE = File.expand_path('~/.legionio/data').freeze

      class << self
        def sandbox_path(lex_name)
          File.join(SANDBOX_BASE, lex_name)
        end

        def allowed?(lex_name, path, access_type)
          expanded = File.expand_path(path)
          return true if in_sandbox?(lex_name, expanded)
          return true if auto_approved?(lex_name, expanded)
          return true if explicitly_approved?(lex_name, expanded, access_type)

          false
        end

        def approve(lex_name, path, access_type)
          approvals[approval_key(lex_name, path, access_type)] = true
          persist_approval(lex_name, path, access_type, true)
        end

        def deny(lex_name, path, access_type)
          approvals[approval_key(lex_name, path, access_type)] = false
          persist_approval(lex_name, path, access_type, false)
        end

        def approved?(lex_name, path, access_type)
          approvals[approval_key(lex_name, path, access_type)] == true
        end

        def add_auto_approve(lex_name, globs)
          auto_approve_globs[lex_name] ||= []
          auto_approve_globs[lex_name].concat(Array(globs))
        end

        def declared_paths(lex_name)
          declarations[lex_name] || { read_paths: [], write_paths: [] }
        end

        def register_paths(lex_name, read_paths: [], write_paths: [])
          declarations[lex_name] = { read_paths: Array(read_paths), write_paths: Array(write_paths) }
        end

        def reset!
          @approvals = {}
          @auto_approve_globs = {}
          @declarations = {}
        end

        private

        def approvals
          @approvals ||= {}
        end

        def auto_approve_globs
          @auto_approve_globs ||= {}
        end

        def declarations
          @declarations ||= {}
        end

        def in_sandbox?(lex_name, expanded_path)
          expanded_path.start_with?(sandbox_path(lex_name))
        end

        def auto_approved?(lex_name, expanded_path)
          global_globs = load_global_auto_approve
          lex_globs = auto_approve_globs[lex_name] || load_lex_auto_approve(lex_name)
          (global_globs + (lex_globs || [])).any? do |glob|
            normalized = glob.end_with?('**') ? "#{glob}/*" : glob
            File.fnmatch(normalized, expanded_path, File::FNM_PATHNAME)
          end
        end

        def explicitly_approved?(lex_name, expanded_path, access_type)
          approvals.any? do |key, approved|
            next false unless approved

            k_lex, k_path, k_type = key.split('|', 3)
            k_lex == lex_name && k_type == access_type.to_s && expanded_path.start_with?(k_path)
          end
        end

        def approval_key(lex_name, path, access_type)
          "#{lex_name}|#{path}|#{access_type}"
        end

        def load_global_auto_approve
          return [] unless defined?(Legion::Settings)

          Legion::Settings.dig(:permissions, :auto_approve) || []
        rescue StandardError
          []
        end

        def load_lex_auto_approve(lex_name)
          return [] unless defined?(Legion::Settings)

          Legion::Settings.dig(lex_name.tr('-', '_').to_sym, :permissions, :auto_approve) || []
        rescue StandardError
          []
        end

        def persist_approval(lex_name, path, access_type, approved)
          return unless defined?(Legion::Data::Local) &&
                        Legion::Data::Local.respond_to?(:connected?) &&
                        Legion::Data::Local.connected?

          model = Legion::Data::Local.model(:extension_permissions)
          existing = model.where(lex_name: lex_name, path: path, access_type: access_type.to_s).first
          if existing
            existing.update(approved: approved, updated_at: Time.now)
          else
            model.insert(lex_name: lex_name, path: path, access_type: access_type.to_s,
                         approved: approved, created_at: Time.now, updated_at: Time.now)
          end
        rescue StandardError
          nil
        end
      end
    end
  end
end
