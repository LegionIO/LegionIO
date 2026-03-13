# Settings Validation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add schema-based configuration validation to legion-settings that infers types from defaults, validates per-module on merge and cross-module on startup, and fails fast with all errors listed.

**Architecture:** A new `Schema` class in legion-settings infers type constraints from module defaults, stores optional overrides, and runs validation passes. `ValidationError` collects all errors before raising. No other gems need changes for the basic case.

**Tech Stack:** Ruby 3.4, RSpec, legion-settings, legion-json

**Working directory:** `/Users/miverso2/rubymine/legion/legion-settings`

**Design doc:** `/Users/miverso2/rubymine/legion/LegionIO/docs/plans/2026-03-13-settings-validation-design.md`

---

### Task 1: Create ValidationError Exception Class

**Files:**
- Create: `lib/legion/settings/validation_error.rb`
- Create: `spec/legion/settings/validation_error_spec.rb`

**Step 1: Create spec directory and write the failing test**

```bash
mkdir -p spec/legion/settings
```

Create `spec/spec_helper.rb`:
```ruby
# frozen_string_literal: true

require 'simplecov'
SimpleCov.start

require 'legion/settings'
```

Create `spec/legion/settings/validation_error_spec.rb`:
```ruby
# frozen_string_literal: true

require 'spec_helper'
require 'legion/settings/validation_error'

RSpec.describe Legion::Settings::ValidationError do
  it 'is a StandardError' do
    expect(described_class.new([])).to be_a(StandardError)
  end

  it 'formats a single error into the message' do
    errors = [{ module: :transport, path: 'connection.host', message: 'expected String, got Integer (42)' }]
    error = described_class.new(errors)
    expect(error.message).to include('1 configuration error')
    expect(error.message).to include('[transport] connection.host: expected String, got Integer (42)')
  end

  it 'formats multiple errors into the message' do
    errors = [
      { module: :transport, path: 'connection.host', message: 'expected String, got Integer' },
      { module: :cache, path: 'driver', message: 'expected String, got Array' }
    ]
    error = described_class.new(errors)
    expect(error.message).to include('2 configuration errors')
    expect(error.message).to include('[transport]')
    expect(error.message).to include('[cache]')
  end

  it 'exposes the errors array via #errors' do
    errors = [{ module: :test, path: 'key', message: 'bad' }]
    error = described_class.new(errors)
    expect(error.errors).to eq(errors)
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/legion/settings/validation_error_spec.rb -v`
Expected: FAIL — `cannot load such file -- legion/settings/validation_error`

**Step 3: Write minimal implementation**

Create `lib/legion/settings/validation_error.rb`:
```ruby
# frozen_string_literal: true

module Legion
  module Settings
    class ValidationError < StandardError
      attr_reader :errors

      def initialize(errors)
        @errors = errors
        super(format_message)
      end

      private

      def format_message
        count = @errors.length
        label = count == 1 ? 'error' : 'errors'
        lines = @errors.map do |err|
          "  [#{err[:module]}] #{err[:path]}: #{err[:message]}"
        end
        "#{count} configuration #{label} detected:\n\n#{lines.join("\n")}"
      end
    end
  end
end
```

**Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/legion/settings/validation_error_spec.rb -v`
Expected: PASS (4 examples, 0 failures)

**Step 5: Run rubocop**

Run: `rubocop lib/legion/settings/validation_error.rb spec/legion/settings/validation_error_spec.rb`
Expected: no offenses

**Step 6: Commit**

```bash
git add spec/spec_helper.rb lib/legion/settings/validation_error.rb spec/legion/settings/validation_error_spec.rb
git commit -m "add validation error exception class with formatted multi-error messages"
```

---

### Task 2: Create Schema Class — Type Inference

**Files:**
- Create: `lib/legion/settings/schema.rb`
- Create: `spec/legion/settings/schema_spec.rb`

**Step 1: Write the failing test**

Create `spec/legion/settings/schema_spec.rb`:
```ruby
# frozen_string_literal: true

require 'spec_helper'
require 'legion/settings/schema'

