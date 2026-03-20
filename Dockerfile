# Build stage
FROM ruby:3.4-slim AS builder
WORKDIR /app
RUN apt-get update && \
    apt-get install -y --no-install-recommends build-essential libpq-dev git && \
    rm -rf /var/lib/apt/lists/*
COPY Gemfile Gemfile.lock ./
RUN bundle config set --local deployment true && \
    bundle config set --local without 'development test' && \
    bundle install --jobs 4 --retry 3
COPY . .

# Runtime stage
FROM ruby:3.4-slim AS runtime
RUN apt-get update && \
    apt-get install -y --no-install-recommends libpq5 curl && \
    rm -rf /var/lib/apt/lists/* && \
    groupadd -r legion && useradd -r -g legion -d /app -s /sbin/nologin legion
WORKDIR /app
COPY --from=builder --chown=legion:legion /app /app
USER legion
EXPOSE 4567
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD curl -sf http://localhost:4567/api/health || exit 1
ENTRYPOINT ["bundle", "exec"]
CMD ["legion", "start"]
