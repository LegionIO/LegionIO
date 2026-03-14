# frozen_string_literal: true

require 'snappy'

module Legion
  module TeamsCache
    # Pure Ruby LevelDB SSTable (.ldb) reader with Snappy decompression.
    # Reads Chromium's IndexedDB LevelDB files without native LevelDB bindings.
    class SSTableReader
      FOOTER_SIZE = 48
      BLOCK_TRAILER_SIZE = 5
      FOOTER_MAGIC = [0x57, 0xfb, 0x80, 0x8b, 0x24, 0x75, 0x47, 0xdb].pack('C*').freeze

      def initialize(path)
        @data = File.binread(path)
      end

      def each_entry(&)
        return enum_for(:each_entry) unless block_given?

        footer = read_footer
        return unless footer

        index_block = read_block(footer[:index_offset], footer[:index_size])
        return unless index_block

        parse_block_entries(index_block) do |_key, handle_data|
          offset, size, = decode_block_handle_at(handle_data, 0)
          next unless offset && size

          data_block = read_block(offset, size)
          next unless data_block

          parse_block_entries(data_block, &)
        end
      end

      private

      def read_footer
        return nil if @data.bytesize < FOOTER_SIZE

        footer = @data.byteslice(@data.bytesize - FOOTER_SIZE, FOOTER_SIZE)
        return nil unless footer.byteslice(40, 8) == FOOTER_MAGIC

        mo, ms, p = decode_block_handle_at(footer, 0)
        io, is, = decode_block_handle_at(footer, p)
        { meta_offset: mo, meta_size: ms, index_offset: io, index_size: is }
      end

      def read_block(offset, size)
        return nil if offset + size + BLOCK_TRAILER_SIZE > @data.bytesize

        block = @data.byteslice(offset, size)
        case @data.getbyte(offset + size)
        when 0x00 then block
        when 0x01 then Snappy.inflate(block)
        end
      rescue Snappy::Error
        nil
      end

      def parse_block_entries(block, &blk)
        return unless block && block.bytesize > 4

        num_restarts = block.byteslice(-4, 4).unpack1('V')
        data_end = block.bytesize - 4 - (num_restarts * 4)
        return if data_end <= 0

        pos = 0
        prev_key = String.new(encoding: 'BINARY')

        while pos < data_end
          shared, pos = decode_varint(block, pos)
          non_shared, pos = decode_varint(block, pos)
          value_len, pos = decode_varint(block, pos)
          break unless shared && non_shared && value_len
          break if pos + non_shared + value_len > data_end

          key = String.new(encoding: 'BINARY')
          key << prev_key.byteslice(0, shared) if shared.positive?
          key << block.byteslice(pos, non_shared)
          pos += non_shared

          value = block.byteslice(pos, value_len)
          pos += value_len

          prev_key = key
          blk.call(key, value)
        end
      end

      def decode_block_handle_at(data, pos)
        offset, pos = decode_varint(data, pos)
        size, pos = decode_varint(data, pos)
        [offset, size, pos]
      end

      def decode_varint(data, pos)
        result = 0
        shift = 0
        loop do
          return [nil, pos] if pos >= data.bytesize

          byte = data.getbyte(pos)
          pos += 1
          result |= ((byte & 0x7F) << shift)
          break if byte.nobits?(0x80)

          shift += 7
          return [nil, pos] if shift > 63
        end
        [result, pos]
      end
    end
  end
end