RSpec.describe Legion::Settings::Schema do
  subject(:schema) { described_class.new }

  describe '#register' do
    it 'infers string type from string defaults' do
      schema.register(:transport, { connection: { host: '127.0.0.1' } })
      constraint = schema.constraint(:transport, [:connection, :host])
      expect(constraint[:type]).to eq(:string)
    end

    it 'infers integer type from integer defaults' do
      schema.register(:transport, { connection: { port: 5672 } })
      constraint = schema.constraint(:transport, [:connection, :port])
      expect(constraint[:type]).to eq(:integer)
    end

    it 'infers boolean type from true' do
      schema.register(:cache, { enabled: true })
      constraint = schema.constraint(:cache, [:enabled])
      expect(constraint[:type]).to eq(:boolean)
    end

    it 'infers boolean type from false' do
      schema.register(:cache, { connected: false })
      constraint = schema.constraint(:cache, [:connected])
      expect(constraint[:type]).to eq(:boolean)
    end

    it 'infers any type from nil' do
      schema.register(:crypt, { cluster_secret: nil })
      constraint = schema.constraint(:crypt, [:cluster_secret])
      expect(constraint[:type]).to eq(:any)
    end

    it 'infers hash type from empty hash' do
      schema.register(:cluster, { public_keys: {} })
      constraint = schema.constraint(:cluster, [:public_keys])
      expect(constraint[:type]).to eq(:hash)
    end

    it 'infers array type from empty array' do
      schema.register(:test, { items: [] })
      constraint = schema.constraint(:test, [:items])
      expect(constraint[:type]).to eq(:array)
    end

    it 'recurses into nested hashes' do
      schema.register(:transport, { connection: { host: 'localhost', port: 5672 } })
      expect(schema.constraint(:transport, [:connection, :host])[:type]).to eq(:string)
      expect(schema.constraint(:transport, [:connection, :port])[:type]).to eq(:integer)
    end

    it 'tracks registered module names' do
      schema.register(:transport, { connected: false })
      schema.register(:cache, { enabled: true })
      expect(schema.registered_modules).to contain_exactly(:transport, :cache)
    end
  end

  describe '#define_override' do
    it 'overrides inferred type for a nil default' do
      schema.register(:crypt, { cluster_secret: nil })
      schema.define_override(:crypt, { cluster_secret: { type: :string, required: true } })
      constraint = schema.constraint(:crypt, [:cluster_secret])
      expect(constraint[:type]).to eq(:string)
      expect(constraint[:required]).to eq(true)
    end

    it 'adds enum constraint' do
      schema.register(:cache, { driver: 'dalli' })
      schema.define_override(:cache, { driver: { enum: %w[dalli redis] } })
      constraint = schema.constraint(:cache, [:driver])
      expect(constraint[:enum]).to eq(%w[dalli redis])
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/legion/settings/schema_spec.rb -v`
Expected: FAIL — `cannot load such file -- legion/settings/schema`

**Step 3: Write implementation**

Create `lib/legion/settings/schema.rb`:
```ruby
# frozen_string_literal: true

module Legion
  module Settings
    class Schema
      def initialize
        @schemas = {}
        @registered = []
      end

      def register(mod_name, defaults)
        mod_name = mod_name.to_sym
        @registered << mod_name unless @registered.include?(mod_name)
        @schemas[mod_name] ||= {}
        infer_types(defaults, @schemas[mod_name])
      end

      def define_override(mod_name, overrides)
        mod_name = mod_name.to_sym
        @schemas[mod_name] ||= {}
        apply_overrides(overrides, @schemas[mod_name])
      end

      def constraint(mod_name, key_path)
        node = @schemas[mod_name.to_sym]
        key_path.each do |key|
          return nil unless node.is_a?(Hash) && node.key?(key)
          node = node[key]
        end
        node
      end

      def registered_modules
        @registered.dup
      end

      def schema_for(mod_name)
        @schemas[mod_name.to_sym]
      end

      private

      def infer_types(defaults, target)
        defaults.each do |key, value|
          if value.is_a?(Hash) && !value.empty?
            target[key] ||= {}
            infer_types(value, target[key])
          else
            target[key] ||= {}
            target[key][:type] = infer_type(value)
          end
        end
      end

      def infer_type(value)
        case value
        when String  then :string
        when Integer then :integer
        when Float   then :float
        when true, false then :boolean
        when Array   then :array
        when Hash    then :hash
        when nil     then :any
        else :any
        end
      end

      def apply_overrides(overrides, target)
        overrides.each do |key, value|
          if value.is_a?(Hash) && !value.key?(:type) && !value.key?(:required) && !value.key?(:enum)
            target[key] ||= {}
            apply_overrides(value, target[key])
          else
            target[key] ||= {}
            target[key].merge!(value)
          end
        end
      end
    end
  end
