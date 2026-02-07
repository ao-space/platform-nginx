#!/bin/bash

# Simplified nginx entrypoint for single-machine deployment
# Requires:
#   - USER_DOMAIN: Base domain (e.g., example.com)
#   - NGINX_BIND_HTTP: HTTP port (default 80)
#   - NGINX_BIND_HTTPS: HTTPS port (default 443)
#   - PROXY_HOST: Platform proxy hostname (default proxy)
#   - SERVICES_HOST: Platform services hostname (default services)
#   - RATE_LIMIT_RPS: Requests per second limit (default 10)
#   - ENABLE_HSTS: Enable HSTS header (default true)

set -e

# Create SSL directory
mkdir -p /etc/nginx/crt/

# Generate self-signed certificate for fallback
openssl genrsa -out /etc/nginx/crt/server.key 2048 2>/dev/null
openssl req -new -x509 -days 3650 -key /etc/nginx/crt/server.key \
    -out /etc/nginx/crt/server.crt \
    -subj "/C=CN/ST=AO/L=Space/O=AO.Space/OU=Platform/CN=localhost" 2>/dev/null

# Check if custom SSL certificate exists
if [ -f /etc/nginx/ssl/tls.crt ] && [ -f /etc/nginx/ssl/tls.key ]; then
    echo "Using custom SSL certificate"
    SSL_CERT="/etc/nginx/ssl/tls.crt"
    SSL_KEY="/etc/nginx/ssl/tls.key"
else
    echo "Warning: Using self-signed certificate. For production, mount your certificate to /etc/nginx/ssl/"
    SSL_CERT="/etc/nginx/crt/server.crt"
    SSL_KEY="/etc/nginx/crt/server.key"
fi

# Default values
NGINX_BIND_HTTP=${NGINX_BIND_HTTP:-80}
NGINX_BIND_HTTPS=${NGINX_BIND_HTTPS:-443}
PROXY_HOST=${PROXY_HOST:-proxy}
SERVICES_HOST=${SERVICES_HOST:-services}
RATE_LIMIT_RPS=${RATE_LIMIT_RPS:-10}
ENABLE_HSTS=${ENABLE_HSTS:-true}

# HSTS header (if enabled)
if [ "$ENABLE_HSTS" = "true" ]; then
    HSTS_HEADER="add_header Strict-Transport-Security \"max-age=31536000; includeSubDomains\" always;"
else
    HSTS_HEADER=""
fi

