#!/bin/bash
# bm-bookstack-install: Installation of BookStack for Alma Linux 
# License: N/A
# Website: https://safesploit.com/
#
# BookStack: https://www.bookstackapp.com/
# Adapted from: https://deviant.engineer/2017/02/bookstack-centos7/
#
#set -xe
VERSION="2023-10-24"

### SWITCH #######################################################################################################################
CONFIGURE_NGINX_AS_HTTPS=true
#CONFIGURE_NGINX_AS_HTTPS=false

### VARIABLES #######################################################################################################################
VARWWW="/var/www"
BOOKSTACK_DIR="${VARWWW}/BookStack"
TMPROOTPWD="/tmp/DB_ROOT.delete"
TMPBOOKPWD="/tmp/DB_BOOKSTACK.delete"
PWDLEN="32"
REMIRPM="https://rpms.remirepo.net/enterprise/remi-release-9.rpm"
CURRENT_IP=$(hostname -i)
DOMAIN=$(hostname)
blanc="\033[1;37m"; gris="\033[0;37m"; magenta="\033[0;35m"; rouge="\033[1;31m"; vert="\033[1;32m"; jaune="\033[1;33m"; bleu="\033[1;34m"; rescolor="\033[0m"

# Database configuration
DB_NAME="bookstackdb"
DB_USER="bookstackuser"

#APP configuration
#APP_URL="https://${DOMAIN}"

APP_LANG="en"

MAIL_PORT="25"  # You can change this value as needed

### Functions #######################################################################################################################

# Print colored text
print_colored() {
    local color="$1"
    local text="$2"
    echo -e "${color}${text}${rescolor}"
}

# Disable SELinux and configure firewall
configure_security() {
    print_colored "${jaune}" "SELinux disable and firewall settings ..."
    sed -i s/^SELINUX=.*$/SELINUX=disabled/ /etc/selinux/config && setenforce 0
    #firewall-cmd --add-service=http --permanent && firewall-cmd --add-service=https --permanent && firewall-cmd --reload
}

# Install required packages
install_packages() {
    print_colored "${jaune}" "Packages installation ..."
    dnf -y update
    dnf -y install vim epel-release # Install EPEL repository
    dnf -y install git unzip mariadb-server nginx

    # Install PHP and its extensions
    dnf -y install php php-cli php-fpm php-json php-gd
    dnf -y install php-mysqlnd php-xml php-openssl php-tokenizer php-mbstring php-mysqlnd
    dnf -y install php-tidy php-json php-pecl-zip

    # Create symlink tidy.so and enable extension in php.ini
    ln -s /usr/lib64/php/modules/tidy.so /usr/lib64/php/modules/tidy.so
    echo "extension=tidy" >> /etc/php.ini
}

# Configure the database
configure_database() {
    print_colored "${jaune}" "Database installation ..."
    systemctl enable --now mariadb.service
    secure_mysql_installation

    # Generate a random bookstackpass
    local bookstackpass=$(cat /dev/urandom | tr -cd 'A-Za-z0-9' | head -c $PWDLEN)
    echo "BookStack user:${bookstackpass}" >> $TMPBOOKPWD && cat $TMPBOOKPWD

    mysql --execute="
    CREATE DATABASE IF NOT EXISTS $DB_NAME DEFAULT CHARACTER SET utf8 COLLATE utf8_general_ci;
    GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost' IDENTIFIED BY '$bookstackpass' WITH GRANT OPTION;
    FLUSH PRIVILEGES;
    quit"

    # Set root password
    DB_ROOT=$(cat /dev/urandom | tr -cd 'A-Za-z0-9' | head -c $PWDLEN)
    echo "MariaDB root:${DB_ROOT}" >> $TMPROOTPWD && cat $TMPROOTPWD
    mysql -e "SET PASSWORD FOR root@localhost = PASSWORD('${DB_ROOT}');FLUSH PRIVILEGES;"

    # Store the generated bookstackpass globally
    BOOKSTACK_PASS="$bookstackpass"
}

secure_mysql_installation() {
    echo "Running mysql_secure_installation..."

    # Step 1: Disallow root login remotely - Answer 'y' (Yes)
    # Step 2: Remove anonymous users - Answer 'n' (No)
    # Step 3: Remove test database and access to it - Answer 'n' (No)
    # Step 4: Reload privilege tables now - Answer 'y' (Yes)
    # Step 5: Change the root password - Answer 'y' (Yes)
    # Step 6: Enter and confirm a new root password - Answer 'y' (Yes)
    printf "\n y\n n\n n\n y\n y\n y\n" | mysql_secure_installation

    echo "mysql_secure_installation completed."
}

