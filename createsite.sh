#!/bin/bash
set -a; source .env; set +a
echo "Starting WordPress site creation using Docker and Nginx as a reverse proxy..."

read -p "Enter domain name: " domain_name
db_name=$(echo "$domain_name" | tr '.' '_')
read -sp "Enter a password for the WordPress admin user: " wp_password
echo

echo "${db_name}_PASSWORD=$wp_password" >> .env

# new db
docker compose exec mariadb mysql -u root -p"$DB_PASSWORD" -e "CREATE DATABASE $db_name; GRANT ALL PRIVILEGES ON $db_name.* TO 'databaseuser'@'%' IDENTIFIED BY '$DB_PASSWORD'"

# add new site to docker-compose.yml
cp  docker-compose.yml docker-compose.back`date +%Y%m%d`
wordpress_service=$(cat <<EOF
  $domain_name:
    image: docker.io/bitnami/wordpress-nginx:latest
    volumes:
      - wordpress-$domain_name-1:/bitnami/wordpress
    environment:
      - ALLOW_EMPTY_PASSWORD=no
      - WORDPRESS_DATABASE_HOST=mariadb
      - WORDPRESS_DATABASE_PORT_NUMBER=3306
      - WORDPRESS_DATABASE_NAME=$db_name
      - WORDPRESS_TABLE_PREFIX=${db_name}_
      - WORDPRESS_DATABASE_USER=\${DB_USER}
      - WORDPRESS_DATABASE_PASSWORD=\${DB_PASSWORD}
      - WORDPRESS_USERNAME=\${WP_ADMIN}
      - WORDPRESS_PASSWORD=\${${db_name}_PASSWORD}
      - WORDPRESS_DATA_TO_PERSIST=wp-config.php wp-content
      - WORDPRESS_ENABLE_REVERSE_PROXY=yes
      - WORDPRESS_ENABLE_HTTPS=yes
    extra_hosts:
      - "$domain_name:172.18.0.1"
    networks:
      - wordpress-network
EOF
)

awk -v wordpress="$wordpress_service" '/# Add new WordPress service after this line/ {print; print wordpress; next}1' docker-compose.yml > docker-compose.tmp && mv docker-compose.tmp docker-compose.yml

cat <<EOF >> docker-compose.yml
  wordpress-$domain_name-1:
    driver: local
EOF
# ssl certificate
docker run -it --rm --name certbot \
  -v "/etc/letsencrypt:/etc/letsencrypt" \
  -v "/var/lib/letsencrypt:/var/lib/letsencrypt" \
  -v "/root/.ssh/cloudflare/cloudflare.ini:/cloudflare.ini:ro" \
  certbot/dns-cloudflare certonly --non-interactive --agree-tos \
  --dns-cloudflare --email gmail@gmail.com \
  --dns-cloudflare-credentials /cloudflare.ini \
  --dns-cloudflare-propagation-seconds 60 \
  -d "$domain_name" -d "www.$domain_name"

echo "The SSL certificate has been generated successfully."

#nginx block
cp proxypass.conf proxypass.back`date +%Y%m%d`
nginx_server_block=$(cat <<EOF

server {
    listen 80;
    server_name $domain_name;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    server_name $domain_name;

    ssl_certificate /etc/letsencrypt/live/$domain_name/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$domain_name/privkey.pem;

    location / {
        proxy_pass https://wordpress-$domain_name-1:8443/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 180s;
        proxy_connect_timeout 180s;
    }
}
EOF
)

echo "$nginx_server_block" >> proxypass.conf

echo "Proxypass configuration updated."


echo "The new WordPress site for $domain_name has been created successfully. Please run 'docker compose up -d' and restart modsecurity container to  apply the changes."


