# Stage 1: Build Flutter Web
FROM debian:bookworm-slim AS build

# Install build dependencies
RUN apt-get update && apt-get install -y \
    curl \
    git \
    unzip \
    xz-utils \
    zip \
    libglu1-mesa \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Install Flutter SDK
RUN wget https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.22.2-stable.tar.xz \
    && tar xf flutter_linux_3.22.2-stable.tar.xz -C /usr/local \
    && rm flutter_linux_3.22.2-stable.tar.xz

ENV PATH="/usr/local/flutter/bin:/usr/local/flutter/bin/cache/dart-sdk/bin:${PATH}"

# Pre-download Flutter development binaries
RUN flutter config --no-analytics
RUN flutter doctor

# Set up working directory
WORKDIR /app

# Copy dependency files first to cache them
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

# Copy all source files
COPY . .

# Build web release
RUN flutter build web --release

# Stage 2: Serve using Nginx
FROM nginx:alpine

# Install openssl to generate self-signed cert for default setup (so it doesn't fail to start)
RUN apk add --no-cache openssl && \
    mkdir -p /etc/nginx/ssl && \
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/nginx/ssl/nginx.key \
    -out /etc/nginx/ssl/nginx.crt \
    -subj "/C=US/ST=State/L=City/O=Organization/OU=Unit/CN=localhost"

# Copy built assets
COPY --from=build /app/build/web /usr/share/nginx/html

# Copy Nginx configuration
COPY nginx.prod.conf /etc/nginx/conf.d/default.conf

# Expose ports
EXPOSE 80
EXPOSE 443

CMD ["nginx", "-g", "daemon off;"]

