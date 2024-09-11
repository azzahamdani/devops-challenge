# Stage 1: Build the Go application using the Makefile
FROM golang:1.23-alpine AS builder
WORKDIR /app
# Install make and necessary build tools
RUN apk add --no-cache make gcc musl-dev
COPY bird/ .
COPY bird/Makefile Makefile
RUN go mod tidy
RUN make bird  # This runs the 'bird' target in the Makefile

# Stage 2: Create a minimal image to run the Go app
FROM alpine:latest
WORKDIR /app
COPY --from=builder /app/getBird .
EXPOSE 4201
CMD ["./getBird"]