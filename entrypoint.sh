#!/bin/bash

mkdir -p /etc/nginx/crt/

openssl genrsa -out /etc/nginx/crt/server.key 2048
openssl req -new -x509 -days 3650 -key /etc/nginx/crt/server.key -out /etc/nginx/crt/server.crt -subj "/C=CN/ST=nginx/L=nginx/O=nginx/OU=nginx/CN=localhost/CN=127.0.0.1"

cat << EOF > /etc/nginx/conf.d/default.conf
server {
    listen ${NGINX_BIND_HTTP};
    server_name  _;
    server_tokens off;

    location /nginx_status {
        return 200;
    }

    location / {
        return 500;
    }
}

server {
    listen ${NGINX_BIND_HTTPS} ssl;
    server_name  _;
    server_tokens off;

    ssl_certificate /etc/nginx/crt/server.crt;
    ssl_certificate_key /etc/nginx/crt/server.key;

    location / {
        return 500;
    }
}

EOF

cat << EOF > /etc/nginx/conf.d/${USER_DOMAIN}.conf
server {
    listen ${NGINX_BIND_HTTP};
    server_name ${USER_DOMAIN} *.${USER_DOMAIN};
    server_tokens off;

    location / {
        return 301 https://\$http_host\$request_uri;
    }
}

server {
    listen ${NGINX_BIND_HTTPS} ssl;
    server_name ${USER_DOMAIN} services.${USER_DOMAIN};
    server_tokens off;

    ssl_certificate /etc/nginx/ssl/tls.crt;
    ssl_certificate_key /etc/nginx/ssl/tls.key;

    location / {

        add_header Access-Control-Allow-Origin '$http_origin' always;
        add_header Access-Control-Allow-Credentials true always;
        add_header Access-Control-Allow-Methods 'GET, PUT, POST, DELETE, PATCH, OPTIONS';
        add_header Access-Control-Expose-Headers '*';
        add_header Access-Control-Allow-Headers 'DNT,X-CustomHeader,Keep-Alive,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Authorization,request-Id';
        add_header Access-Control-Max-Age '1728000';
        if (\$request_method = 'OPTIONS') {
            return 204;
        } 

        proxy_pass http://127.0.0.1:${SERVICES_LOCAL_BIND};

        client_max_body_size 0;
        proxy_read_timeout 300;
        proxy_connect_timeout 300;
        proxy_redirect     off;

        proxy_set_header   X-Forwarded-Proto \$scheme;
        proxy_set_header   Host              \$http_host;
        proxy_set_header   X-Real-IP         \$remote_addr;
        proxy_set_header   X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header   access_token      \$http_access_token;

    }
}

server {
    listen ${NGINX_BIND_HTTPS} ssl;
    server_name *.res.${USER_DOMAIN} *.update.${USER_DOMAIN} *.download.${USER_DOMAIN} *.push.${USER_DOMAIN};
    server_tokens off;

    ssl_certificate /etc/nginx/ssl/tls.crt;
    ssl_certificate_key /etc/nginx/ssl/tls.key;

    if ( \$host ~* (.*)\.(.*)\.(.*)\.(.*)) {
        set \$real_domain \$1.\$3.\$4;
      }

    location / {

        if (\$request_method = 'PROPFIND') {
            return 302 https://\$http_host/space/dav/;
        }

        add_header Access-Control-Allow-Origin '$http_origin' always;
        add_header Access-Control-Allow-Credentials true always;
        add_header Access-Control-Allow-Methods 'GET, PUT, POST, DELETE, PATCH, OPTIONS';
        add_header Access-Control-Expose-Headers '*';
        add_header Access-Control-Allow-Headers 'DNT,X-CustomHeader,Keep-Alive,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Authorization,request-Id';
        add_header Access-Control-Max-Age '1728000';
        if (\$request_method = 'OPTIONS') {
            return 204;
        } 

        proxy_pass http://127.0.0.1:${PROXY_LOCAL_BIND};

        client_max_body_size 0;
        proxy_read_timeout 85;
        proxy_connect_timeout 85;
        proxy_redirect     off;

        proxy_set_header Connection close;

        proxy_set_header   X-Forwarded-Proto \$scheme;
        proxy_set_header   Host              \$real_domain;
        proxy_set_header   X-Real-IP         \$remote_addr;
        proxy_set_header   X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header   access_token      \$http_access_token;

    }
}

server {
    listen ${NGINX_BIND_HTTPS} ssl;
    server_name *.${USER_DOMAIN};
    server_tokens off;

    ssl_certificate /etc/nginx/ssl/tls.crt;
    ssl_certificate_key /etc/nginx/ssl/tls.key;

    location /carddav/ {

        proxy_pass http://127.0.0.1:${PROXY_LOCAL_BIND};

        client_max_body_size 0;
        proxy_read_timeout 85;
        proxy_connect_timeout 85;
        proxy_redirect     off;

        proxy_set_header Connection close;

        proxy_set_header   X-Forwarded-Proto \$scheme;
        proxy_set_header   Host              \$http_host;
        proxy_set_header   X-Real-IP         \$remote_addr;
        proxy_set_header   X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header   access_token      \$http_access_token;

    }

    location /.well-known {

        proxy_pass http://127.0.0.1:${PROXY_LOCAL_BIND};

        client_max_body_size 0;
        proxy_read_timeout 85;
        proxy_connect_timeout 85;
        proxy_redirect     off;

        proxy_set_header Connection close;

        proxy_set_header   X-Forwarded-Proto \$scheme;
        proxy_set_header   Host              \$http_host;
        proxy_set_header   X-Real-IP         \$remote_addr;
        proxy_set_header   X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header   access_token      \$http_access_token;

    }

    location / {

        if (\$request_method = 'PROPFIND') {
            return 302 https://\$http_host/space/dav/;
        }

        add_header Access-Control-Allow-Origin '$http_origin' always;
        add_header Access-Control-Allow-Credentials true always;
        add_header Access-Control-Allow-Methods 'GET, PUT, POST, DELETE, PATCH, OPTIONS';
        add_header Access-Control-Expose-Headers '*';
        add_header Access-Control-Allow-Headers 'DNT,X-CustomHeader,Keep-Alive,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Authorization,request-Id';
        add_header Access-Control-Max-Age '1728000';
        if (\$request_method = 'OPTIONS') {
            return 204;
        } 

        proxy_pass http://127.0.0.1:${PROXY_LOCAL_BIND};

        client_max_body_size 0;
        proxy_read_timeout 85;
        proxy_connect_timeout 85;
        proxy_redirect     off;

        proxy_set_header Connection close;

        proxy_set_header   X-Forwarded-Proto \$scheme;
        proxy_set_header   Host              \$http_host;
        proxy_set_header   X-Real-IP         \$remote_addr;
        proxy_set_header   X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header   access_token      \$http_access_token;

    }
}

EOF

exec nginx -g "daemon off;"