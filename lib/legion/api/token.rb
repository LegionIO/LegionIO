# frozen_string_literal: true

module Legion
  class API < Sinatra::Base
    module Token
      def self.issue_worker_token(worker_id:, owner_msid:, ttl: 3600)
        Legion::Crypt::JWT.issue(
          { worker_id: worker_id, sub: owner_msid, scope: 'worker' },
          signing_key: signing_key,
          ttl:         ttl,
          issuer:      'legion'
        )
      end

      def self.issue_human_token(msid:, name: nil, roles: [], ttl: 28_800)
        Legion::Crypt::JWT.issue(
          { sub: msid, name: name, roles: roles, scope: 'human' },
          signing_key: signing_key,
          ttl:         ttl,
          issuer:      'legion'
        )
      end

      def self.signing_key
        return Legion::Crypt.cluster_secret if defined?(Legion::Crypt) && Legion::Crypt.respond_to?(:cluster_secret)

        raise 'no signing key available - Legion::Crypt not initialized'
      end
    end
  end
end
