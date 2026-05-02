# ── Stage 1: Build Rust server ──
# Uses latest stable Rust — dependencies (actix-web, time) require 1.88+
FROM rust:slim-bookworm AS builder

RUN apt-get update && apt-get install -y --no-install-recommends pkg-config && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Cache dependencies first
COPY Cargo.toml Cargo.lock* ./
RUN mkdir src && echo "fn main() {}" > src/main.rs \
    && cargo build --release 2>&1 \
    && rm -rf src

# Build actual source
COPY src/ src/
RUN touch src/main.rs && cargo build --release

# ── Stage 2: Minimal runtime image ──
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy server binary
COPY --from=builder /app/target/release/the-yut-server .

# Copy pre-built Godot web export
COPY static/ ./static/

# Default port — override with PORT env var
ENV PORT=9001
ENV HOST=0.0.0.0
ENV RUST_LOG=info

EXPOSE 9001

CMD ["./the-yut-server"]