end
```

**Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/legion/settings/schema_spec.rb -v`
Expected: PASS (11 examples, 0 failures)

**Step 5: Run rubocop**

Run: `rubocop lib/legion/settings/schema.rb spec/legion/settings/schema_spec.rb`
Expected: no offenses

**Step 6: Commit**

```bash
git add lib/legion/settings/schema.rb spec/legion/settings/schema_spec.rb
git commit -m "add schema class with type inference from defaults and optional overrides"
```

---

### Task 3: Schema Class — Validation Logic

**Files:**
- Modify: `lib/legion/settings/schema.rb`
- Modify: `spec/legion/settings/schema_spec.rb`

**Step 1: Write the failing tests**

Append to `spec/legion/settings/schema_spec.rb`:
```ruby
  describe '#validate_module' do
    it 'returns no errors for valid settings' do
      schema.register(:cache, { driver: 'dalli', enabled: true, port: 11211 })
      errors = schema.validate_module(:cache, { driver: 'redis', enabled: false, port: 11211 })
      expect(errors).to be_empty
    end

    it 'returns error for wrong type' do
      schema.register(:transport, { connection: { host: '127.0.0.1' } })
      errors = schema.validate_module(:transport, { connection: { host: 42 } })
      expect(errors.length).to eq(1)
      expect(errors.first[:path]).to eq('connection.host')
      expect(errors.first[:message]).to include('expected String')
    end

    it 'skips validation for :any type' do
      schema.register(:crypt, { cluster_secret: nil })
      errors = schema.validate_module(:crypt, { cluster_secret: 'some_secret' })
      expect(errors).to be_empty
    end

    it 'validates enum constraints' do
      schema.register(:cache, { driver: 'dalli' })
      schema.define_override(:cache, { driver: { enum: %w[dalli redis] } })
      errors = schema.validate_module(:cache, { driver: 'memcache' })
      expect(errors.length).to eq(1)
      expect(errors.first[:message]).to include('one of')
    end

    it 'validates required constraint' do
      schema.register(:crypt, { cluster_secret: nil })
      schema.define_override(:crypt, { cluster_secret: { type: :string, required: true } })
      errors = schema.validate_module(:crypt, { cluster_secret: nil })
      expect(errors.length).to eq(1)
      expect(errors.first[:message]).to include('required')
    end

    it 'allows nil for non-required fields regardless of type' do
      schema.register(:transport, { connection: { host: '127.0.0.1' } })
      errors = schema.validate_module(:transport, { connection: { host: nil } })
      expect(errors).to be_empty
    end

    it 'recurses into nested hashes' do
      schema.register(:transport, { connection: { host: '127.0.0.1', port: 5672 } })
      errors = schema.validate_module(:transport, { connection: { host: 42, port: 'bad' } })
      expect(errors.length).to eq(2)
    end
  end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/legion/settings/schema_spec.rb -v`
Expected: FAIL — `undefined method 'validate_module'`

**Step 3: Write implementation**

