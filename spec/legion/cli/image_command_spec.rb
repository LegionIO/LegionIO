# frozen_string_literal: true

require 'spec_helper'
require 'base64'
require 'legion/cli'
require 'legion/cli/image_command'

RSpec.describe Legion::CLI::Image do
  let(:out) { instance_double(Legion::CLI::Output::Formatter) }
  let(:llm_mod) { Module.new }
  let(:llm_response) do
    double('Response', content: 'A beautiful image.',
                       usage:   double('Usage', input_tokens: 100, output_tokens: 20))
  end
  let(:chat_session) { double('ChatSession', ask: llm_response) }

  before do
    allow(Legion::CLI::Output::Formatter).to receive(:new).and_return(out)
    allow(out).to receive(:success)
    allow(out).to receive(:error)
    allow(out).to receive(:warn)
    allow(out).to receive(:json)
    allow(out).to receive(:spacer)
    allow(out).to receive(:detail)
    allow(out).to receive(:header)

    allow(Legion::CLI::Connection).to receive(:config_dir=)
    allow(Legion::CLI::Connection).to receive(:log_level=)
    allow(Legion::CLI::Connection).to receive(:ensure_llm)
    allow(Legion::CLI::Connection).to receive(:shutdown)

    stub_const('Legion::LLM', llm_mod)
    allow(Legion::LLM).to receive(:chat).and_return(chat_session)
  end

  def build_command(opts = {})
    described_class.new([], opts.merge(json: false, no_color: true, verbose: false,
                                       format: 'text', prompt: 'Describe this image in detail'))
  end

  def build_json_command(opts = {})
    described_class.new([], opts.merge(json: true, no_color: true, verbose: false,
                                       format: 'json', prompt: 'Describe this image in detail'))
  end

  def with_temp_image(ext = 'png')
    require 'tempfile'
    file = Tempfile.new(['test_image', ".#{ext}"])
    file.binmode
    file.write("\x89PNG\r\n\x1a\n")
    file.flush
    yield file.path
  ensure
    file&.unlink
  end

  describe 'class structure' do
    it 'is a Thor subcommand' do
      expect(described_class).to be < Thor
    end

    it 'defines analyze and compare commands' do
      expect(described_class.commands.keys).to include('analyze', 'compare')
    end

    it 'has SUPPORTED_TYPES covering common image formats' do
      expect(described_class::SUPPORTED_TYPES).to include('png', 'jpg', 'jpeg', 'gif', 'webp')
    end

    it 'maps extensions to correct MIME types' do
      expect(described_class::MIME_TYPES['png']).to  eq('image/png')
      expect(described_class::MIME_TYPES['jpg']).to  eq('image/jpeg')
      expect(described_class::MIME_TYPES['jpeg']).to eq('image/jpeg')
      expect(described_class::MIME_TYPES['gif']).to  eq('image/gif')
      expect(described_class::MIME_TYPES['webp']).to eq('image/webp')
    end
  end

  describe '#analyze' do
    context 'with a valid image file' do
      it 'reads image, sends to LLM, and outputs response' do
        with_temp_image('png') do |path|
          cmd = build_command
          expect(Legion::LLM).to receive(:chat).and_return(chat_session)
          expect(out).to receive(:header).with('Analysis')
          cmd.analyze(path)
        end
      end

      it 'base64-encodes the image data in the message' do
        with_temp_image('png') do |path|
          raw = File.binread(path)
          expected_b64 = Base64.strict_encode64(raw)
          cmd = build_command

          expect(chat_session).to receive(:ask) do |content|
            image_block = content.find { |b| b[:type] == 'image' }
            expect(image_block[:source][:data]).to eq(expected_b64)
            expect(image_block[:source][:media_type]).to eq('image/png')
            llm_response
          end
          cmd.analyze(path)
        end
      end

      it 'includes the prompt as a text block in the message' do
        with_temp_image('png') do |path|
          cmd = described_class.new([], json: false, no_color: true, verbose: false,
                                        format: 'text', prompt: 'What color is this?')

          expect(chat_session).to receive(:ask) do |content|
            text_block = content.find { |b| b[:type] == 'text' }
            expect(text_block[:text]).to eq('What color is this?')
            llm_response
          end
          cmd.analyze(path)
        end
      end

      it 'passes model option to LLM when provided' do
        with_temp_image('png') do |path|
          cmd = described_class.new([], json: false, no_color: true, verbose: false,
                                        format: 'text', prompt: 'desc', model: 'claude-opus-4-5')
          expect(Legion::LLM).to receive(:chat)
            .with(hash_including(model: 'claude-opus-4-5'))
            .and_return(chat_session)
          cmd.analyze(path)
        end
      end

      it 'passes provider option as symbol to LLM when provided' do
        with_temp_image('png') do |path|
          cmd = described_class.new([], json: false, no_color: true, verbose: false,
                                        format: 'text', prompt: 'desc', provider: 'anthropic')
          expect(Legion::LLM).to receive(:chat)
            .with(hash_including(provider: :anthropic))
            .and_return(chat_session)
          cmd.analyze(path)
        end
      end
    end

    context 'MIME type detection' do
      %w[jpg jpeg].each do |ext|
        it "maps .#{ext} to image/jpeg" do
          with_temp_image(ext) do |path|
            cmd = build_command
            expect(chat_session).to receive(:ask) do |content|
              image_block = content.find { |b| b[:type] == 'image' }
              expect(image_block[:source][:media_type]).to eq('image/jpeg')
              llm_response
            end
            cmd.analyze(path)
          end
        end
      end

      %w[gif webp].each do |ext|
        it "maps .#{ext} to image/#{ext}" do
          with_temp_image(ext) do |path|
            cmd = build_command
            expect(chat_session).to receive(:ask) do |content|
              image_block = content.find { |b| b[:type] == 'image' }
              expect(image_block[:source][:media_type]).to eq("image/#{ext}")
              llm_response
            end
            cmd.analyze(path)
          end
        end
      end
    end

    context 'output format' do
      it 'renders text output by default' do
        with_temp_image('png') do |path|
          cmd = build_command
          expect(out).to receive(:header).with('Analysis')
          expect(out).to receive(:spacer).at_least(:once)
          cmd.analyze(path)
        end
      end

      it 'outputs JSON when --format json is set' do
        with_temp_image('png') do |path|
          cmd = described_class.new([], json: false, no_color: true, verbose: false,
                                        format: 'json', prompt: 'desc')
          expect(out).to receive(:json).with(hash_including(response: 'A beautiful image.'))
          cmd.analyze(path)
        end
      end

      it 'outputs JSON when --json flag is set' do
        with_temp_image('png') do |path|
          cmd = build_json_command
          expect(out).to receive(:json).with(hash_including(
                                               path:     path,
                                               response: 'A beautiful image.'
                                             ))
          cmd.analyze(path)
        end
      end

      it 'includes usage stats in JSON output' do
        with_temp_image('png') do |path|
          cmd = build_json_command
          expect(out).to receive(:json).with(hash_including(
                                               usage: { input_tokens: 100, output_tokens: 20 }
                                             ))
          cmd.analyze(path)
        end
      end
    end

    context 'error cases' do
      it 'shows error and exits when file does not exist' do
        cmd = build_command
        expect(out).to receive(:error).with(/File not found/)
        expect { cmd.analyze('/nonexistent/path/image.png') }.to raise_error(SystemExit)
      end

      it 'shows error and exits for unsupported file type' do
        require 'tempfile'
        file = Tempfile.new(['test', '.bmp'])
        file.close

        cmd = build_command
        expect(out).to receive(:error).with(/Unsupported image type/)
        expect { cmd.analyze(file.path) }.to raise_error(SystemExit)
      ensure
        file&.unlink
      end

      it 'shows error when LLM raises an exception' do
        with_temp_image('png') do |path|
          allow(chat_session).to receive(:ask).and_raise(StandardError, 'provider unavailable')
          cmd = build_command
          expect(out).to receive(:error).with(/LLM call failed.*provider unavailable/)
          expect { cmd.analyze(path) }.to raise_error(SystemExit)
        end
      end

      it 'shows error when LLM connection setup fails' do
        with_temp_image('png') do |path|
          allow(Legion::CLI::Connection).to receive(:ensure_llm)
            .and_raise(Legion::CLI::Error, 'legion-llm gem is not installed')
          cmd = build_command
          expect(out).to receive(:error).with(/legion-llm gem is not installed/)
          expect { cmd.analyze(path) }.to raise_error(SystemExit)
        end
      end
    end
  end

  describe '#compare' do
    context 'with two valid image files' do
      it 'sends both images to LLM in a single message' do
        with_temp_image('png') do |path1|
          with_temp_image('jpg') do |path2|
            cmd = described_class.new([], json: false, no_color: true, verbose: false,
                                          format: 'text',
                                          prompt: 'Compare these two images and describe the differences')

            expect(chat_session).to receive(:ask) do |content|
              image_blocks = content.select { |b| b[:type] == 'image' }
              expect(image_blocks.length).to eq(2)
              expect(image_blocks[0][:source][:media_type]).to eq('image/png')
              expect(image_blocks[1][:source][:media_type]).to eq('image/jpeg')
              llm_response
            end
            cmd.compare(path1, path2)
          end
        end
      end

      it 'includes the comparison prompt as text block' do
        with_temp_image('png') do |path1|
          with_temp_image('png') do |path2|
            custom_prompt = 'Which image is brighter?'
            cmd = described_class.new([], json: false, no_color: true, verbose: false,
                                          format: 'text', prompt: custom_prompt)

            expect(chat_session).to receive(:ask) do |content|
              text_block = content.find { |b| b[:type] == 'text' }
              expect(text_block[:text]).to eq(custom_prompt)
              llm_response
            end
            cmd.compare(path1, path2)
          end
        end
      end

      it 'renders text output with analysis header' do
        with_temp_image('png') do |path1|
          with_temp_image('png') do |path2|
            cmd = described_class.new([], json: false, no_color: true, verbose: false,
                                          format: 'text',
                                          prompt: 'Compare these two images and describe the differences')
            expect(out).to receive(:header).with('Analysis')
            cmd.compare(path1, path2)
          end
        end
      end

      it 'outputs JSON with both paths when --json is set' do
        with_temp_image('png') do |path1|
          with_temp_image('png') do |path2|
            cmd = build_json_command(prompt: 'Compare these two images and describe the differences')
            expect(out).to receive(:json).with(hash_including(
                                                 path1:    path1,
                                                 path2:    path2,
                                                 response: 'A beautiful image.'
                                               ))
            cmd.compare(path1, path2)
          end
        end
      end
    end

    context 'error cases' do
      it 'shows error and exits when first file does not exist' do
        with_temp_image('png') do |path2|
          cmd = build_command
          expect(out).to receive(:error).with(/File not found/)
          expect { cmd.compare('/nonexistent/image.png', path2) }.to raise_error(SystemExit)
        end
      end

      it 'shows error and exits when second file does not exist' do
        with_temp_image('png') do |path1|
          cmd = build_command
          expect(out).to receive(:error).with(/File not found/)
          expect { cmd.compare(path1, '/nonexistent/image.png') }.to raise_error(SystemExit)
        end
      end

      it 'shows error for unsupported type on first image' do
        require 'tempfile'
        bad = Tempfile.new(['img', '.tiff'])
        bad.close
        with_temp_image('png') do |path2|
          cmd = build_command
          expect(out).to receive(:error).with(/Unsupported image type/)
          expect { cmd.compare(bad.path, path2) }.to raise_error(SystemExit)
        end
      ensure
        bad&.unlink
      end
    end
  end

  describe '#load_image' do
    it 'returns a hash with path, mime_type, and base64 data' do
      with_temp_image('png') do |path|
        cmd = build_command
        result = cmd.load_image(path, out)
        expect(result[:path]).to eq(path)
        expect(result[:mime_type]).to eq('image/png')
        expect(result[:data]).to eq(Base64.strict_encode64(File.binread(path)))
      end
    end

    it 'raises SystemExit for missing file' do
      cmd = build_command
      expect(out).to receive(:error).with(/File not found/)
      expect { cmd.load_image('/no/such/file.png', out) }.to raise_error(SystemExit)
    end

    it 'raises SystemExit for unsupported extension' do
      require 'tempfile'
      f = Tempfile.new(['img', '.svg'])
      f.close
      cmd = build_command
      expect(out).to receive(:error).with(/Unsupported image type/)
      expect { cmd.load_image(f.path, out) }.to raise_error(SystemExit)
    ensure
      f&.unlink
    end
  end

  describe '#build_image_message' do
    it 'builds a user message with image and text content blocks' do
      cmd = build_command
      images = [{ path: '/img.png', mime_type: 'image/png', data: 'abc123' }]
      msg = cmd.build_image_message(images, 'What is this?')

      expect(msg[:role]).to eq('user')
      expect(msg[:content].length).to eq(2)
      expect(msg[:content][0][:type]).to eq('image')
      expect(msg[:content][0][:source][:type]).to eq('base64')
      expect(msg[:content][0][:source][:media_type]).to eq('image/png')
      expect(msg[:content][0][:source][:data]).to eq('abc123')
      expect(msg[:content][1][:type]).to eq('text')
      expect(msg[:content][1][:text]).to eq('What is this?')
    end

    it 'includes all images when multiple are provided' do
      cmd = build_command
      images = [
        { path: '/a.png', mime_type: 'image/png',  data: 'data1' },
        { path: '/b.jpg', mime_type: 'image/jpeg', data: 'data2' }
      ]
      msg = cmd.build_image_message(images, 'Compare')
      image_blocks = msg[:content].select { |b| b[:type] == 'image' }
      expect(image_blocks.length).to eq(2)
    end
  end
end
