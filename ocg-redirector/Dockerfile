# Build redirector
FROM rust:1.96.1-alpine3.24 AS builder
RUN apk --no-cache add musl-dev perl make
WORKDIR /ocg
COPY Cargo.* ./
COPY ocg-redirector ocg-redirector
COPY ocg-server ocg-server
WORKDIR /ocg/ocg-redirector
RUN cargo build --locked --release

# Final stage
FROM alpine:3.24.1
RUN apk --no-cache add ca-certificates && addgroup -S ocg && adduser -S ocg -G ocg
USER ocg
WORKDIR /home/ocg
COPY --from=builder /ocg/target/release/ocg-redirector /usr/local/bin