Add to `lib/legion/settings/schema.rb` inside the `Schema` class, in the public section:
```ruby
      def validate_module(mod_name, values)
        mod_name = mod_name.to_sym
        schema = @schemas[mod_name]
        return [] if schema.nil?

        errors = []
        validate_node(schema, values, mod_name, '', errors)
        errors
      end

      private

      def validate_node(schema_node, value_node, mod_name, path_prefix, errors)
        schema_node.each do |key, constraint|
          current_path = path_prefix.empty? ? key.to_s : "#{path_prefix}.#{key}"
          value = value_node.is_a?(Hash) ? value_node[key] : nil

          if constraint.is_a?(Hash) && constraint.key?(:type)
            validate_leaf(constraint, value, mod_name, current_path, errors)
          elsif constraint.is_a?(Hash)
            validate_node(constraint, value, mod_name, current_path, errors) if value.is_a?(Hash)
          end
        end
      end

      def validate_leaf(constraint, value, mod_name, path, errors)
        if value.nil?
          if constraint[:required]
            errors << { module: mod_name, path: path, message: 'is required but was nil' }
          end
          return
        end

        validate_type(constraint, value, mod_name, path, errors)
        validate_enum(constraint, value, mod_name, path, errors)
      end

      def validate_type(constraint, value, mod_name, path, errors)
        expected = constraint[:type]
        return if expected == :any

        valid = case expected
                when :string  then value.is_a?(String)
                when :integer then value.is_a?(Integer)
                when :float   then value.is_a?(Float) || value.is_a?(Integer)
                when :boolean then value.is_a?(TrueClass) || value.is_a?(FalseClass)
                when :array   then value.is_a?(Array)
                when :hash    then value.is_a?(Hash)
                else true
                end

        return if valid

        type_name = TYPE_NAMES.fetch(expected, expected.to_s)
        errors << { module: mod_name, path: path, message: "expected #{type_name}, got #{value.class} (#{value.inspect})" }
      end

      TYPE_NAMES = { string: 'String', integer: 'Integer', float: 'Float', boolean: 'Boolean',
                     array: 'Array', hash: 'Hash' }.freeze

      def validate_enum(constraint, value, mod_name, path, errors)
        return unless constraint[:enum]
        return if constraint[:enum].include?(value)

        errors << { module: mod_name, path: path, message: "expected one of #{constraint[:enum].inspect}, got #{value.inspect}" }
      end
```

**Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/legion/settings/schema_spec.rb -v`
Expected: PASS (18 examples, 0 failures)

**Step 5: Run rubocop**

Run: `rubocop lib/legion/settings/schema.rb spec/legion/settings/schema_spec.rb`
Expected: no offenses

**Step 6: Commit**

```bash
git add lib/legion/settings/schema.rb spec/legion/settings/schema_spec.rb
git commit -m "add schema validation logic for type, enum, and required constraints"
```

---

### Task 4: Schema Class — Unknown Key Detection

**Files:**
- Modify: `lib/legion/settings/schema.rb`
- Modify: `spec/legion/settings/schema_spec.rb`

**Step 1: Write the failing tests**

Append to `spec/legion/settings/schema_spec.rb`:
```ruby
  describe '#detect_unknown_keys' do
    before do
      schema.register(:transport, { connected: false })
      schema.register(:cache, { enabled: true })
    end

    it 'returns no warnings for known keys' do
      settings = { transport: { connected: true }, cache: { enabled: false } }
      warnings = schema.detect_unknown_keys(settings)
      expect(warnings).to be_empty
    end

    it 'warns about unknown top-level keys' do
      settings = { transport: {}, cache: {}, trasport: {} }
      warnings = schema.detect_unknown_keys(settings)
      expect(warnings.length).to eq(1)
      expect(warnings.first[:message]).to include('trasport')
    end

    it 'suggests corrections for typos within edit distance 2' do
      settings = { transport: {}, cache: {}, tansport: {} }
      warnings = schema.detect_unknown_keys(settings)
      expect(warnings.first[:message]).to include('did you mean')
    end

    it 'skips keys from default_settings that are not module-registered' do
      # Keys like :client, :extensions, :reload etc are in default_settings
      # but not registered by any module via merge_settings.
      # They should be allowed.
      settings = { transport: {}, client: {}, extensions: {} }
      warnings = schema.detect_unknown_keys(settings, known_defaults: %i[client extensions])
      expect(warnings).to be_empty
    end

    it 'warns about unknown first-level keys within a module' do
      schema.register(:cache, { driver: 'dalli', enabled: true })
      settings = { cache: { driver: 'dalli', enbled: true } }
      warnings = schema.detect_unknown_keys(settings)
      expect(warnings.length).to eq(1)
      expect(warnings.first[:path]).to eq('cache.enbled')
    end
  end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/legion/settings/schema_spec.rb -v --tag detect_unknown`
Expected: FAIL — `undefined method 'detect_unknown_keys'`

**Step 3: Write implementation**

Add to `lib/legion/settings/schema.rb` public section:
```ruby
      def detect_unknown_keys(settings, known_defaults: [])
        warnings = []
        all_known = @registered + known_defaults

        settings.each_key do |key|
          next if all_known.include?(key)

          suggestion = find_similar(key, all_known)
          msg = "top-level key :#{key} is not registered by any module"
          msg += " (did you mean :#{suggestion}?)" if suggestion
          warnings << { module: :unknown_key, path: key.to_s, message: msg }
        end

        check_first_level_keys(settings, warnings)
        warnings
      end

      private

      def check_first_level_keys(settings, warnings)
        @schemas.each do |mod_name, mod_schema|
          values = settings[mod_name]
          next unless values.is_a?(Hash)

          known_keys = mod_schema.keys
          values.each_key do |key|
            next if known_keys.include?(key)

            suggestion = find_similar(key, known_keys)
            msg = "unknown key :#{key}"
            msg += " (did you mean :#{suggestion}?)" if suggestion
            warnings << { module: mod_name, path: "#{mod_name}.#{key}", message: msg }
          end
        end
      end

      def find_similar(key, candidates)
        key_str = key.to_s
        candidates.map(&:to_s).select { |c| levenshtein(key_str, c) <= 2 }
                  .min_by { |c| levenshtein(key_str, c) }
                  &.to_sym
      end

      def levenshtein(str_a, str_b)
        m = str_a.length
        n = str_b.length
        return m if n.zero?
        return n if m.zero?

        matrix = Array.new(m + 1) { |i| i }
        (1..n).each do |j|
          prev = matrix[0]
          matrix[0] = j
          (1..m).each do |i|
            cost = str_a[i - 1] == str_b[j - 1] ? 0 : 1
            temp = matrix[i]
            matrix[i] = [matrix[i] + 1, matrix[i - 1] + 1, prev + cost].min
            prev = temp
          end
        end
        matrix[m]
      end
