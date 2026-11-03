# =========================
# BUILDER
# =========================
FROM ruby:3.4.4-slim AS builder

ENV RAILS_ENV=production \
    NODE_ENV=production \
    BUNDLE_WITHOUT="development:test" \
    BUNDLE_PATH=/bundle

# System deps
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    git \
    curl \
    ca-certificates \
    pkg-config \
    libpq-dev \
    python3 \
    libvips \
  && rm -rf /var/lib/apt/lists/*

# Node 24 (package.json declara engines: node 24.x)
RUN curl -fsSL https://deb.nodesource.com/setup_24.x | bash - \
  && apt-get update && apt-get install -y --no-install-recommends nodejs \
  && rm -rf /var/lib/apt/lists/*

# pnpm (via corepack)
RUN corepack enable && corepack prepare pnpm@latest --activate

WORKDIR /app

# Ruby deps
COPY Gemfile Gemfile.lock ./
RUN gem install bundler && bundle install

# JS deps
COPY package.json pnpm-lock.yaml ./

# 🔥 INSTALAÇÃO CORRETA (resolve Vite + Chart.js)
RUN rm -rf node_modules && \
    pnpm install --no-frozen-lockfile --shamefully-hoist

# App
COPY . .

# Build assets
ARG SECRET_KEY_BASE=dummy
# Heap do Node na precompilacao. O default de 4096 nao cabe em host apertado:
# o build concorre com o que ja estiver em execucao, e o OOM killer pode
# escolher outro processo em vez do build -- inclusive o banco. Passe
# --build-arg NODE_HEAP_MB=2048 nesses casos.
ARG NODE_HEAP_MB=4096

RUN export NODE_OPTIONS="--max-old-space-size=${NODE_HEAP_MB} --openssl-legacy-provider" && \
    SECRET_KEY_BASE=${SECRET_KEY_BASE} \
    RAILS_LOG_TO_STDOUT=enabled \
    bundle exec rails assets:precompile && \
    rm -rf node_modules tmp/cache


# =========================
# RUNTIME
# =========================
FROM ruby:3.4.4-slim

ENV RAILS_ENV=production \
    NODE_ENV=production \
    BUNDLE_WITHOUT="development:test" \
    BUNDLE_PATH=/bundle \
    RAILS_LOG_TO_STDOUT=true \
    RAILS_SERVE_STATIC_FILES=true

# Runtime deps
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq5 \
    libvips \
    postgresql-client \
    git \
    curl \
    ca-certificates \
  && curl -fsSL https://deb.nodesource.com/setup_24.x | bash - \
  && apt-get install -y --no-install-recommends nodejs \
  && rm -rf /var/lib/apt/lists/*

# pnpm também no runtime (pra debug futuro)
RUN corepack enable && corepack prepare pnpm@latest --activate

WORKDIR /app

COPY --from=builder /bundle /bundle
COPY --from=builder /app /app

EXPOSE 3000

# Sem -p: config/puma.rb ja faz `port ENV.fetch('PORT', 3000)`, entao cada stack
# escolhe a porta pela env PORT. Sem db:migrate: com o container servindo, migrar
# no boot deixa a stack indisponivel e faz web e worker migrarem em paralelo.
CMD ["bundle", "exec", "rails", "s", "-b", "0.0.0.0"]
