# frozen_string_literal: true

require 'securerandom'

module Legion
  class API < Sinatra::Base
    module Routes
      module Skills
        def self.registered(app)
          app.helpers do
            define_method(:skills_registry_available?) do
              defined?(Legion::LLM::Skills::Registry)
            end

            define_method(:skill_descriptor) do |skill|
              {
                name:        skill.skill_name,
                namespace:   skill.namespace,
                description: skill.description,
                trigger:     skill.trigger,
                follows:     skill.follows_skill
              }
            end
          end

          register_list(app)
          register_show(app)
          register_invoke(app)
          register_cancel(app)
        end

        def self.register_list(app)
          app.get '/api/skills' do
            return json_error('skills_unavailable', 'Skills unavailable', status_code: 503) unless skills_registry_available?

            skills = Legion::LLM::Skills::Registry.all.map { |s| skill_descriptor(s) }
            json_response(skills)
          end
        end

        def self.register_show(app)
          app.get '/api/skills/:namespace/:name' do
            return json_error('skills_unavailable', 'Skills unavailable', status_code: 503) unless skills_registry_available?

            key   = "#{params[:namespace]}:#{params[:name]}"
            skill = Legion::LLM::Skills::Registry.find(key)
            return json_error('not_found', "Skill #{key} not found", status_code: 404) unless skill

            json_response(skill_descriptor(skill).merge(steps: skill.steps))
          end
        end

        def self.register_invoke(app)
          app.post '/api/skills/invoke' do
            return json_error('skills_unavailable', 'Skills unavailable', status_code: 503) unless skills_registry_available?

            body       = parse_request_body
            skill_name = body[:skill_name]
            return json_error('unprocessable', 'skill_name required', status_code: 422) if skill_name.nil? || skill_name.empty?

            skill_class = Legion::LLM::Skills::Registry.find(skill_name)
            return json_error('not_found', "Skill #{skill_name} not found", status_code: 404) unless skill_class

            conv_id = body[:conversation_id] || "conv_#{SecureRandom.hex(8)}"
            begin
              Legion::LLM::ConversationStore.set_skill_state(conv_id, skill_key: skill_name, resume_at: 0)
              require 'legion/llm/inference' unless defined?(Legion::LLM::Inference::Request) &&
                                                    defined?(Legion::LLM::Inference::Executor)

              req = Legion::LLM::Inference::Request.build(
                messages:        [{ role: :user, content: body[:initial_message] || 'start skill' }],
                conversation_id: conv_id,
                metadata:        (body[:metadata].is_a?(Hash) ? body[:metadata] : {}).merge(skill_invoke: true),
                stream:          false
              )
              result = Legion::LLM::Inference::Executor.new(req).call
              json_response({ conversation_id: conv_id, content: result.message[:content],
                              skill_name: skill_name })
            rescue StandardError => e
              Legion::LLM::ConversationStore.clear_skill_state(conv_id)
              json_error('internal_error', e.message, status_code: 500)
            end
          end
        end

        def self.register_cancel(app)
          app.delete '/api/skills/active/:conversation_id' do
            conv_id = params[:conversation_id]
            if defined?(Legion::LLM::ConversationStore)
              state = Legion::LLM::ConversationStore.cancel_skill!(conv_id)
              if state && defined?(Legion::Events)
                Legion::Events.emit('skill.cancelled', conversation_id: conv_id,
                                                       skill_name:      state[:skill_key])
              end
            end
            status 204
          end
        end

        private_class_method :register_list, :register_show, :register_invoke, :register_cancel
      end
    end
  end
end
