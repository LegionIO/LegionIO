# frozen_string_literal: true

module Legion
  module Extensions
    module Builder
      module Base
        def find_files(name, path = extension_path)
          files = []
          return files unless Dir.exist? "#{path}/#{name}"

          Dir["#{path}/#{name}/*.rb"].each do |file|
            files.push(file)
          end
          files
        end

        def require_files(files)
          files.each { |file| require file }
        end

        def const_defined_two?(item, root = Kernel)
          root.const_defined?(item.to_s)
        end

        def define_constant_two(item, root: Kernel, type: Module)
          return true if root.const_defined?(item)

          root.const_set(item.to_s, type.new)
        end

        def define_get(item, root: Kernel, type: Module)
          define_constant_two(item, root: root, type: type) if const_defined_two?(item, root: root)
          root.const_get(item)
        end
      end
    end
  end
end
