# Build server
FROM rust:1-alpine3.21 AS builder
RUN apk --no-cache add musl-dev perl make
WORKDIR /ocg
COPY Cargo.* ./
COPY ocg-server ocg-server
WORKDIR /ocg/ocg-server
RUN cargo build --release

# Final stage
FROM alpine:3.21.0
RUN apk --no-cache add ca-certificates && addgroup -S ocg && adduser -S ocg -G ocg
USER ocg
WORKDIR /home/ocg
COPY --from=builder /ocg/target/release/ocg-server /usr/local/bin