```

**Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/legion/settings/schema_spec.rb -v`
Expected: PASS (23 examples, 0 failures)

**Step 5: Run rubocop**

Run: `rubocop lib/legion/settings/schema.rb spec/legion/settings/schema_spec.rb`
Expected: no offenses

**Step 6: Commit**

```bash
git add lib/legion/settings/schema.rb spec/legion/settings/schema_spec.rb
git commit -m "add unknown key detection with typo suggestions via levenshtein distance"
```

---

### Task 5: Integrate Schema into Settings Module

**Files:**
- Modify: `lib/legion/settings.rb`
- Modify: `lib/legion/settings/loader.rb`
- Delete: `lib/legion/settings/validators/legion.rb`
- Create: `spec/legion/settings/integration_spec.rb`

**Step 1: Write the failing test**

Create `spec/legion/settings/integration_spec.rb`:
```ruby
# frozen_string_literal: true

require 'spec_helper'
require 'legion/settings/schema'
require 'legion/settings/validation_error'

RSpec.describe 'Settings validation integration' do
  before do
    Legion::Settings.instance_variable_set(:@loader, nil)
    Legion::Settings.instance_variable_set(:@schema, nil)
    Legion::Settings.instance_variable_set(:@cross_validations, nil)
    Legion::Settings.load
  end

  describe '.merge_settings with schema inference' do
    it 'registers schema when merging settings' do
      Legion::Settings.merge_settings('mymodule', { host: 'localhost', port: 8080 })
      expect(Legion::Settings.schema.registered_modules).to include(:mymodule)
    end

    it 'collects type errors on merge when user config conflicts' do
      # Simulate user config already loaded with bad type
      Legion::Settings.set_prop(:mymodule, { port: 'not_a_number' })
      Legion::Settings.merge_settings('mymodule', { port: 8080 })
      expect(Legion::Settings.errors).not_to be_empty
    end
  end

  describe '.define_schema' do
    it 'stores overrides for a module' do
      Legion::Settings.merge_settings('cache', { driver: 'dalli' })
      Legion::Settings.define_schema('cache', { driver: { enum: %w[dalli redis] } })
      constraint = Legion::Settings.schema.constraint(:cache, [:driver])
      expect(constraint[:enum]).to eq(%w[dalli redis])
    end
  end

  describe '.add_cross_validation' do
    it 'registers a cross-validation block' do
      called = false
      Legion::Settings.add_cross_validation { |_settings, _errors| called = true }
      Legion::Settings.validate!
      expect(called).to be true
    end

    it 'collects errors from cross-validation blocks' do
      Legion::Settings.add_cross_validation do |_settings, errors|
        errors << { module: :test, path: 'test.key', message: 'cross-module failure' }
      end
      expect { Legion::Settings.validate! }.to raise_error(Legion::Settings::ValidationError)
    end
  end

  describe '.validate!' do
    it 'does not raise when settings are valid' do
      Legion::Settings.merge_settings('valid', { name: 'test', count: 5 })
      expect { Legion::Settings.validate! }.not_to raise_error
    end

    it 'raises ValidationError with all collected errors' do
      Legion::Settings.set_prop(:badmod, { host: 42 })
      Legion::Settings.merge_settings('badmod', { host: 'localhost' })
      expect { Legion::Settings.validate! }.to raise_error(Legion::Settings::ValidationError) do |e|
        expect(e.errors.length).to be >= 1
      end
    end
  end

  describe '.errors' do
    it 'returns the loader errors array' do
      Legion::Settings.merge_settings('clean', { flag: true })
      expect(Legion::Settings.errors).to be_an(Array)
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/legion/settings/integration_spec.rb -v`
Expected: FAIL — `undefined method 'schema'` / `undefined method 'define_schema'`

