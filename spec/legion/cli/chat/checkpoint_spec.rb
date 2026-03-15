# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'legion/cli/chat/checkpoint'

RSpec.describe Legion::CLI::Chat::Checkpoint do
  let(:tmpdir) { Dir.mktmpdir('checkpoint-test') }
  let(:test_file) { File.join(tmpdir, 'test.txt') }

  before do
    described_class.configure(max_depth: 10, mode: :per_edit)
  end

  after do
    described_class.clear
    FileUtils.rm_rf(tmpdir)
  end

  describe '.save' do
    it 'saves state of an existing file' do
      File.write(test_file, 'original content')
      entry = described_class.save(test_file)

      expect(entry.path).to eq(test_file)
      expect(entry.content).to eq('original content')
      expect(entry.existed).to be true
      expect(entry.timestamp).to be_a(Time)
    end

    it 'saves state for a non-existent file' do
      entry = described_class.save(File.join(tmpdir, 'new.txt'))

      expect(entry.existed).to be false
      expect(entry.content).to be_nil
    end

    it 'respects max_depth' do
      described_class.configure(max_depth: 3)
      5.times { |i| described_class.save(File.join(tmpdir, "file#{i}.txt")) }

      expect(described_class.count).to eq(3)
    end
  end

  describe '.rewind' do
    it 'restores the last edit' do
      File.write(test_file, 'original')
      described_class.save(test_file)
      File.write(test_file, 'modified')

      restored = described_class.rewind(1)

      expect(restored.length).to eq(1)
      expect(File.read(test_file)).to eq('original')
    end

    it 'rewinds multiple steps' do
      file_a = File.join(tmpdir, 'a.txt')
      file_b = File.join(tmpdir, 'b.txt')
      File.write(file_a, 'a-original')
      File.write(file_b, 'b-original')

      described_class.save(file_a)
      File.write(file_a, 'a-modified')
      described_class.save(file_b)
      File.write(file_b, 'b-modified')

      restored = described_class.rewind(2)

      expect(restored.length).to eq(2)
      expect(File.read(file_a)).to eq('a-original')
      expect(File.read(file_b)).to eq('b-original')
    end

    it 'deletes a file that was newly created' do
      new_file = File.join(tmpdir, 'brand_new.txt')
      described_class.save(new_file)
      File.write(new_file, 'created after checkpoint')

      described_class.rewind(1)

      expect(File.exist?(new_file)).to be false
    end

    it 'returns empty array when no checkpoints exist' do
      expect(described_class.rewind(1)).to eq([])
    end

    it 'clamps steps to available checkpoints' do
      File.write(test_file, 'content')
      described_class.save(test_file)

      restored = described_class.rewind(100)
      expect(restored.length).to eq(1)
    end
  end

  describe '.rewind_file' do
    it 'restores a specific file' do
      file_a = File.join(tmpdir, 'a.txt')
      file_b = File.join(tmpdir, 'b.txt')
      File.write(file_a, 'a-original')
      File.write(file_b, 'b-original')

      described_class.save(file_a)
      File.write(file_a, 'a-modified')
      described_class.save(file_b)
      File.write(file_b, 'b-modified')

      entry = described_class.rewind_file(file_a)

      expect(entry).not_to be_nil
      expect(File.read(file_a)).to eq('a-original')
      expect(File.read(file_b)).to eq('b-modified')
    end

    it 'returns nil when file has no checkpoint' do
      expect(described_class.rewind_file('/no/such/file')).to be_nil
    end
  end

  describe '.list' do
    it 'returns checkpoint metadata' do
      File.write(test_file, 'content')
      described_class.save(test_file)

      entries = described_class.list
      expect(entries.length).to eq(1)
      expect(entries.first[:path]).to eq(test_file)
      expect(entries.first[:existed]).to be true
      expect(entries.first[:timestamp]).to be_a(Time)
    end
  end

  describe '.clear' do
    it 'removes all checkpoints' do
      3.times { |i| described_class.save(File.join(tmpdir, "f#{i}.txt")) }
      described_class.clear
      expect(described_class.count).to eq(0)
    end
  end

  describe '.count' do
    it 'returns the number of checkpoints' do
      expect(described_class.count).to eq(0)
      described_class.save(test_file)
      expect(described_class.count).to eq(1)
    end
  end
end
