# Build tern
FROM golang:1.26.4-alpine3.24 AS tern
RUN apk --no-cache add git
RUN go install github.com/jackc/tern@latest

# Build final image
FROM alpine:3.24.1
RUN addgroup -S ocg && adduser -S ocg -G ocg
USER ocg
WORKDIR /home/ocg
COPY --from=tern /go/bin/tern /usr/local/bin
COPY database/migrations .
