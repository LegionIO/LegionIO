# frozen_string_literal: true

require 'time'
require_relative 'sstable_reader'
require_relative 'record_parser'

module Legion
  module TeamsCache
    # Extracts Teams messages from the local Chromium IndexedDB LevelDB cache.
    # Works offline - reads the local file system, no Graph API needed.
    #
    # Two record types contain messages:
    #   1. Conversation records: metadata + lastMessage (one per conversation)
    #   2. MessageMap records: replyChainId + messageMap with multiple messages
    class Extractor
      Message = Struct.new(
        :content,         # HTML message body
        :sender,          # display name (e.g. "Iverson, Matthew D")
        :sender_id,       # orgid URI (e.g. "8:orgid:uuid")
        :message_type,    # RichText/Html, RichText/Media_Card, Text
        :content_type,    # Text
        :compose_time,    # ISO 8601 timestamp
        :thread_id,       # conversation thread ID
        :thread_type,     # space, chat, topic
        :thread_topic,    # channel/chat name
        :client_msg_id,   # unique client message ID
        :content_hash,    # dedup hash from Teams
        :message_id
      )

      DEFAULT_PATH = File.expand_path(
        '~/Library/Containers/com.microsoft.teams2/Data/Library/Application Support/' \
        'Microsoft/MSTeams/EBWebView/WV2Profile_tfw/IndexedDB/' \
        'https_teams.microsoft.com_0.indexeddb.leveldb'
      ).freeze

      SKIP_MESSAGE_TYPES = %w[
        ThreadActivity/AddMember
        ThreadActivity/DeleteMember
        ThreadActivity/TopicUpdate
        Event/Call
        RichText/Media_CallRecording
      ].freeze

      def initialize(db_path: DEFAULT_PATH)
        @db_path = db_path
      end

      # Returns true if the Teams LevelDB directory exists.
      def available?
        Dir.exist?(@db_path)
      end

      # Extract all messages. Returns array of Message structs.
      # Options:
      #   since:      Time - only messages after this time
      #   channels:   Array<String> - filter by thread topic/name
      #   senders:    Array<String> - filter by sender display name
      #   skip_bots:  Boolean - skip integration/bot messages (default: true)
      def extract(since: nil, channels: nil, senders: nil, skip_bots: true)
        raise "Teams cache not found at #{@db_path}" unless available?

        messages = []
        seen_hashes = Set.new

        each_ldb_file do |path|
          reader = SSTableReader.new(path)
          reader.each_entry do |_key, value|
            extract_from_record(value, messages, seen_hashes)
          end
        rescue StandardError => e
          warn "TeamsCache: error reading #{File.basename(path)}: #{e.message}"
        end

        messages = apply_filters(messages, since: since, channels: channels,
                                           senders: senders, skip_bots: skip_bots)
        messages.sort_by { |m| m.compose_time || '' }
      end

      # Returns summary stats without extracting full messages.
      def stats
        return nil unless available?

        file_count = 0
        total_bytes = 0

        each_ldb_file do |path|
          file_count += 1
          total_bytes += File.size(path)
        end

        {
          path:        @db_path,
          ldb_files:   file_count,
          total_bytes: total_bytes,
          total_mb:    (total_bytes / 1_048_576.0).round(1)
        }
      end

      private

      def each_ldb_file(&)
        files = Dir.glob(File.join(@db_path, '*.ldb')) +
                Dir.glob(File.join(@db_path, '*.log'))
        files.sort_by { |f| File.mtime(f) }.each(&)
      end

      def extract_from_record(value, messages, seen_hashes)
        return unless value && value.bytesize > 50

        strings = RecordParser.extract_strings(value)
        return if strings.size < 10

        if strings.include?('messageMap')
          extract_message_map(strings, messages, seen_hashes)
        elsif strings.include?('lastMessage')
          extract_conversation(strings, messages, seen_hashes)
        end
      end

      def extract_conversation(strings, messages, seen_hashes)
        parsed = RecordParser.parse_conversation(strings)
        lm = parsed[:last_message]
        fields = parsed[:fields]

        return if lm.empty? || lm['content'].nil? || lm['content'].empty?

        add_message(messages, seen_hashes,
                    content:       lm['content'],
                    sender:        lm['imdisplayname'] || lm['fromDisplayNameInToken'],
                    sender_id:     lm['fromUserId'] || lm['from'],
                    msg_type:      lm['messagetype'] || lm['messageType'],
                    compose_time:  lm['composetime'] || lm['composeTime'],
                    thread_id:     fields['id'],
                    thread_type:   fields['threadType'] || lm['threadtype'],
                    thread_topic:  fields['topicThreadTopic'] || fields['topic'],
                    client_msg_id: lm['clientmessageid'] || lm['clientMessageId'],
                    content_hash:  lm['contentHash'] || lm['contenthash'],
                    message_id:    lm['id'])
      end

      # Extract individual messages from a messageMap record.
      # These contain multiple messages in a reply chain.
      def extract_message_map(strings, messages, seen_hashes) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
        conversation_id = nil
        i = 0

        # Read header
        while i < strings.length && strings[i] != 'messageMap'
          conversation_id = strings[i + 1] if strings[i] == 'conversationId'
          i += 1
        end

        return unless conversation_id

        i += 1 if strings[i] == 'messageMap'

        # Parse individual messages. Each message block contains content, sender, etc.
        # New messages are delimited by 'dedupeKey' fields.
        current_msg = {}
        while i < strings.length
          field = strings[i]

          if field == 'dedupeKey' && current_msg.key?('content')
            flush_map_entry(current_msg, conversation_id, messages, seen_hashes)
            current_msg = {}
          end

          if RecordParser::BOOLEAN_FIELDS.include?(field)
            i += 1
            next
          end

          if RecordParser::KNOWN_FIELDS.include?(field) && i + 1 < strings.length
            next_str = strings[i + 1]
            if RecordParser::KNOWN_FIELDS.include?(next_str)
              i += 1
            else
              current_msg[field] = next_str
              i += 2
            end
          else
            current_msg['content'] = "#{current_msg['content']}#{field}" if current_msg.key?('content') && RecordParser.html_fragment?(field)
            i += 1
          end
        end

        flush_map_entry(current_msg, conversation_id, messages, seen_hashes) if current_msg.key?('content')
      end

      def flush_map_entry(msg, conversation_id, messages, seen_hashes)
        return if msg['content'].nil? || msg['content'].empty?

        add_message(messages, seen_hashes,
                    content:       msg['content'],
                    sender:        msg['imdisplayname'] || msg['fromDisplayNameInToken'],
                    sender_id:     msg['fromUserId'] || msg['from'] || msg['creator'],
                    msg_type:      msg['messagetype'] || msg['messageType'],
                    compose_time:  msg['composetime'] || msg['composeTime'],
                    thread_id:     conversation_id,
                    thread_type:   nil,
                    thread_topic:  nil,
                    client_msg_id: msg['clientmessageid'] || msg['clientMessageId'],
                    content_hash:  msg['contentHash'] || msg['contenthash'],
                    message_id:    msg['id'])
      end

      def add_message(messages, seen_hashes, content:, sender:, sender_id:, msg_type:, # rubocop:disable Metrics/ParameterLists
                      compose_time:, thread_id:, thread_type:, thread_topic:,
                      client_msg_id:, content_hash:, message_id:)
        dedup_key = content_hash || content
        return if seen_hashes.include?(dedup_key)

        seen_hashes << dedup_key
        return if SKIP_MESSAGE_TYPES.include?(msg_type)

        messages << Message.new(
          content:       content,
          sender:        sender,
          sender_id:     sender_id,
          message_type:  msg_type,
          content_type:  nil,
          compose_time:  compose_time,
          thread_id:     thread_id,
          thread_type:   thread_type,
          thread_topic:  thread_topic,
          client_msg_id: client_msg_id,
          content_hash:  content_hash,
          message_id:    message_id
        )
      end

      def apply_filters(messages, since:, channels:, senders:, skip_bots:) # rubocop:disable Metrics/CyclomaticComplexity
        messages.select do |msg|
          next false if since && msg.compose_time && Time.parse(msg.compose_time) < since
          next false if channels&.none? { |c| msg.thread_topic&.downcase&.include?(c.downcase) }
          next false if senders&.none? { |s| msg.sender&.downcase&.include?(s.downcase) }
          next false if skip_bots && bot_message?(msg)

          true
        end
      end

      def bot_message?(msg)
        return false unless msg.sender_id

        # Integration/bot senders use "28:..." prefix, humans use "8:orgid:..."
        msg.sender_id.start_with?('28:') ||
          msg.sender_id.include?('integration:') ||
          msg.sender_id.include?('bot:')
      end
    end
  end
end
