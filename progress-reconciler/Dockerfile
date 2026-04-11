# Multi-stage Docker build for progress-reconciler
FROM golang:1.23-alpine AS builder

WORKDIR /build

# Copy go module files
COPY go.mod go.sum ./
RUN go mod download

# Copy source code
COPY . .

# Tidy modules and build binary
RUN go mod tidy && \
    CGO_ENABLED=0 GOOS=linux go build -o progress-reconciler \
    -ldflags="-w -s" \
    ./cmd/reconciler

# Final stage
FROM alpine:latest

RUN apk --no-cache add ca-certificates tzdata

WORKDIR /app

COPY --from=builder /build/progress-reconciler .

USER nobody:nobody

EXPOSE 8080

CMD ["./progress-reconciler"]