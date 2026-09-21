# ============================================
# Recon Framework - Multi-Stage Dockerfile
# Production Hardened & Minimal Attack Surface
# ============================================

# Stage 1: Build & install pinned reconnaissance tool binaries
FROM golang:1.23-alpine AS builder

# Install build prerequisites
RUN apk add --no-cache git make gcc musl-dev libpcap-dev

# Compile pinned versions of required reconnaissance tools
ENV CGO_ENABLED=1
RUN go install -v github.com/projectdiscovery/subfinder/v2/cmd/subfinder@v2.6.8 && \
    go install -v github.com/tomnomnom/assetfinder@v0.1.1 && \
    go install -v github.com/projectdiscovery/dnsx/cmd/dnsx@v1.2.1 && \
    go install -v github.com/projectdiscovery/naabu/v2/cmd/naabu@v2.3.1 && \
    go install -v github.com/projectdiscovery/httpx/cmd/httpx@v1.6.8 && \
    go install -v github.com/projectdiscovery/katana/cmd/katana@v1.1.0 && \
    go install -v github.com/projectdiscovery/nuclei/v3/cmd/nuclei@v3.3.2

# Stage 2: Minimal, secure runtime container
FROM alpine:3.20

LABEL maintainer="Akashdeep Singh" \
      description="Production-hardened Recon Framework reconnaissance engine" \
      version="1.3.0"

# Install core runtime dependencies (zero unnecessary packages)
RUN apk add --no-cache \
    bash \
    coreutils \
    jq \
    curl \
    bind-tools \
    ca-certificates \
    libpcap \
    libcap

# Copy compiled binaries from builder stage
COPY --from=builder /go/bin/subfinder /usr/local/bin/subfinder
COPY --from=builder /go/bin/assetfinder /usr/local/bin/assetfinder
COPY --from=builder /go/bin/dnsx /usr/local/bin/dnsx
COPY --from=builder /go/bin/naabu /usr/local/bin/naabu
COPY --from=builder /go/bin/httpx /usr/local/bin/httpx
COPY --from=builder /go/bin/katana /usr/local/bin/katana
COPY --from=builder /go/bin/nuclei /usr/local/bin/nuclei

# Grant raw packet capture capability to Naabu for non-root scanning
RUN setcap cap_net_raw,cap_net_bind_service=+ep /usr/local/bin/naabu 2>/dev/null || true

# Create dedicated non-root service user and group
RUN addgroup -g 10001 recon && \
    adduser -u 10001 -G recon -h /home/recon -D recon

# Set up application workspace
WORKDIR /app

# Copy application scripts, configurations, and data models
COPY recon.sh config.sh install.sh VERSION /app/
COPY lib/ /app/lib/
COPY schemas/ /app/schemas/

# Create output directory and configure strict unprivileged permissions
RUN mkdir -p /app/output /home/recon/.config && \
    chmod 755 /app/recon.sh /app/config.sh /app/install.sh /app/lib/*.sh && \
    chown -R recon:recon /app /home/recon

# Switch to unprivileged user
USER 10001:10001

# Declare output storage volume
VOLUME ["/app/output"]

# Environment defaults
ENV OUTPUT_DIR=/app/output \
    HOME=/home/recon \
    TERM=xterm-256color

# Entrypoint to Recon Framework controller
ENTRYPOINT ["/app/recon.sh"]
CMD ["--help"]