**Step 3: Modify `lib/legion/settings.rb`**

Replace entire file with:
```ruby
# frozen_string_literal: true

require 'legion/json'
require 'legion/settings/version'
require 'legion/json/parse_error'
require 'legion/settings/loader'
require 'legion/settings/schema'
require 'legion/settings/validation_error'

module Legion
  module Settings
    CORE_MODULES = %i[transport cache crypt data logging client].freeze

    class << self
      attr_accessor :loader

      def load(options = {})
        @loader = Legion::Settings::Loader.new
        @loader.load_env
        @loader.load_file(options[:config_file]) if options[:config_file]
        @loader.load_directory(options[:config_dir]) if options[:config_dir]
        options[:config_dirs]&.each do |directory|
          @loader.load_directory(directory)
        end
        @loader
      end

      def get(options = {})
        @loader || @loader = load(options)
      end

      def [](key)
        logger.info('Legion::Settings was not loading, auto loading now!') if @loader.nil?
        @loader = load if @loader.nil?
        @loader[key]
      rescue NoMethodError, TypeError
        logger.fatal 'rescue inside [](key)'
        nil
      end

      def set_prop(key, value)
        @loader = load if @loader.nil?
        @loader[key] = value
      end

      def merge_settings(key, hash)
        @loader = load if @loader.nil?
        thing = {}
        thing[key.to_sym] = hash
        @loader.load_module_settings(thing)
        schema.register(key.to_sym, hash)
        validate_module_on_merge(key.to_sym)
      end

      def define_schema(key, overrides)
        schema.define_override(key.to_sym, overrides)
      end

      def add_cross_validation(&block)
        cross_validations << block
      end

      def validate!
        @loader = load if @loader.nil?
        revalidate_all_modules
        run_cross_validations
        detect_unknown_keys
        raise ValidationError, errors unless errors.empty?
      end

      def schema
        @schema ||= Schema.new
      end

      def errors
        @loader = load if @loader.nil?
        @loader.errors
      end

      def logger
        @logger = if ::Legion.const_defined?('Logging')
                    ::Legion::Logging
                  else
                    require 'logger'
                    ::Logger.new($stdout)
                  end
      end

      private

      def cross_validations
        @cross_validations ||= []
      end

      def validate_module_on_merge(mod_name)
        values = @loader[mod_name]
        return unless values.is_a?(Hash)

        module_errors = schema.validate_module(mod_name, values)
        @loader.errors.concat(module_errors)
      end

      def revalidate_all_modules
        schema.registered_modules.each do |mod_name|
          values = @loader[mod_name]
          next unless values.is_a?(Hash)

          module_errors = schema.validate_module(mod_name, values)
          @loader.errors.concat(module_errors)
        end
        @loader.errors.uniq!
      end

      def run_cross_validations
        settings_hash = @loader.to_hash
        cross_validations.each do |block|
          block.call(settings_hash, @loader.errors)
        end
      end

      def detect_unknown_keys
        default_keys = @loader.default_settings.keys
        registered = schema.registered_modules
        known_defaults = default_keys - registered

        warnings = schema.detect_unknown_keys(@loader.to_hash, known_defaults: known_defaults)
        warnings.each do |w|
          @loader.errors << w
        end
      end
    end
  end
end
```

