# Build tern
FROM golang:1.25.4-alpine3.22 AS tern
RUN apk --no-cache add git
RUN go install github.com/jackc/tern@latest

# Build final image
FROM alpine:3.23.2
RUN addgroup -S ocg && adduser -S ocg -G ocg
USER ocg
WORKDIR /home/ocg
COPY --from=tern /go/bin/tern /usr/local/bin
COPY database/migrations .
