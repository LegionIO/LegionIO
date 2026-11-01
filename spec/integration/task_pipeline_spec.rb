# frozen_string_literal: true

require 'spec_helper'
require 'open3'
require 'rbconfig'
require 'tmpdir'

RSpec.describe 'Durable Conditioner and Transformer task chaining' do
  it 'runs framework stages without consuming destination identities across one-to-one, fan-out, and rejection paths' do
    Dir.mktmpdir('legion-chain-spec') do |directory|
      result_path = File.join(directory, 'results.json')
      environment = {
        'HOME' => directory, 'LEGION_DNS_BOOTSTRAP' => 'false',
        'RABBITMQ_URL' => ENV.fetch('RABBITMQ_URL', 'amqp://guest:guest@127.0.0.1:5672/%2F')
      }
      output, status = Open3.capture2e(environment, RbConfig.ruby, File.join(__dir__, 'support/task_pipeline.rb'), result_path)
      expect(status.success?).to be(true), output
      reports = Legion::JSON.load(File.read(result_path))

      expect(reports.map { |report| report[:effects].map { |effect| effect[:value] }.sort }).to eq([[42], [43, 43], [44, 45], []])
      expect(reports.map { |report| report[:conditioner_completions] }).to eq([1, 2, 1, 0])
      expect(reports.map { |report| report[:tasks].length }).to eq([1, 2, 3, 1])

      reports.each do |report|
        expect(report[:root][:status]).to eq('task.completed')
        root_id = report[:root][:id]
        task_ids = [root_id] + report[:tasks].map { |task| task[:id] }
        report[:tasks].each do |task|
          expect(task[:master_id]).to eq(root_id)
          expect(task_ids).to include(task[:parent_id])
          expect(task[:parent_id]).not_to eq(task[:id])
        end
        report[:effects].each do |effect|
          task = report[:tasks].find { |row| row[:id] == effect[:task_id] }
          expect(task).to include(status: 'task.completed', attempt_count: 1)
        end
      end
      expect(reports.last[:tasks]).to contain_exactly(include(status: 'task.skipped', attempt_count: 0))
    end
  end
end