# Create main nginx configuration with security settings
cat << EOF > /etc/nginx/nginx.conf
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
    use epoll;
    multi_accept on;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    # Logging format
    log_format main '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                    '\$status \$body_bytes_sent "\$http_referer" '
                    '"\$http_user_agent" "\$http_x_forwarded_for"';
    access_log /var/log/nginx/access.log main;

    # Performance
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;

    # Security: Hide server version
    server_tokens off;

    # Security: Rate limiting zone
    limit_req_zone \$binary_remote_addr zone=api_limit:10m rate=${RATE_LIMIT_RPS}r/s;
    limit_req_zone \$binary_remote_addr zone=login_limit:10m rate=5r/m;
    limit_conn_zone \$binary_remote_addr zone=conn_limit:10m;

    # Security: Request size limits
    client_max_body_size 1G;
    client_body_buffer_size 128k;
    client_header_buffer_size 1k;
    large_client_header_buffers 4 16k;

    # Security: Timeouts
    client_body_timeout 60s;
    client_header_timeout 60s;
    send_timeout 60s;

    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css text/xml application/json application/javascript application/xml;

    # Include server configs
    include /etc/nginx/conf.d/*.conf;
}
EOF

# Create default server (catch-all for undefined hosts)
cat << EOF > /etc/nginx/conf.d/00-default.conf
server {
    listen ${NGINX_BIND_HTTP} default_server;
    listen ${NGINX_BIND_HTTPS} ssl default_server;
    server_name _;

    ssl_certificate ${SSL_CERT};
    ssl_certificate_key ${SSL_KEY};

    # Health check endpoint
    location /nginx_status {
        return 200 "OK";
        add_header Content-Type text/plain;
    }

    # Block all other requests
    location / {
        return 444;
    }
}
EOF

# Create platform API server (services.domain.com and domain.com)
cat << EOF > /etc/nginx/conf.d/10-platform.conf
# HTTP to HTTPS redirect for platform
server {
    listen ${NGINX_BIND_HTTP};
    server_name ${USER_DOMAIN} services.${USER_DOMAIN} platform.${USER_DOMAIN};

    location / {
        return 301 https://\$http_host\$request_uri;
    }
}

# Platform API server
server {
    listen ${NGINX_BIND_HTTPS} ssl http2;
    server_name ${USER_DOMAIN} services.${USER_DOMAIN} platform.${USER_DOMAIN};

    # SSL Configuration
    ssl_certificate ${SSL_CERT};
    ssl_certificate_key ${SSL_KEY};
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:50m;
    ssl_session_tickets off;

    # Security headers
    ${HSTS_HEADER}
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    # CORS headers
    add_header Access-Control-Allow-Origin '\$http_origin' always;
    add_header Access-Control-Allow-Credentials true always;
    add_header Access-Control-Allow-Methods 'GET, PUT, POST, DELETE, PATCH, OPTIONS' always;
    add_header Access-Control-Allow-Headers 'DNT,X-CustomHeader,Keep-Alive,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Authorization,Request-Id' always;
    add_header Access-Control-Expose-Headers '*' always;
    add_header Access-Control-Max-Age 1728000 always;

    # Rate limiting
    limit_req zone=api_limit burst=20 nodelay;
    limit_conn conn_limit 50;

    location / {
        if (\$request_method = 'OPTIONS') {
            return 204;
        }

        proxy_pass http://${SERVICES_HOST}:8080;
        proxy_http_version 1.1;

        client_max_body_size 0;
        proxy_read_timeout 300;
        proxy_connect_timeout 300;
        proxy_redirect off;

        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Host \$http_host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }

    # Block sensitive paths
    location ~ /\.(git|svn|htaccess|env) {
        deny all;
        return 404;
    }
}
EOF

# Create user space server (*.domain.com)
cat << EOF > /etc/nginx/conf.d/20-spaces.conf
# HTTP to HTTPS redirect for user spaces
server {
    listen ${NGINX_BIND_HTTP};
    server_name *.${USER_DOMAIN};

    location / {
        return 301 https://\$http_host\$request_uri;
    }
}

# User space server (wildcard subdomain)
server {
    listen ${NGINX_BIND_HTTPS} ssl http2;
    server_name *.${USER_DOMAIN};

    # SSL Configuration
    ssl_certificate ${SSL_CERT};
    ssl_certificate_key ${SSL_KEY};
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:50m;
    ssl_session_tickets off;

    # Security headers
    ${HSTS_HEADER}
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    # CORS headers
    add_header Access-Control-Allow-Origin '\$http_origin' always;
    add_header Access-Control-Allow-Credentials true always;
    add_header Access-Control-Allow-Methods 'GET, PUT, POST, DELETE, PATCH, OPTIONS' always;
    add_header Access-Control-Allow-Headers 'DNT,X-CustomHeader,Keep-Alive,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Authorization,Request-Id' always;
    add_header Access-Control-Expose-Headers '*' always;
    add_header Access-Control-Max-Age 1728000 always;

    # Rate limiting
    limit_req zone=api_limit burst=50 nodelay;
    limit_conn conn_limit 100;

    # WebDAV redirect
    if (\$request_method = 'PROPFIND') {
        return 302 https://\$http_host/space/dav/;
    }

    location / {
        if (\$request_method = 'OPTIONS') {
            return 204;
        }

        proxy_pass http://${PROXY_HOST}:80;
        proxy_http_version 1.1;

        client_max_body_size 0;
        proxy_read_timeout 85;
        proxy_connect_timeout 85;
        proxy_redirect off;

        proxy_set_header Connection close;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Host \$http_host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }

    # Block sensitive paths
    location ~ /\.(git|svn|htaccess|env) {
        deny all;
        return 404;
    }
}
EOF

echo "Nginx configuration generated for domain: ${USER_DOMAIN}"
echo "  - Platform API: https://${USER_DOMAIN}, https://platform.${USER_DOMAIN}"
echo "  - User spaces: https://*.${USER_DOMAIN}"
echo "  - Rate limit: ${RATE_LIMIT_RPS} req/s"
echo "  - HSTS enabled: ${ENABLE_HSTS}"

exec nginx -g "daemon off;"