**Step 4: Modify `lib/legion/settings/loader.rb`**

Replace the broken `validate` method (line 151-154) with:
```ruby
      def validate
        # Validation is now handled by Legion::Settings.validate!
        # This method is kept for backwards compatibility
        Legion::Settings.validate!
      rescue Legion::Settings::ValidationError
        # errors are already collected in @errors
      end
```

Add `[]=(key, value)` method after the `[](key)` method (after line 69) so `set_prop` works for setting values:
```ruby
      def []=(key, value)
        @settings[key] = value
        @indifferent_access = false
      end
```

Make `default_settings` public by moving the method above the `private` keyword (it's already in the public section — just verify it stays there). It's already public since it's defined before `private` on line 156.

**Step 5: Delete old validator**

```bash
rm lib/legion/settings/validators/legion.rb
rmdir lib/legion/settings/validators
```

**Step 6: Run tests**

Run: `bundle exec rspec -v`
Expected: PASS (all specs pass)

**Step 7: Run rubocop**

Run: `rubocop lib/ spec/`
Expected: no offenses

**Step 8: Commit**

```bash
git add lib/legion/settings.rb lib/legion/settings/loader.rb spec/legion/settings/integration_spec.rb
git rm lib/legion/settings/validators/legion.rb
git commit -m "integrate schema validation into settings: merge-time checks, validate!, cross-validation"
```

---

### Task 6: Add .rubocop.yml Spec Exclusion and Final Verification

**Files:**
- Modify: `.rubocop.yml`

**Step 1: Add spec exclusion for BlockLength**

Add to `.rubocop.yml` under `Metrics/BlockLength`:
```yaml
Metrics/BlockLength:
  Max: 40
  Exclude:
    - 'spec/**/*'
```

**Step 2: Run full rubocop**

Run: `rubocop`
Expected: no offenses

**Step 3: Run full test suite**

Run: `bundle exec rspec -v`
Expected: all green

**Step 4: Commit**

```bash
git add .rubocop.yml
git commit -m "add spec exclusion for metrics/blocklength"
```

---

### Task 7: Update TODO

**Files:**
- Modify: `/Users/miverso2/rubymine/legion/LegionIO/docs/TODO.md`

**Step 1: Mark the config validation item as done**

Change:
```markdown
- [ ] Configuration validation in legion-settings
  - [ ] Schema definitions per module (required keys, types)
  - [ ] Fail-fast on startup with clear error messages
```
To:
```markdown
- [x] Configuration validation in legion-settings
  - [x] Schema definitions per module (inferred from defaults + optional overrides)
  - [x] Fail-fast on startup with clear error messages (collect all, raise once)
  - [ ] Dev mode: warn-but-continue instead of raise
```

**Step 2: Commit**

```bash
cd /Users/miverso2/rubymine/legion/LegionIO
git add docs/TODO.md
git commit -m "mark settings validation as complete in todo"
```

---

Plan complete and saved to `docs/plans/2026-03-13-settings-validation-plan.md`. Two execution options:

**1. Subagent-Driven (this session)** — I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Parallel Session (separate)** — Open new session with executing-plans, batch execution with checkpoints

Which approach?
