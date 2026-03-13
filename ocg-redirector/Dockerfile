# Build redirector
FROM rust:1-alpine3.23 AS builder
RUN apk --no-cache add musl-dev perl make
WORKDIR /ocg
COPY Cargo.* ./
COPY ocg-redirector ocg-redirector
COPY ocg-server/Cargo.toml ocg-server/Cargo.toml
WORKDIR /ocg/ocg-redirector
RUN cargo build --release

# Final stage
FROM alpine:3.23.3
RUN apk --no-cache add ca-certificates && addgroup -S ocg && adduser -S ocg -G ocg
USER ocg
WORKDIR /home/ocg
COPY --from=builder /ocg/target/release/ocg-redirector /usr/local/bin
