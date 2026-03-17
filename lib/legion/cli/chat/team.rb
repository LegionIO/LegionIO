# frozen_string_literal: true

module Legion
  module CLI
    class Chat
      module Team
        class UserContext
          attr_reader :user_id, :team_id, :display_name

          def initialize(user_id:, team_id: nil, display_name: nil)
            @user_id = user_id
            @team_id = team_id
            @display_name = display_name || user_id
          end

          def to_h
            { user_id: user_id, team_id: team_id, display_name: display_name }
          end
        end

        class << self
          def current_user
            Thread.current[:legion_chat_user]
          end

          def with_user(context)
            previous = Thread.current[:legion_chat_user]
            Thread.current[:legion_chat_user] = context
            yield
          ensure
            Thread.current[:legion_chat_user] = previous
          end

          def detect_user
            user_id = ENV.fetch('LEGION_USER', ENV.fetch('USER', 'anonymous'))
            team_id = ENV.fetch('LEGION_TEAM', nil)
            UserContext.new(user_id: user_id, team_id: team_id)
          end
        end
      end
    end
  end
end
