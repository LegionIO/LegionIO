# frozen_string_literal: true

require 'json'
require 'thor'

module Legion
  module CLI
    class MindGrowth < Thor
      def self.exit_on_failure?
        true
      end

      class_option :json,     type: :boolean, default: false, desc: 'Output as JSON'
      class_option :no_color, type: :boolean, default: false, desc: 'Disable color output'
      class_option :verbose,  type: :boolean, default: false, aliases: ['-V'], desc: 'Verbose logging'

      desc 'status', 'Show mind-growth cycle status'
      def status
        require_mind_growth!
        result = mind_growth_client.growth_status
        out = formatter
        if options[:json]
          out.json(result)
        else
          out.header('Mind-Growth Status')
          out.spacer
          out.detail(result)
        end
      end

      desc 'propose', 'Propose a new cognitive concept'
      option :category,    type: :string, desc: 'Cognitive category'
      option :description, type: :string, desc: 'Concept description'
      option :name,        type: :string, desc: 'Concept name'
      def propose
        require_mind_growth!
        result = mind_growth_client.propose_concept(
          category:    options[:category]&.to_sym,
          description: options[:description],
          name:        options[:name]
        )
        out = formatter
        if options[:json]
          out.json(result)
        elsif result[:success]
          out.success("Proposal created: #{result.dig(:proposal, :id)}")
        else
          out.warn("Proposal failed: #{result[:error]}")
        end
      end

      desc 'approve ID', 'Approve a proposal'
      def approve(proposal_id)
        require_mind_growth!
        result = mind_growth_client.evaluate_proposal(proposal_id: proposal_id)
        out = formatter
        if options[:json]
          out.json(result)
        elsif result[:success]
          status_label = result[:approved] ? 'approved' : 'rejected'
          out.success("Proposal #{proposal_id[0, 8]} #{status_label}")
        else
          out.warn("Evaluation failed: #{result[:error]}")
        end
      end

      desc 'reject ID', 'Reject a proposal'
      map 'reject' => :reject_proposal
      option :reason, type: :string, desc: 'Rejection reason'
      def reject_proposal(proposal_id)
        require_mind_growth!
        proposal = Legion::Extensions::MindGrowth::Runners::Proposer.get_proposal_object(proposal_id)
        out = formatter
        if proposal.nil?
          out.warn("Proposal #{proposal_id[0, 8]} not found")
          return
        end
        proposal.transition!(:rejected)
        if options[:json]
          out.json({ success: true, proposal_id: proposal_id, status: 'rejected',
                     reason: options[:reason] })
        else
          out.success("Proposal #{proposal_id[0, 8]} rejected")
        end
      rescue ArgumentError => e
        formatter.warn("Cannot reject: #{e.message}")
      end

      desc 'build ID', 'Force-build an approved proposal'
      def build(proposal_id)
        require_mind_growth!
        result = mind_growth_client.build_extension(proposal_id: proposal_id)
        out = formatter
        if options[:json]
          out.json(result)
        elsif result[:success]
          out.success("Build pipeline started for #{proposal_id[0, 8]}")
          out.detail(result[:pipeline]) if result[:pipeline]
        else
          out.warn("Build failed: #{result[:error]}")
        end
      end

      desc 'proposals', 'List proposals'
      option :status, type: :string, desc: 'Filter by status'
      option :limit,  type: :numeric, default: 20, desc: 'Max results'
      def proposals
        require_mind_growth!
        result = mind_growth_client.list_proposals(
          status: options[:status]&.to_sym,
          limit:  options[:limit]
        )
        out = formatter
        if options[:json]
          out.json(result)
        else
          rows = (result[:proposals] || []).map do |p|
            [p[:id].to_s[0, 8], p[:name].to_s, p[:category].to_s,
             p[:status].to_s, p[:created_at].to_s]
          end
          if rows.empty?
            out.warn('No proposals found')
          else
            out.table(%w[id name category status created_at], rows)
          end
        end
      end

      desc 'profile', 'Show cognitive architecture profile'
      def profile
        require_mind_growth!
        result = mind_growth_client.cognitive_profile
        out = formatter
        if options[:json]
          out.json(result)
        else
          out.header('Cognitive Architecture Profile')
          out.spacer
          out.detail({ total_extensions: result[:total_extensions],
                       overall_coverage: result[:overall_coverage] })
          out.spacer
          coverage = result[:model_coverage] || {}
          rows = coverage.map { |model, data| [model.to_s, data[:coverage].to_s, data[:missing].to_s] }
          out.table(%w[model coverage missing], rows) unless rows.empty?
        end
      end

      desc 'health', 'Show extension health and fitness scores'
      def health
        require_mind_growth!
        result = mind_growth_client.validate_fitness(extensions: [])
        out = formatter
        if options[:json]
          out.json(result)
        else
          out.header('Extension Fitness')
          out.spacer
          ranked = result[:ranked] || []
          if ranked.empty?
            out.warn('No extensions to score')
          else
            rows = ranked.map { |e| [e[:name].to_s, format('%.3f', e[:fitness].to_f)] }
            out.table(%w[extension fitness], rows)
          end
        end
      end

      desc 'report', 'Generate retrospective report'
      def report
        require_mind_growth!
        result = mind_growth_client.session_report
        out = formatter
        if options[:json]
          out.json(result)
        else
          out.header('Mind-Growth Report')
          out.spacer
          out.detail(result)
        end
      end

      desc 'history', 'Show recent proposal history'
      option :limit, type: :numeric, default: 50, desc: 'Max results'
      def history
        require_mind_growth!
        result = mind_growth_client.list_proposals(limit: options[:limit])
        out = formatter
        if options[:json]
          out.json(result)
        else
          rows = (result[:proposals] || []).map do |p|
            [p[:id].to_s[0, 8], p[:name].to_s, p[:category].to_s,
             p[:status].to_s, p[:created_at].to_s]
          end
          if rows.empty?
            out.warn('No proposals found')
          else
            out.table(%w[id name category status created_at], rows)
          end
        end
      end

      no_commands do
        def formatter
          @formatter ||= Output::Formatter.new(
            json:  options[:json],
            color: !options[:no_color]
          )
        end

        def require_mind_growth!
          return if defined?(Legion::Extensions::MindGrowth::Client)

          raise CLI::Error, 'lex-mind-growth extension is not loaded. Install and enable it first.'
        end

        def mind_growth_client
          @mind_growth_client ||= Legion::Extensions::MindGrowth::Client.new
        end
      end
    end
  end
end
