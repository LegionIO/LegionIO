# frozen_string_literal: true

module Legion
  module Guardrails
    module EmbeddingSimilarity
      class << self
        def check(input, safe_embeddings:, threshold: 0.3)
          return { safe: true, reason: 'no embeddings service' } unless defined?(Legion::LLM) && Legion::LLM.respond_to?(:embed)

          input_vec = Legion::LLM.embed(input)
          return { safe: true, reason: 'embedding failed' } unless input_vec

          min_dist = safe_embeddings.map { |se| cosine_distance(input_vec, se) }.min || 1.0
          safe = min_dist <= threshold
          if !safe && defined?(Legion::Logging)
            Legion::Logging.warn "[Guardrails] EmbeddingSimilarity rejected input: distance=#{min_dist.round(4)} threshold=#{threshold}"
          end
          { safe: safe, distance: min_dist.round(4), threshold: threshold }
        end

        def cosine_distance(vec_a, vec_b)
          return 1.0 if vec_a.nil? || vec_b.nil? || vec_a.empty? || vec_b.empty?

          dot = vec_a.zip(vec_b).sum { |x, y| (x || 0) * (y || 0) }
          mag_a = Math.sqrt(vec_a.sum { |x| x**2 })
          mag_b = Math.sqrt(vec_b.sum { |x| x**2 })
          return 1.0 if mag_a.zero? || mag_b.zero?

          1.0 - (dot / (mag_a * mag_b))
        end
      end
    end

    module RAGRelevancy
      class << self
        def check(question:, context:, answer:, threshold: 3)
          return { relevant: true, reason: 'no LLM' } unless defined?(Legion::LLM)

          result = Legion::LLM.chat_single(
            messages: [
              { role:    'system',
                content: 'Rate 1-5 how relevant the answer is to the question given the context. Reply ONLY with the number.' },
              { role: 'user', content: "Question: #{question}\nContext: #{context}\nAnswer: #{answer}" }
            ]
          )
          score = result[:content].to_s.strip.to_i
          relevant = score >= threshold
          Legion::Logging.warn "[Guardrails] RAGRelevancy rejected answer: score=#{score} threshold=#{threshold}" if !relevant && defined?(Legion::Logging)
          { relevant: relevant, score: score, threshold: threshold }
        rescue StandardError => e
          Legion::Logging.warn "Guardrails::RAGRelevancy#check failed: #{e.message}" if defined?(Legion::Logging)
          { relevant: true, reason: 'check failed' }
        end
      end
    end
  end
end