#Untested
optimize_database() {
    print_colored "${jaune}" "Optimizing the BookStack database ..."

    # Log in to MariaDB as root (you might need to provide root credentials here)
    mysql -u root -p"${DB_ROOT}" <<EOF
    USE ${DB_NAME};

    -- Remove anonymous users
    DROP USER IF EXISTS ''@'localhost';
    DROP USER IF EXISTS ''@'${HOSTNAME}';

    -- Remove remote root login
    DROP USER IF EXISTS 'root'@'${HOSTNAME}';
    DROP USER IF EXISTS 'root'@'${CURRENT_IP}';

    -- Remove the test database
    DROP DATABASE IF EXISTS test;

    -- Reload privileges
    FLUSH PRIVILEGES;
EOF

    print_colored "${vert}" "Database optimization completed."
}


# Configure PHP-FPM
configure_php_fpm() {
    print_colored "${jaune}" "PHP-FPM configuration ..."
    fpmconf=/etc/php-fpm.d/www.conf
    sed -i "s|^listen =.*$|listen = /run/php-fpm.sock|" $fpmconf
    sed -i "s|^;listen.owner =.*$|listen.owner = nginx|" $fpmconf
    sed -i "s|^;listen.group =.*$|listen.group = nginx|" $fpmconf
    sed -i "s|^user = apache.*$|user = nginx ; PHP-FPM running user|" $fpmconf
    sed -i "s|^group = apache.*$|group = nginx ; PHP-FPM running group|" $fpmconf
    sed -i "s|^php_value\[session.save_path\].*$|php_value[session.save_path] = ${VARWWW}/sessions|" $fpmconf
    #optimize_php_fpm
}

# Optimises PHP-FPM configuration (UNTESTED)
optimize_php_fpm() {
    # PHP-FPM pool configuration file (adjust path if necessary)
    php_fpm_pool_conf="/etc/php-fpm.d/www.conf"

    # Adjust PHP-FPM pool settings
    sed -i 's/^pm = dynamic/pm = ondemand/' "$php_fpm_pool_conf"
    sed -i 's/^pm.max_children = .*/pm.max_children = 10/' "$php_fpm_pool_conf"
    sed -i 's/^pm.start_servers = .*/pm.start_servers = 2/' "$php_fpm_pool_conf"
    sed -i 's/^pm.min_spare_servers = .*/pm.min_spare_servers = 1/' "$php_fpm_pool_conf"
    sed -i 's/^pm.max_spare_servers = .*/pm.max_spare_servers = 3/' "$php_fpm_pool_conf"

    # Tune PHP settings
    php_ini="/etc/php.ini"
    sed -i 's/^memory_limit = .*/memory_limit = 256M/' "$php_ini"
    sed -i 's/^max_execution_time = .*/max_execution_time = 60/' "$php_ini"
    sed -i 's/^post_max_size = .*/post_max_size = 20M/' "$php_ini"
    sed -i 's/^upload_max_filesize = .*/upload_max_filesize = 20M/' "$php_ini"
    sed -i 's/^;date.timezone =/date.timezone = "America/New_York"/' "$php_ini"

    # Enable OPCache (optional)
    # sed -i 's/^;opcache.enable=0/opcache.enable=1/' "$php_ini"

    # Security settings (customize as needed)
    sed -i 's/^expose_php = On/expose_php = Off/' "$php_ini"
    # Add more security settings here

    # Restart PHP-FPM service to apply changes (adjust service name if necessary)
    systemctl restart php-fpm
}


# Boolean Logic for configuring NGINX
configure_nginx() {
    if [[ "${CONFIGURE_NGINX_AS_HTTPS}" == true ]]; then
        configure_nginx_https
    else
        configure_nginx_http
    fi
}

set_app_url() {
    if [[ "${CONFIGURE_NGINX_AS_HTTPS}" == true ]]; then
        APP_URL="https://${DOMAIN}"
    else
        APP_URL="http://${DOMAIN}"
    fi
}

