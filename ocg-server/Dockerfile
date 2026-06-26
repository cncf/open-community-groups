# Build server
FROM rust:1.96.0-alpine3.23 AS builder
ARG OCG_COMMIT_SHA
ENV OCG_COMMIT_SHA=$OCG_COMMIT_SHA
ENV CARGO_HTTP_MULTIPLEXING=false
ENV CARGO_HTTP_TIMEOUT=120
ENV CARGO_NET_RETRY=10
RUN apk --no-cache add musl-dev perl make
RUN wget -O /usr/local/bin/tailwindcss https://github.com/tailwindlabs/tailwindcss/releases/download/v4.1.10/tailwindcss-linux-x64-musl
RUN chmod +x /usr/local/bin/tailwindcss
WORKDIR /ocg
COPY Cargo.* ./
COPY ocg-redirector/Cargo.* ocg-redirector
COPY docs docs
COPY ocg-server ocg-server
WORKDIR /ocg/ocg-server
RUN for attempt in 1 2 3; do \
      cargo build --locked --release && exit 0; \
      echo "cargo build failed; retrying in $((attempt * 10)) seconds" >&2; \
      sleep $((attempt * 10)); \
    done; \
    cargo build --locked --release

# Final stage
FROM alpine:3.23.5
RUN apk --no-cache add ca-certificates postgresql17-client && addgroup -S ocg && adduser -S ocg -G ocg
USER ocg
WORKDIR /home/ocg
COPY --from=builder /ocg/target/release/ocg-server /usr/local/bin
