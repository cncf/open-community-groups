# Build server
FROM rust:1-alpine3.22 AS builder
RUN apk --no-cache add musl-dev perl make
RUN wget -O /usr/local/bin/tailwindcss https://github.com/tailwindlabs/tailwindcss/releases/download/v4.1.10/tailwindcss-linux-x64-musl
RUN chmod +x /usr/local/bin/tailwindcss
WORKDIR /ocg
COPY Cargo.* ./
COPY ocg-server ocg-server
WORKDIR /ocg/ocg-server
RUN cargo build --release

# Final stage
FROM alpine:3.22.2
RUN apk --no-cache add ca-certificates && addgroup -S ocg && adduser -S ocg -G ocg
USER ocg
WORKDIR /home/ocg
COPY --from=builder /ocg/target/release/ocg-server /usr/local/bin