# Configure NGINX HTTP only version
configure_nginx_http() {
    print_colored "${jaune}" "Nginx configuration ..."
    mv /etc/nginx/nginx.conf /etc/nginx/nginx.conf.BAK

    cat << '_EOF_' > /etc/nginx/nginx.conf
    user nginx;
    worker_processes auto;
    error_log /var/log/nginx/error.log;
    pid /run/nginx.pid;
    include /usr/share/nginx/modules/*.conf;
    events {
        worker_connections 1024;
    }
    http {
        log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
                          '$status $body_bytes_sent "$http_referer" '
                          '"$http_user_agent" "$http_x_forwarded_for"';
        access_log  /var/log/nginx/access.log  main;
        sendfile            on;
        tcp_nopush          on;
        tcp_nodelay         on;
        keepalive_timeout   65;
        types_hash_max_size 2048;
        include             /etc/nginx/mime.types;
        default_type        application/octet-stream;
        include /etc/nginx/conf.d/*.conf;
    }
_EOF_

    cat << '_EOF_' > /etc/nginx/conf.d/bookstack.conf
    server {
        listen 80;
        #HTTP conf:
        #listen 443 ssl;
        #ssl_certificate /etc/pki/tls/blogmotion/monserveur.crt;
        #ssl_certificate_key /etc/pki/tls/blogmotion/monserveur.key;
        #ssl_protocols TLSv1.2;
        #ssl_prefer_server_ciphers on;
        server_name _;
        root /var/www/BookStack/public;
        access_log  /var/log/nginx/bookstack_access.log;
        error_log  /var/log/nginx/bookstack_error.log;
        client_max_body_size 1G;
        fastcgi_buffers 64 4K;
        index  index.php;
        location / {
            try_files $uri $uri/ /index.php?$query_string;
        }
        location ~ ^/(?:\.htaccess|data|config|db_structure\.xml|README) {
            deny all;
        }
        location ~ \.php(?:$|/) {
            fastcgi_split_path_info ^(.+\.php)(/.+)$;
            include fastcgi_params;
            fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
            fastcgi_param PATH_INFO $fastcgi_path_info;
            fastcgi_pass unix:/var/run/php-fpm.sock;
        }
        location ~* \.(?:jpg|jpeg|gif|bmp|ico|png|css|js|swf)$ {
            expires 30d;
            access_log off;
        }
    }
_EOF_

    # Enable and start services
    systemctl enable --now nginx.service
    systemctl enable --now php-fpm.service
}



# Function to configure NGINX with security measures (HTTPS)
configure_nginx_https() {
    generate_self_signed_certificate

    print_colored "${jaune}" "Nginx configuration ..."
    mv /etc/nginx/nginx.conf /etc/nginx/nginx.conf.BAK

    cat << '_EOF_' > /etc/nginx/nginx.conf
    user nginx;
    worker_processes auto;
    error_log /var/log/nginx/error.log;
    pid /run/nginx.pid;
    include /usr/share/nginx/modules/*.conf;
    events {
        worker_connections 1024;
    }
    http {
        log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
                          '$status $body_bytes_sent "$http_referer" '
                          '"$http_user_agent" "$http_x_forwarded_for"';
        access_log  /var/log/nginx/access.log  main;
        sendfile            on;
        tcp_nopush          on;
        tcp_nodelay         on;
        keepalive_timeout   65;
        types_hash_max_size 2048;
        include             /etc/nginx/mime.types;
        default_type        application/octet-stream;
        include /etc/nginx/conf.d/*.conf;
    }
_EOF_

    cat << '_EOF_' > /etc/nginx/conf.d/bookstack_https.conf
    server {
        listen 443 ssl;
        ssl_certificate /etc/nginx/ssl/nginx.crt;
        ssl_certificate_key /etc/nginx/ssl/nginx.key;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers 'TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384';
        ssl_prefer_server_ciphers off;
        ssl_session_timeout 1d;
        server_name _;

        root /var/www/BookStack/public;
        access_log  /var/log/nginx/bookstack_access.log;
        error_log  /var/log/nginx/bookstack_error.log;
        client_max_body_size 1G;
        fastcgi_buffers 64 4K;
        index  index.php;
        location / {
            try_files $uri $uri/ /index.php?$query_string;
        }
        location ~ ^/(?:\.htaccess|data|config|db_structure\.xml|README) {
            deny all;
        }
        location ~ \.php(?:$|/) {
            fastcgi_split_path_info ^(.+\.php)(/.+)$;
            include fastcgi_params;
            fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
            fastcgi_param PATH_INFO $fastcgi_path_info;
            fastcgi_pass unix:/var/run/php-fpm.sock;
        }
        location ~* \.(?:jpg|jpeg|gif|bmp|ico|png|css|js|swf)$ {
            expires 30d;
            access_log off;
        }
    }
_EOF_

    # Enable and start services
    systemctl enable --now nginx.service
    systemctl enable --now php-fpm.service
}



# Generate a self-signed HTTPS certificate
generate_self_signed_certificate() {
    # Check if the certificate files already exist
    if [ -f "/etc/nginx/ssl/nginx.crt" ] && [ -f "/etc/nginx/ssl/nginx.key" ]; then
        print_colored "${jaune}" "Using existing SSL certificate."
    else
        print_colored "${jaune}" "Generating a self-signed SSL certificate..."
        mkdir -p /etc/nginx/ssl
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/nginx/ssl/nginx.key -out /etc/nginx/ssl/nginx.crt -subj "/C=US/ST=State/L=City/O=Organization/CN=localhost"
        chmod 600 /etc/nginx/ssl/nginx.key
        chmod 644 /etc/nginx/ssl/nginx.crt
    fi
}


# Modify settings for Bookstack .env
inject_and_modify_app_settings() {
    cp .env.example .env
    /var/www/BookStack/.env

    sed -i "s|APP_URL=.*$|APP_URL=${APP_URL}|" .env
    sed -i "s|^DB_DATABASE=.*$|DB_DATABASE=$DB_NAME|" .env
    sed -i "s|^DB_USERNAME=.*$|DB_USERNAME=$DB_USER|" .env
    sed -i "s|^DB_PASSWORD=.*$|DB_PASSWORD=${BOOKSTACK_PASS}|" .env
    sed -i "s|^MAIL_PORT=.*$|MAIL_PORT=${MAIL_PORT}|" .env  # Use the MAIL_PORT variable
}

exit_messages() {
    print_colored "${magenta}" " --- END OF SCRIPT (v${VERSION}) ---"
    echo -e "\t * 1 * ${gris}Database Name: ${rouge}${DB_NAME}${gris} Database User: ${rouge}${DB_USER}${gris} Database Password: ${rouge}${BOOKSTACK_PASS}${gris}${rescolor}"
    echo -e "\t * 2 * ${vert}PLEASE NOTE the MariaDB password root:${DB_ROOT} ${rescolor}"
    echo -e "\t * 3 * ${rouge}AND DELETE the files (or reboot) ${TMPROOTPWD} and ${TMPBOOKPWD} ${rescolor}"
    echo -e "\t * 4 * ${bleu}Logon ${APP_URL} or http://${CURRENT_IP} \n\t\t -> with admin@admin.com and 'password' ${rescolor}"
}


# Install and configure BookStack
install_bookstack() {
    print_colored "${jaune}" "BookStack installation ..."
    mkdir -p ${VARWWW}/sessions # php sessions

    # Clone the latest from the release branch
    git clone https://github.com/BookStackApp/BookStack.git --branch release --single-branch ${BOOKSTACK_DIR}

    # Let Composer do its things
    cd /usr/local/bin
    curl -sS https://getcomposer.org/installer | php
    mv composer.phar composer
    cd ${BOOKSTACK_DIR}
    composer install

    # Config file injection
    inject_and_modify_app_settings

    # Generate and update APP_KEY in .env
    php artisan key:generate --no-interaction --force

    # Generate database tables and other settings
    php artisan migrate --force

    # Fix rights
    chown -R nginx:nginx /var/www/{BookStack,sessions}
    chmod -R 755 bootstrap/cache public/uploads storage

    # Exit messages for usage
    exit_messages
}

### START SCRIPT ####################################################################################################################
print_colored "${vert}" "#########################################################"
print_colored "${vert}" "#                                                       #"
print_colored "${vert}" "#                BookStack Installation                 #"
print_colored "${vert}" "#                                                       #"
print_colored "${vert}" "#                  Tested on Alma 9 (x64)               #"
print_colored "${vert}" "#                      by @safesploit                   #"
print_colored "${vert}" "#                                                       #"
print_colored "${vert}" "###################### ${VERSION} #######################"
print_colored "${rescolor}" "\n\n"
sleep 3

# Execute functions
set_app_url
configure_security
install_packages
configure_database
configure_php_fpm
configure_nginx
install_bookstack

exit 0
