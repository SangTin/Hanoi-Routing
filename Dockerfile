# syntax=docker/dockerfile:1.7

FROM rust:bookworm AS builder
WORKDIR /workspace

RUN set -eux; \
    for i in 1 2 3 4 5; do \
      rustup toolchain install nightly --profile minimal && break; \
      if [ "$i" -eq 5 ]; then exit 1; fi; \
      sleep 5; \
    done; \
    rustup default nightly

COPY CCH-Hanoi /workspace/CCH-Hanoi
COPY rust_road_router /workspace/rust_road_router

# Build-only compatibility patch for newer nightly:
# usize::is_multiple_of now expects an unborrowed RHS.
RUN sed -i 's/is_multiple_of(&align_of::<T>())/is_multiple_of(align_of::<T>())/' \
    /workspace/rust_road_router/engine/src/util.rs

RUN cargo +nightly build --release \
    --manifest-path /workspace/CCH-Hanoi/Cargo.toml \
    -p hanoi-server \
    --bin hanoi_server

FROM debian:bookworm-slim AS runtime
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    libgcc-s1 \
    libstdc++6 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=builder /workspace/CCH-Hanoi/target/release/hanoi_server /usr/local/bin/hanoi_server
COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENV GRAPH_DIR=/data/graph
ENV ORIGINAL_GRAPH_DIR=
ENV QUERY_PORT=8080
ENV CUSTOMIZE_PORT=9080
ENV LINE_GRAPH=false
ENV LOG_FORMAT=pretty
ENV RUST_LOG=info

EXPOSE 8080 9080
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
