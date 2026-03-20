# frozen_string_literal: true

module Legion
  class API < Sinatra::Base
    module Routes
      module OrgChart
        def self.registered(app)
          app.helpers OrgChartHelpers
          app.get '/api/org-chart' do
            require_data!
            departments = build_org_chart
            json_response({ departments: departments })
          end
        end

        module OrgChartHelpers
          def build_org_chart
            extensions = Legion::Data::Model::Extension.all
            workers = Legion::Data::Model::DigitalWorker.all

            extensions.map do |ext|
              functions = Legion::Data::Model::Function.where(extension_id: ext.id).all
              {
                name:  ext.name,
                roles: functions.map do |func|
                  ext_workers = workers.select { |w| w.extension_name == ext.name }
                  {
                    name:    func.name,
                    workers: ext_workers.map { |w| { id: w.id, name: w.name, status: w.lifecycle_state } }
                  }
                end
              }
            end
          rescue StandardError
            []
          end
        end
      end
    end
  end
end
