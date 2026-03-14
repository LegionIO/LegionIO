# frozen_string_literal: true

module Legion
  module TeamsCache
    # Parses Chromium IndexedDB values from Teams LevelDB records.
    # Values use 0x22 (double-quote) as a string marker followed by varint length.
    # Teams stores conversation objects as sequential key-value string pairs.
    #
    # Gotchas:
    #   - Boolean fields (isSanitized, isModerator, etc.) have non-string values
    #     that get skipped by the string extractor, causing the next field name
    #     to appear immediately.
    #   - HTML content strings get split on internal 0x22 bytes (from HTML attributes
    #     like href="..."), producing multiple string fragments for one content field.
    #   - Field names are well-known and can be used to detect key vs value.
    class RecordParser
      # Known field names in Teams conversation records.
      # Used to distinguish field names from field values in the string stream.
      KNOWN_FIELDS = Set.new(%w[
                               id source version type content contentHash isSanitized messagetype messageType
                               contenttype contentType activitytype activityType clientmessageid clientMessageId
                               sequenceId prioritizeimdisplayname prioritizeImDisplayName imdisplayname
                               fromDisplayNameInToken fromFamilyNameInToken fromGivenNameInToken
                               fromAgentIdentityBlueprintId properties mentions cards importance subject title
                               links files formatVariant languageStamp draftDetails innerThreadId state
                               inlineImages callId composetime composeTime originalarrivaltime originalArrivalTime
                               from fromUserId conversationLink skypeguid translation deletionInfo
                               annotationsSummary threadtype threadType postType dlpData crossPostData
                               callLogsOwnerId sendPipelineStatus streamingMetadata originalParentMessageId
                               skypeeditedid importMetadata recipientId isPlainTextConvertedToHtml
                               clientArrivalTime lastMessage members botMembers rosterVersion rosterSummary
                               nonFilteredLastMessageTimeUtc __typename localClientId memberProperties
                               memberExpirationTime role explicitlyAdded isModerator isFollowing isReader
                               channelOnlyMember messages lastMessageTimeUtc detailsVersion
                               consumptionHorizonForPinnedMessages consumptionhorizon consumptionHorizonBookmark
                               rclch rclchBookmark lastTimeFavorited favorite ispinned
                               lastimportantimreceivedtime lasturgentimreceivedtime isfollowed followAllRc
                               notifyAllRc collapsed isGeneralChannelFavorite pinnedVersion pinnedOrder
                               hasMessageDraft targetLink teamId threadProperties topic topicThreadTopic
                               spaceThreadTopic spaceThreadVersion description favDefault
                               channelDocsFolderRelativeUrl channelDocsDocumentLibraryId sharepointRootLibrary
                               isdeleted tenantid creator retentionHorizon retentionHorizonV2
                               sharedInSpaces spaceId gapDetectionEnabled createdat groupId
                               extensionDefinitionContainer lastjoinat lastleaveat chatModalityType
                               threadingMode csav1 teamSmtpAddress spaceType spaceTypes classification
                               dynamicMembership isMaxMemberLimitExceeded isTeamLocked
                               isUnlockMembershipSyncRequired picture pictureETag sharepointSiteUrl
                               notebookId sensitivityLabelDisplayName sensitivityLabelId sensitivityLabelName
                               sensitivityLabelToolTip sensitivityLabelParentDisplayName
                               sensitivityLabelParentName sensitivityLabelParentTooltip
                               sensitivityLabelIsCopyBlocked teamStatus spaceAdminSettings visibility
                               topics threadVersion lastContentMessageTime identityMaskEnabled
                               lastL2MessageIdNotFromSelf parentId clientUpdateTime isMigrated chatSubType
                               conversationId replyChainId latestDeliveryTime parentMessageVersion
                               messageMap dedupeKey parentMessageId searchKey edittime skypeGuid
                               isConversationLastMessage isConversationLastMessageSanitized
                               originalNonLieMessage hasAnnotated messageSearchKey
                             ]).freeze

      # Fields that have boolean or numeric values (not strings).
      # When we see these, the next string is NOT their value — it's the next field.
      BOOLEAN_FIELDS = Set.new(%w[
                                 isSanitized isModerator isFollowing isReader channelOnlyMember
                                 explicitlyAdded hasMessageDraft ispinned isfollowed collapsed
                                 isGeneralChannelFavorite favDefault isdeleted isMaxMemberLimitExceeded
                                 isTeamLocked isUnlockMembershipSyncRequired isPlainTextConvertedToHtml
                                 gapDetectionEnabled dynamicMembership identityMaskEnabled
                                 sensitivityLabelIsCopyBlocked isMigrated prioritizeimdisplayname
                                 prioritizeImDisplayName isConversationLastMessage
                                 isConversationLastMessageSanitized hasAnnotated
                               ]).freeze

      # Extract ordered string array from a binary IDB value.
      def self.extract_strings(data)
        strings = []
        pos = 0

        while pos < data.bytesize
          if data.getbyte(pos) == 0x22
            str, new_pos = read_length_prefixed_string(data, pos + 1)
            if str
              strings << str
              pos = new_pos
              next
            end
          end
          pos += 1
        end

        strings
      end

      # Parse a conversation record into a structured hash.
      # Uses known field names to correctly pair keys with values,
      # handling boolean fields (no string value) and fragmented HTML content.
      def self.parse_conversation(strings)
        fields = {}
        last_message = {}
        in_last_message = false
        past_last_message = false

        i = 0
        while i < strings.length
          str = strings[i]

          # Detect section boundaries
          if str == 'lastMessage'
            in_last_message = true
            i += 1
            next
          end

          if in_last_message && %w[members botMembers rosterVersion rosterSummary
                                   nonFilteredLastMessageTimeUtc __typename
                                   localClientId parentId clientUpdateTime].include?(str)
            in_last_message = false
            past_last_message = true
          end

          target = in_last_message ? last_message : fields

          advance = consume_field(strings, i, str, target, past_last_message)
          i += advance
        end

        { fields: fields, last_message: last_message }
      end

      # Consume one field token from the strings array and return how many positions to advance.
      def self.consume_field(strings, idx, str, target, past_last_message)
        if KNOWN_FIELDS.include?(str)
          consume_known_field(strings, idx, str, target)
        else
          target['content'] = "#{target['content']}#{str}" if target.key?('content') && html_fragment?(str) && !past_last_message
          1
        end
      end

      def self.consume_known_field(strings, idx, str, target)
        return 1 if BOOLEAN_FIELDS.include?(str)
        return 1 if idx + 1 >= strings.length

        value = strings[idx + 1]
        if KNOWN_FIELDS.include?(value)
          1
        else
          target[str] = value
          2
        end
      end

      # Check if a string looks like an HTML fragment (split from content field).
      def self.html_fragment?(str)
        str.include?('<') || str.start_with?('http') ||
          str.match?(/\A(width|height|alt|id|itemid|src|href|target|rel|style)/) ||
          str.match?(/\A[a-z]+=/)
      end

      def self.read_length_prefixed_string(data, pos)
        return nil if pos >= data.bytesize

        len = data.getbyte(pos)
        return nil unless len&.positive?

        if len < 0x80
          str_start = pos + 1
          actual_len = len
        else
          next_byte = data.getbyte(pos + 1)
          return nil unless next_byte

          actual_len = (len & 0x7F) | (next_byte << 7)
          str_start = pos + 2

          if next_byte >= 0x80 && pos + 2 < data.bytesize
            third = data.getbyte(pos + 2)
            return nil unless third

            actual_len = (len & 0x7F) | ((next_byte & 0x7F) << 7) | (third << 14)
            str_start = pos + 3
          end
        end

        return nil if actual_len <= 0 || actual_len > 1_000_000
        return nil if str_start + actual_len > data.bytesize

        str = data.byteslice(str_start, actual_len)
        str.force_encoding('UTF-8')
        return nil unless str.valid_encoding?

        [str, str_start + actual_len]
      end
    end
  end
end
