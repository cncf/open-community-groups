# Build redirector
FROM rust:1.95.0-alpine3.23 AS builder
RUN apk --no-cache add musl-dev perl make
WORKDIR /ocg
COPY Cargo.* ./
COPY ocg-redirector ocg-redirector
COPY ocg-server/build.rs ocg-server/build.rs
COPY ocg-server/Cargo.* ocg-server
COPY ocg-server/src/main.rs ocg-server/src/main.rs
WORKDIR /ocg/ocg-redirector
RUN cargo build --locked --release

# Final stage
FROM alpine:3.23.4
RUN apk --no-cache add ca-certificates && addgroup -S ocg && adduser -S ocg -G ocg
USER ocg
WORKDIR /home/ocg
COPY --from=builder /ocg/target/release/ocg-redirector /usr/local/bin
