# Stage 1: Build the Go application using the Makefile
FROM golang:1.23-alpine AS builder
WORKDIR /app
# Install make and necessary build tools
RUN apk add --no-cache make gcc musl-dev
COPY birdImage/ .
COPY birdImage/Makefile Makefile
RUN go mod tidy
RUN make birdImage  # This runs the 'birdImage' target in the Makefile

# Stage 2: Create a minimal image to run the Go app
FROM alpine:latest
WORKDIR /app
COPY --from=builder /app/getBirdImage .
EXPOSE 4200
CMD ["./getBirdImage"]
