#!/bin/bash

apache_user=$1

if [ -z "${apache_user}" ];then
    echo "Please input logged in username ...."
    exit \1
fi

# Function check user root
f_check_root () {
    if (( $EUID == 0 )); then
        # If user is root, continue to function f_sub_main
        f_sub_main
    else
        # If user not is root, print message and exit script
        echo "Please run this script by user root !"
        exit
    fi
}

# Function update os
f_update_os () {
    echo "Starting update os ..."
    sleep 1

    apt update
    apt upgrade -y
    apt install -y vim git htop unzip patch curl

    sleep 1
}

f_install_nginx() {
    ########## INSTALL APACHE ##########
    echo "Installing nginx ..."
    sleep 1

    apt update -y
    apt install nginx -y


    echo "Configuring Nginx ..."
    > /etc/nginx/nginx.conf

    cat > /etc/nginx/nginx.conf <<EOL
user ${apache_user} ${apache_user};
worker_processes auto;
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;

events {
	worker_connections 768;
}

http {
	sendfile on;
	tcp_nopush on;
	tcp_nodelay on;
	keepalive_timeout 65;
	types_hash_max_size 2048;
	client_body_buffer_size 10K;
    	client_header_buffer_size 1k;
    	client_max_body_size 10m;
    	large_client_header_buffers 4 16k;

	include /etc/nginx/mime.types;
	default_type application/octet-stream;

	ssl_protocols TLSv1 TLSv1.1 TLSv1.2; # Dropping SSLv3, ref: POODLE
	ssl_prefer_server_ciphers on;

	access_log /var/log/nginx/access.log;
	error_log /var/log/nginx/error.log;

	gzip on;

	include /etc/nginx/conf.d/*.conf;
	include /etc/nginx/sites-enabled/*;
}
EOL

    echo "Creating php-fpm pool ..."

    mkdir /etc/nginx/magento2_config

    touch /etc/nginx/magento2_config/nginx70.conf
    cat > /etc/nginx/magento2_config/nginx70.conf <<EOL
root \$MAGE_ROOT/pub;

index index.php;
autoindex off;
charset UTF-8;
error_page 404 403 = /errors/404.php;
#add_header "X-UA-Compatible" "IE=Edge";

# PHP entry point for setup application
location ~* ^/setup($|/) {
    root \$MAGE_ROOT;
    location ~ ^/setup/index.php {
        fastcgi_pass   unix:/var/run/php/php7.0-fpm.sock;

        fastcgi_param  PHP_FLAG  "session.auto_start=off \n suhosin.session.cryptua=off";
        fastcgi_param  PHP_VALUE "memory_limit=756M \n max_execution_time=600";
        fastcgi_read_timeout 600s;
        fastcgi_connect_timeout 600s;

        fastcgi_index  index.php;
        fastcgi_param  SCRIPT_FILENAME  \$document_root\$fastcgi_script_name;
        include        fastcgi_params;
    }

    location ~ ^/setup/(?!pub/). {
        deny all;
    }

    location ~ ^/setup/pub/ {
        add_header X-Frame-Options "SAMEORIGIN";
    }
}

# PHP entry point for update application
location ~* ^/update($|/) {
    root \$MAGE_ROOT;

    location ~ ^/update/index.php {
        fastcgi_split_path_info ^(/update/index.php)(/.+)$;
        fastcgi_pass   unix:/var/run/php/php7.0-fpm.sock;
        fastcgi_index  index.php;
        fastcgi_param  SCRIPT_FILENAME  \$document_root\$fastcgi_script_name;
        fastcgi_param  PATH_INFO        \$fastcgi_path_info;
        include        fastcgi_params;
    }

    # Deny everything but index.php
    location ~ ^/update/(?!pub/). {
        deny all;
    }

    location ~ ^/update/pub/ {
        add_header X-Frame-Options "SAMEORIGIN";
    }
}

location / {
    try_files \$uri \$uri/ /index.php\$is_args\$args;
}

location /pub/ {
    location ~ ^/pub/media/(downloadable|customer|import|theme_customization/.*\.xml) {
        deny all;
    }
    alias \$MAGE_ROOT/pub/;
    add_header X-Frame-Options "SAMEORIGIN";
}

location /static/ {
    # Uncomment the following line in production mode
    # expires max;

    # Remove signature of the static files that is used to overcome the browser cache
    location ~ ^/static/version {
        rewrite ^/static/(version[^/]+/)?(.*)$ /static/\$2 last;
    }

    location ~* \.(ico|jpg|jpeg|png|gif|svg|js|css|swf|eot|ttf|otf|woff|woff2|html|json)$ {
        add_header Cache-Control "public";
        add_header X-Frame-Options "SAMEORIGIN";
        expires +1y;

        if (!-f \$request_filename) {
            rewrite ^/static/?(.*)$ /static.php?resource=\$1 last;
        }
    }
    location ~* \.(zip|gz|gzip|bz2|csv|xml)$ {
        add_header Cache-Control "no-store";
        add_header X-Frame-Options "SAMEORIGIN";
        expires    off;

        if (!-f \$request_filename) {
           rewrite ^/static/?(.*)$ /static.php?resource=\$1 last;
        }
    }
    if (!-f \$request_filename) {
        rewrite ^/static/?(.*)$ /static.php?resource=\$1 last;
    }
    add_header X-Frame-Options "SAMEORIGIN";
}

location /media/ {
    try_files \$uri \$uri/ /get.php\$is_args\$args;

    location ~ ^/media/theme_customization/.*\.xml {
        deny all;
    }

    location ~* \.(ico|jpg|jpeg|png|gif|svg|js|css|swf|eot|ttf|otf|woff|woff2)$ {
        add_header Cache-Control "public";
        add_header X-Frame-Options "SAMEORIGIN";
        expires +1y;
        try_files \$uri \$uri/ /get.php\$is_args\$args;
    }
    location ~* \.(zip|gz|gzip|bz2|csv|xml)$ {
        add_header Cache-Control "no-store";
        add_header X-Frame-Options "SAMEORIGIN";
        expires    off;
        try_files \$uri \$uri/ /get.php\$is_args\$args;
    }
    add_header X-Frame-Options "SAMEORIGIN";
}

location /media/customer/ {
    deny all;
}

location /media/downloadable/ {
    deny all;
}

location /media/import/ {
    deny all;
}

# PHP entry point for main application
location ~ (index|get|static|report|404|503|health_check|opcache_.*|phpinfo_.*)\.php$ {
    try_files \$uri =404;
    fastcgi_pass   unix:/var/run/php/php7.0-fpm.sock;
    fastcgi_buffers 1024 4k;

    fastcgi_param  PHP_FLAG  "session.auto_start=off \n suhosin.session.cryptua=off";
    fastcgi_param  PHP_VALUE "memory_limit=756M \n max_execution_time=18000 \n session.save_path=";
    fastcgi_read_timeout 600s;
    fastcgi_connect_timeout 600s;

    fastcgi_index  index.php;
    fastcgi_param  SCRIPT_FILENAME  \$document_root\$fastcgi_script_name;
    include        fastcgi_params;
}

gzip on;
gzip_disable "msie6";

gzip_comp_level 6;
gzip_min_length 1100;
gzip_buffers 16 8k;
gzip_proxied any;
gzip_types
    text/plain
    text/css
    text/js
    text/xml
    text/javascript
    application/javascript
    application/x-javascript
    application/json
    application/xml
    application/xml+rss
    image/svg+xml;
gzip_vary on;

# Banned locations (only reached if the earlier PHP entry point regexes don't match)
location ~* (\.php$|\.htaccess$|\.git) {
    deny all;
}
EOL

    touch /etc/nginx/magento2_config/nginx71.conf
    cat > /etc/nginx/magento2_config/nginx71.conf <<EOL
root \$MAGE_ROOT/pub;

index index.php;
autoindex off;
charset UTF-8;
error_page 404 403 = /errors/404.php;
#add_header "X-UA-Compatible" "IE=Edge";

# PHP entry point for setup application
location ~* ^/setup($|/) {
    root \$MAGE_ROOT;
    location ~ ^/setup/index.php {
        fastcgi_pass   unix:/var/run/php/php7.1-fpm.sock;

        fastcgi_param  PHP_FLAG  "session.auto_start=off \n suhosin.session.cryptua=off";
        fastcgi_param  PHP_VALUE "memory_limit=756M \n max_execution_time=600";
        fastcgi_read_timeout 600s;
        fastcgi_connect_timeout 600s;

        fastcgi_index  index.php;
        fastcgi_param  SCRIPT_FILENAME  \$document_root\$fastcgi_script_name;
        include        fastcgi_params;
    }

    location ~ ^/setup/(?!pub/). {
        deny all;
    }

    location ~ ^/setup/pub/ {
        add_header X-Frame-Options "SAMEORIGIN";
    }
}

# PHP entry point for update application
location ~* ^/update($|/) {
    root \$MAGE_ROOT;

    location ~ ^/update/index.php {
        fastcgi_split_path_info ^(/update/index.php)(/.+)$;
        fastcgi_pass   unix:/var/run/php/php7.1-fpm.sock;
        fastcgi_index  index.php;
        fastcgi_param  SCRIPT_FILENAME  \$document_root\$fastcgi_script_name;
        fastcgi_param  PATH_INFO        \$fastcgi_path_info;
        include        fastcgi_params;
    }

    # Deny everything but index.php
    location ~ ^/update/(?!pub/). {
        deny all;
    }

    location ~ ^/update/pub/ {
        add_header X-Frame-Options "SAMEORIGIN";
    }
}

location / {
    try_files \$uri \$uri/ /index.php\$is_args\$args;
}

location /pub/ {
    location ~ ^/pub/media/(downloadable|customer|import|theme_customization/.*\.xml) {
        deny all;
    }
    alias \$MAGE_ROOT/pub/;
    add_header X-Frame-Options "SAMEORIGIN";
}

location /static/ {
    # Uncomment the following line in production mode
    # expires max;

    # Remove signature of the static files that is used to overcome the browser cache
    location ~ ^/static/version {
        rewrite ^/static/(version[^/]+/)?(.*)$ /static/\$2 last;
    }

    location ~* \.(ico|jpg|jpeg|png|gif|svg|js|css|swf|eot|ttf|otf|woff|woff2|html|json)$ {
        add_header Cache-Control "public";
        add_header X-Frame-Options "SAMEORIGIN";
        expires +1y;

        if (!-f \$request_filename) {
            rewrite ^/static/?(.*)$ /static.php?resource=\$1 last;
        }
    }
    location ~* \.(zip|gz|gzip|bz2|csv|xml)$ {
        add_header Cache-Control "no-store";
        add_header X-Frame-Options "SAMEORIGIN";
        expires    off;

        if (!-f \$request_filename) {
           rewrite ^/static/?(.*)$ /static.php?resource=\$1 last;
        }
    }
    if (!-f \$request_filename) {
        rewrite ^/static/?(.*)$ /static.php?resource=\$1 last;
    }
    add_header X-Frame-Options "SAMEORIGIN";
}

location /media/ {
    try_files \$uri \$uri/ /get.php\$is_args\$args;

    location ~ ^/media/theme_customization/.*\.xml {
        deny all;
    }

    location ~* \.(ico|jpg|jpeg|png|gif|svg|js|css|swf|eot|ttf|otf|woff|woff2)$ {
        add_header Cache-Control "public";
        add_header X-Frame-Options "SAMEORIGIN";
        expires +1y;
        try_files \$uri \$uri/ /get.php\$is_args\$args;
    }
    location ~* \.(zip|gz|gzip|bz2|csv|xml)$ {
        add_header Cache-Control "no-store";
        add_header X-Frame-Options "SAMEORIGIN";
        expires    off;
        try_files \$uri \$uri/ /get.php\$is_args\$args;
    }
    add_header X-Frame-Options "SAMEORIGIN";
}

location /media/customer/ {
    deny all;
}

location /media/downloadable/ {
    deny all;
}

location /media/import/ {
    deny all;
}

# PHP entry point for main application
location ~ (index|get|static|report|404|503|health_check|opcache_.*|phpinfo_.*)\.php$ {
    try_files \$uri =404;
    fastcgi_pass   unix:/var/run/php/php7.1-fpm.sock;
    fastcgi_buffers 1024 4k;

    fastcgi_param  PHP_FLAG  "session.auto_start=off \n suhosin.session.cryptua=off";
    fastcgi_param  PHP_VALUE "memory_limit=756M \n max_execution_time=18000 \n session.save_path=";
    fastcgi_read_timeout 600s;
    fastcgi_connect_timeout 600s;

    fastcgi_index  index.php;
    fastcgi_param  SCRIPT_FILENAME  \$document_root\$fastcgi_script_name;
    include        fastcgi_params;
}

gzip on;
gzip_disable "msie6";

gzip_comp_level 6;
gzip_min_length 1100;
gzip_buffers 16 8k;
gzip_proxied any;
gzip_types
    text/plain
    text/css
    text/js
    text/xml
    text/javascript
    application/javascript
    application/x-javascript
    application/json
    application/xml
    application/xml+rss
    image/svg+xml;
gzip_vary on;

# Banned locations (only reached if the earlier PHP entry point regexes don't match)
location ~* (\.php$|\.htaccess$|\.git) {
    deny all;
}
EOL

    touch /etc/nginx/magento2_config/nginx72.conf
    cat > /etc/nginx/magento2_config/nginx72.conf <<EOL
root \$MAGE_ROOT/pub;

index index.php;
autoindex off;
charset UTF-8;
error_page 404 403 = /errors/404.php;
#add_header "X-UA-Compatible" "IE=Edge";

# PHP entry point for setup application
location ~* ^/setup($|/) {
    root \$MAGE_ROOT;
    location ~ ^/setup/index.php {
        fastcgi_pass   unix:/var/run/php/php7.2-fpm.sock;

        fastcgi_param  PHP_FLAG  "session.auto_start=off \n suhosin.session.cryptua=off";
        fastcgi_param  PHP_VALUE "memory_limit=756M \n max_execution_time=600";
        fastcgi_read_timeout 600s;
        fastcgi_connect_timeout 600s;

        fastcgi_index  index.php;
        fastcgi_param  SCRIPT_FILENAME  \$document_root\$fastcgi_script_name;
        include        fastcgi_params;
    }

    location ~ ^/setup/(?!pub/). {
        deny all;
    }

    location ~ ^/setup/pub/ {
        add_header X-Frame-Options "SAMEORIGIN";
    }
}

# PHP entry point for update application
location ~* ^/update($|/) {
    root \$MAGE_ROOT;

    location ~ ^/update/index.php {
        fastcgi_split_path_info ^(/update/index.php)(/.+)$;
        fastcgi_pass   unix:/var/run/php/php7.2-fpm.sock;
        fastcgi_index  index.php;
        fastcgi_param  SCRIPT_FILENAME  \$document_root\$fastcgi_script_name;
        fastcgi_param  PATH_INFO        \$fastcgi_path_info;
        include        fastcgi_params;
    }

    # Deny everything but index.php
    location ~ ^/update/(?!pub/). {
        deny all;
    }

    location ~ ^/update/pub/ {
        add_header X-Frame-Options "SAMEORIGIN";
    }
}

location / {
    try_files \$uri \$uri/ /index.php\$is_args\$args;
}

location /pub/ {
    location ~ ^/pub/media/(downloadable|customer|import|theme_customization/.*\.xml) {
        deny all;
    }
    alias \$MAGE_ROOT/pub/;
    add_header X-Frame-Options "SAMEORIGIN";
}

location /static/ {
    # Uncomment the following line in production mode
    # expires max;

    # Remove signature of the static files that is used to overcome the browser cache
    location ~ ^/static/version {
        rewrite ^/static/(version[^/]+/)?(.*)$ /static/\$2 last;
    }

    location ~* \.(ico|jpg|jpeg|png|gif|svg|js|css|swf|eot|ttf|otf|woff|woff2|html|json)$ {
        add_header Cache-Control "public";
        add_header X-Frame-Options "SAMEORIGIN";
        expires +1y;

        if (!-f \$request_filename) {
            rewrite ^/static/?(.*)$ /static.php?resource=\$1 last;
        }
    }
    location ~* \.(zip|gz|gzip|bz2|csv|xml)$ {
        add_header Cache-Control "no-store";
        add_header X-Frame-Options "SAMEORIGIN";
        expires    off;

        if (!-f \$request_filename) {
           rewrite ^/static/?(.*)$ /static.php?resource=\$1 last;
        }
    }
    if (!-f \$request_filename) {
        rewrite ^/static/?(.*)$ /static.php?resource=\$1 last;
    }
    add_header X-Frame-Options "SAMEORIGIN";
}

location /media/ {
    try_files \$uri \$uri/ /get.php\$is_args\$args;

    location ~ ^/media/theme_customization/.*\.xml {
        deny all;
    }

    location ~* \.(ico|jpg|jpeg|png|gif|svg|js|css|swf|eot|ttf|otf|woff|woff2)$ {
        add_header Cache-Control "public";
        add_header X-Frame-Options "SAMEORIGIN";
        expires +1y;
        try_files \$uri \$uri/ /get.php\$is_args\$args;
    }
    location ~* \.(zip|gz|gzip|bz2|csv|xml)$ {
        add_header Cache-Control "no-store";
        add_header X-Frame-Options "SAMEORIGIN";
        expires    off;
        try_files \$uri \$uri/ /get.php\$is_args\$args;
    }
    add_header X-Frame-Options "SAMEORIGIN";
}

location /media/customer/ {
    deny all;
}

location /media/downloadable/ {
    deny all;
}

location /media/import/ {
    deny all;
}

# PHP entry point for main application
location ~ (index|get|static|report|404|503|health_check|opcache_.*|phpinfo_.*)\.php$ {
    try_files \$uri =404;
    fastcgi_pass   unix:/var/run/php/php7.2-fpm.sock;
    fastcgi_buffers 1024 4k;

    fastcgi_param  PHP_FLAG  "session.auto_start=off \n suhosin.session.cryptua=off";
    fastcgi_param  PHP_VALUE "memory_limit=756M \n max_execution_time=18000 \n session.save_path=";
    fastcgi_read_timeout 600s;
    fastcgi_connect_timeout 600s;

    fastcgi_index  index.php;
    fastcgi_param  SCRIPT_FILENAME  \$document_root\$fastcgi_script_name;
    include        fastcgi_params;
}

gzip on;
gzip_disable "msie6";

gzip_comp_level 6;
gzip_min_length 1100;
gzip_buffers 16 8k;
gzip_proxied any;
gzip_types
    text/plain
    text/css
    text/js
    text/xml
    text/javascript
    application/javascript
    application/x-javascript
    application/json
    application/xml
    application/xml+rss
    image/svg+xml;
gzip_vary on;

# Banned locations (only reached if the earlier PHP entry point regexes don't match)
location ~* (\.php$|\.htaccess$|\.git) {
    deny all;
}
EOL


    touch /etc/nginx/magento2_config/nginx73.conf
    cat > /etc/nginx/magento2_config/nginx73.conf <<EOL
root \$MAGE_ROOT/pub;

index index.php;
autoindex off;
charset UTF-8;
error_page 404 403 = /errors/404.php;
#add_header "X-UA-Compatible" "IE=Edge";

# PHP entry point for setup application
location ~* ^/setup($|/) {
    root \$MAGE_ROOT;
    location ~ ^/setup/index.php {
        fastcgi_pass   unix:/var/run/php/php7.3-fpm.sock;

        fastcgi_param  PHP_FLAG  "session.auto_start=off \n suhosin.session.cryptua=off";
        fastcgi_param  PHP_VALUE "memory_limit=756M \n max_execution_time=600";
        fastcgi_read_timeout 600s;
        fastcgi_connect_timeout 600s;

        fastcgi_index  index.php;
        fastcgi_param  SCRIPT_FILENAME  \$document_root\$fastcgi_script_name;
        include        fastcgi_params;
    }

    location ~ ^/setup/(?!pub/). {
        deny all;
    }

    location ~ ^/setup/pub/ {
        add_header X-Frame-Options "SAMEORIGIN";
    }
}

# PHP entry point for update application
location ~* ^/update($|/) {
    root \$MAGE_ROOT;

    location ~ ^/update/index.php {
        fastcgi_split_path_info ^(/update/index.php)(/.+)$;
        fastcgi_pass   unix:/var/run/php/php7.3-fpm.sock;
        fastcgi_index  index.php;
        fastcgi_param  SCRIPT_FILENAME  \$document_root\$fastcgi_script_name;
        fastcgi_param  PATH_INFO        \$fastcgi_path_info;
        include        fastcgi_params;
    }

    # Deny everything but index.php
    location ~ ^/update/(?!pub/). {
        deny all;
    }

    location ~ ^/update/pub/ {
        add_header X-Frame-Options "SAMEORIGIN";
    }
}

location / {
    try_files \$uri \$uri/ /index.php\$is_args\$args;
}

location /pub/ {
    location ~ ^/pub/media/(downloadable|customer|import|theme_customization/.*\.xml) {
        deny all;
    }
    alias \$MAGE_ROOT/pub/;
    add_header X-Frame-Options "SAMEORIGIN";
}

location /static/ {
    # Uncomment the following line in production mode
    # expires max;

    # Remove signature of the static files that is used to overcome the browser cache
    location ~ ^/static/version {
        rewrite ^/static/(version[^/]+/)?(.*)$ /static/\$2 last;
    }

    location ~* \.(ico|jpg|jpeg|png|gif|svg|js|css|swf|eot|ttf|otf|woff|woff2|html|json)$ {
        add_header Cache-Control "public";
        add_header X-Frame-Options "SAMEORIGIN";
        expires +1y;

        if (!-f \$request_filename) {
            rewrite ^/static/?(.*)$ /static.php?resource=\$1 last;
        }
    }
    location ~* \.(zip|gz|gzip|bz2|csv|xml)$ {
        add_header Cache-Control "no-store";
        add_header X-Frame-Options "SAMEORIGIN";
        expires    off;

        if (!-f \$request_filename) {
           rewrite ^/static/?(.*)$ /static.php?resource=\$1 last;
        }
    }
    if (!-f \$request_filename) {
        rewrite ^/static/?(.*)$ /static.php?resource=\$1 last;
    }
    add_header X-Frame-Options "SAMEORIGIN";
}

location /media/ {
    try_files \$uri \$uri/ /get.php\$is_args\$args;

    location ~ ^/media/theme_customization/.*\.xml {
        deny all;
    }

    location ~* \.(ico|jpg|jpeg|png|gif|svg|js|css|swf|eot|ttf|otf|woff|woff2)$ {
        add_header Cache-Control "public";
        add_header X-Frame-Options "SAMEORIGIN";
        expires +1y;
        try_files \$uri \$uri/ /get.php\$is_args\$args;
    }
    location ~* \.(zip|gz|gzip|bz2|csv|xml)$ {
        add_header Cache-Control "no-store";
        add_header X-Frame-Options "SAMEORIGIN";
        expires    off;
        try_files \$uri \$uri/ /get.php\$is_args\$args;
    }
    add_header X-Frame-Options "SAMEORIGIN";
}

location /media/customer/ {
    deny all;
}

location /media/downloadable/ {
    deny all;
}

location /media/import/ {
    deny all;
}

# PHP entry point for main application
location ~ (index|get|static|report|404|503|health_check|opcache_.*|phpinfo_.*)\.php$ {
    try_files \$uri =404;
    fastcgi_pass   unix:/var/run/php/php7.3-fpm.sock;
    fastcgi_buffers 1024 4k;

    fastcgi_param  PHP_FLAG  "session.auto_start=off \n suhosin.session.cryptua=off";
    fastcgi_param  PHP_VALUE "memory_limit=756M \n max_execution_time=18000 \n session.save_path=";
    fastcgi_read_timeout 600s;
    fastcgi_connect_timeout 600s;

    fastcgi_index  index.php;
    fastcgi_param  SCRIPT_FILENAME  \$document_root\$fastcgi_script_name;
    include        fastcgi_params;
}

gzip on;
gzip_disable "msie6";

gzip_comp_level 6;
gzip_min_length 1100;
gzip_buffers 16 8k;
gzip_proxied any;
gzip_types
    text/plain
    text/css
    text/js
    text/xml
    text/javascript
    application/javascript
    application/x-javascript
    application/json
    application/xml
    application/xml+rss
    image/svg+xml;
gzip_vary on;

# Banned locations (only reached if the earlier PHP entry point regexes don't match)
location ~* (\.php$|\.htaccess$|\.git) {
    deny all;
}
EOL

    touch /etc/nginx/magento2_config/nginx74.conf
    cat > /etc/nginx/magento2_config/nginx74.conf <<EOL
root \$MAGE_ROOT/pub;

index index.php;
autoindex off;
charset UTF-8;
error_page 404 403 = /errors/404.php;
#add_header "X-UA-Compatible" "IE=Edge";


# Deny access to sensitive files
location /.user.ini {
    deny all;
}

# PHP entry point for setup application
location ~* ^/setup($|/) {
    root \$MAGE_ROOT;
    location ~ ^/setup/index.php {
        fastcgi_pass   unix:/var/run/php/php7.4-fpm.sock;

        fastcgi_param  PHP_FLAG  "session.auto_start=off \n suhosin.session.cryptua=off";
        fastcgi_param  PHP_VALUE "memory_limit=756M \n max_execution_time=600";
        fastcgi_read_timeout 600s;
        fastcgi_connect_timeout 600s;

        fastcgi_index  index.php;
        fastcgi_param  SCRIPT_FILENAME  \$document_root\$fastcgi_script_name;
        include        fastcgi_params;
    }

    location ~ ^/setup/(?!pub/). {
        deny all;
    }

    location ~ ^/setup/pub/ {
        add_header X-Frame-Options "SAMEORIGIN";
    }
}

# PHP entry point for update application
location ~* ^/update($|/) {
    root \$MAGE_ROOT;

    location ~ ^/update/index.php {
        fastcgi_split_path_info ^(/update/index.php)(/.+)$;
        fastcgi_pass   unix:/var/run/php/php7.4-fpm.sock;
        fastcgi_index  index.php;
        fastcgi_param  SCRIPT_FILENAME  \$document_root\$fastcgi_script_name;
        fastcgi_param  PATH_INFO        \$fastcgi_path_info;
        include        fastcgi_params;
    }

    # Deny everything but index.php
    location ~ ^/update/(?!pub/). {
        deny all;
    }

    location ~ ^/update/pub/ {
        add_header X-Frame-Options "SAMEORIGIN";
    }
}

location / {
    try_files \$uri \$uri/ /index.php\$is_args\$args;
}

location /pub/ {
    location ~ ^/pub/media/(downloadable|customer|import|custom_options|theme_customization/.*\.xml) {
        deny all;
    }
    alias \$MAGE_ROOT/pub/;
    add_header X-Frame-Options "SAMEORIGIN";
}

location /static/ {
    # Uncomment the following line in production mode
    # expires max;

    # Remove signature of the static files that is used to overcome the browser cache
    location ~ ^/static/version {
        rewrite ^/static/(version\d*/)?(.*)$ /static/\$2 last;
    }

    location ~* \.(ico|jpg|jpeg|png|gif|svg|js|css|swf|eot|ttf|otf|woff|woff2|html|json)$ {
        add_header Cache-Control "public";
        add_header X-Frame-Options "SAMEORIGIN";
        expires +1y;

        if (!-f \$request_filename) {
            rewrite ^/static/(version\d*/)?(.*)$ /static.php?resource=\$2 last;
        }
    }
    location ~* \.(zip|gz|gzip|bz2|csv|xml)$ {
        add_header Cache-Control "no-store";
        add_header X-Frame-Options "SAMEORIGIN";
        expires    off;

        if (!-f \$request_filename) {
           rewrite ^/static/(version\d*/)?(.*)$ /static.php?resource=\$2 last;
        }
    }
    if (!-f \$request_filename) {
        rewrite ^/static/(version\d*/)?(.*)$ /static.php?resource=\$2 last;
    }
    add_header X-Frame-Options "SAMEORIGIN";
}

location /media/ {
    try_files \$uri \$uri/ /get.php\$is_args\$args;

    location ~ ^/media/theme_customization/.*\.xml {
        deny all;
    }

    location ~* \.(ico|jpg|jpeg|png|gif|svg|js|css|swf|eot|ttf|otf|woff|woff2)$ {
        add_header Cache-Control "public";
        add_header X-Frame-Options "SAMEORIGIN";
        expires +1y;
        try_files \$uri \$uri/ /get.php\$is_args\$args;
    }
    location ~* \.(zip|gz|gzip|bz2|csv|xml)$ {
        add_header Cache-Control "no-store";
        add_header X-Frame-Options "SAMEORIGIN";
        expires    off;
        try_files \$uri \$uri/ /get.php\$is_args\$args;
    }
    add_header X-Frame-Options "SAMEORIGIN";
}

location /media/customer/ {
    deny all;
}

location /media/downloadable/ {
    deny all;
}

location /media/import/ {
    deny all;
}

location /media/custom_options/ {
    deny all;
}

location /errors/ {
    location ~* \.xml$ {
        deny all;
    }
}

# PHP entry point for main application
location ~ ^/(index|get|static|errors/report|errors/404|errors/503|health_check|opcache_.*|phpinfo_.*)\.php$ {
    try_files \$uri =404;
    fastcgi_pass   unix:/var/run/php/php7.4-fpm.sock;
    fastcgi_buffers 16 16k;
    fastcgi_buffer_size 32k;

    fastcgi_param  PHP_FLAG  "session.auto_start=off \n suhosin.session.cryptua=off";
    fastcgi_param  PHP_VALUE "memory_limit=756M \n max_execution_time=18000 \n session.save_path=";
    fastcgi_read_timeout 600s;
    fastcgi_connect_timeout 600s;

    fastcgi_index  index.php;
    fastcgi_param  SCRIPT_FILENAME  \$document_root\$fastcgi_script_name;
    include        fastcgi_params;
}

gzip on;
gzip_disable "msie6";

gzip_comp_level 6;
gzip_min_length 1100;
gzip_buffers 16 8k;
gzip_proxied any;
gzip_types
    text/plain
    text/css
    text/js
    text/xml
    text/javascript
    application/javascript
    application/x-javascript
    application/json
    application/xml
    application/xml+rss
    image/svg+xml;
gzip_vary on;

# Banned locations (only reached if the earlier PHP entry point regexes don't match)
location ~* (\.php$|\.phtml$|\.htaccess$|\.git) {
    deny all;
}
EOL

    touch /etc/nginx/sites-available/virtualhost.conf.sample
    cat > /etc/nginx/sites-available/virtualhost.conf.sample <<EOL

    #note: This is demo only, you should do the following steps:
    #cp virtualhost.conf.sample your-virtual-host.conf
    #sudo ln -s /etc/nginx/sites-available/your-virtual-host.conf /etc/nginx/sites-enabled/
    #service nginx restart

server {
   listen 80;

   #server_name your_virtual_site_here
   #After that, add 127.0.0.1 your_virtual_site_here into /etc/hosts
   server_name magento.dev;

   #set \$MAGE_ROOT as your project folder location, should be set to /home/${apache_user} to avoid permission issues
   set \$MAGE_ROOT /home/${apache_user}/your-folder-here;
   #set \$MAGE_DEBUG_SHOW_ARGS 1;

   #select only 1 according to php version which is used
   #include /etc/nginx/magento2_config/nginx74.conf;
   #include /etc/nginx/magento2_config/nginx73.conf;
   #include /etc/nginx/magento2_config/nginx72.conf;
   #include /etc/nginx/magento2_config/nginx70.conf;
}

EOL


    # Enable and start httpd service
    systemctl enable nginx.service
    systemctl restart nginx.service
}

f_mysql_config() {
    #create user
    mysql \
    -e "CREATE USER '${apache_user}'@'localhost' IDENTIFIED BY '${apache_user}';" \
    -e "GRANT ALL PRIVILEGES ON * . * TO '${apache_user}'@'localhost';" \
    -e "FLUSH PRIVILEGES;"
}

f_install_mysql() {
    echo "Preparing install mysql ..."
    sleep 1

    echo "Make sure mysql8 is removed when installing ubuntu 20.04"
    apt-get remove --purge mysql-server mysql-client mysql-common -y
    apt-get remove mysql-community-client-core -y
    apt-get remove mysql-community-server-core -y
    apt-get autoremove -y
    apt-get autoclean -y

    #hold mysql8 to avoid mysql8
    apt-mark hold mysql-client
    apt-mark hold mysql-server

    apt-get install software-properties-common -y
    apt-key adv --recv-keys --keyserver hkp://keyserver.ubuntu.com:80 0xF1656F24C74CD1D8
    sh -c "echo 'deb https://mirrors.evowise.com/mariadb/repo/10.2/ubuntu '$(lsb_release -cs)' main' > /etc/apt/sources.list.d/MariaDB102.list"

    apt-get update -y
    apt-get install mariadb-server mariadb-client -y
    f_mysql_config

    mysql --user=root <<_EOF_
        ALTER USER 'root'@'localhost' IDENTIFIED BY 'root';
        DELETE FROM mysql.user WHERE User='';
        DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
        DROP DATABASE IF EXISTS test;
        DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
        FLUSH PRIVILEGES;
_EOF_

}

f_install_php() {

    echo "Preparing install php ..."
    sleep 1

    apt install software-properties-common -y
    add-apt-repository ppa:ondrej/php -y
    apt update

    echo "install php7.4 ..."
    sleep 1
    apt install -y php7.4-fpm php7.4-bcmath php7.4-cli php7.4-common php7.4-gd php7.4-intl php7.4-json php7.4-mbstring  php7.4-xmlrpc php7.4-xml php7.4-mysql php7.4-soap php7.4-zip php7.4-curl

    sed -i "s/user = www-data/user = ${apache_user}/g" /etc/php/7.4/fpm/pool.d/www.conf
    sed -i "s/group = www-data/group = ${apache_user}/g" /etc/php/7.4/fpm/pool.d/www.conf
    sed -i "s/listen.owner = www-data/listen.owner = ${apache_user}/g" /etc/php/7.4/fpm/pool.d/www.conf
    sed -i "s/listen.group = www-data/listen.group = ${apache_user}/g" /etc/php/7.4/fpm/pool.d/www.conf
    sed -i "s/zend_extension=opcache.so/;zend_extension=opcache.so/g" /etc/php/7.4/mods-available/opcache.ini
    sed -i "s/zend_extension=xdebug.so/;zend_extension=xdebug.so/g" /etc/php/7.4/mods-available/xdebug.ini

    echo "install php7.3 ..."
    sleep 1
    apt install -y php7.3-fpm php7.3-bcmath php7.3-cli php7.3-common php7.3-gd php7.3-intl php7.3-json php7.3-mbstring  php7.3-xmlrpc php7.3-xml php7.3-mysql php7.3-soap php7.3-zip php7.3-curl

    sed -i "s/user = www-data/user = ${apache_user}/g" /etc/php/7.3/fpm/pool.d/www.conf
    sed -i "s/group = www-data/group = ${apache_user}/g" /etc/php/7.3/fpm/pool.d/www.conf
    sed -i "s/listen.owner = www-data/listen.owner = ${apache_user}/g" /etc/php/7.3/fpm/pool.d/www.conf
    sed -i "s/listen.group = www-data/listen.group = ${apache_user}/g" /etc/php/7.3/fpm/pool.d/www.conf
    sed -i "s/zend_extension=opcache.so/;zend_extension=opcache.so/g" /etc/php/7.3/mods-available/opcache.ini
    sed -i "s/zend_extension=xdebug.so/;zend_extension=xdebug.so/g" /etc/php/7.3/mods-available/xdebug.ini

    echo "install php7.2 ..."
    sleep 1
    apt install -y php7.2-fpm php7.2-bcmath php7.2-cli php7.2-common php7.2-gd php7.2-intl php7.2-json php7.2-mbstring  php7.2-xmlrpc php7.2-xml php7.2-mysql php7.2-soap php7.2-zip php7.2-curl

    sed -i "s/user = www-data/user = ${apache_user}/g" /etc/php/7.2/fpm/pool.d/www.conf
    sed -i "s/group = www-data/group = ${apache_user}/g" /etc/php/7.2/fpm/pool.d/www.conf
    sed -i "s/listen.owner = www-data/listen.owner = ${apache_user}/g" /etc/php/7.2/fpm/pool.d/www.conf
    sed -i "s/listen.group = www-data/listen.group = ${apache_user}/g" /etc/php/7.2/fpm/pool.d/www.conf
    sed -i "s/zend_extension=opcache.so/;zend_extension=opcache.so/g" /etc/php/7.2/mods-available/opcache.ini
    sed -i "s/zend_extension=xdebug.so/;zend_extension=xdebug.so/g" /etc/php/7.2/mods-available/xdebug.ini

    echo "install php7.1 ..."
    sleep 1
    apt install -y php7.1-fpm php7.1-bcmath php7.1-cli php7.1-common php7.1-gd php7.1-intl php7.1-json php7.1-mbstring  php7.1-xmlrpc php7.1-xml php7.1-mysql php7.1-soap php7.1-zip php7.1-curl php7.1-mcrypt
    sed -i "s/user = www-data/user = ${apache_user}/g" /etc/php/7.1/fpm/pool.d/www.conf
    sed -i "s/group = www-data/group = ${apache_user}/g" /etc/php/7.1/fpm/pool.d/www.conf
    sed -i "s/listen.owner = www-data/listen.owner = ${apache_user}/g" /etc/php/7.1/fpm/pool.d/www.conf
    sed -i "s/listen.group = www-data/listen.group = ${apache_user}/g" /etc/php/7.1/fpm/pool.d/www.conf
    sed -i "s/zend_extension=opcache.so/;zend_extension=opcache.so/g" /etc/php/7.1/mods-available/opcache.ini
    sed -i "s/zend_extension=xdebug.so/;zend_extension=xdebug.so/g" /etc/php/7.1/mods-available/xdebug.ini

    echo "install php7.0 ..."
    sleep 1
    apt install -y php7.0-fpm php7.0-bcmath php7.0-cli php7.0-common php7.0-gd php7.0-intl php7.0-json php7.0-mbstring  php7.0-xmlrpc php7.0-xml php7.0-mysql php7.0-soap php7.0-zip php7.0-curl php7.0-mcrypt

    sed -i "s/user = www-data/user = ${apache_user}/g" /etc/php/7.0/fpm/pool.d/www.conf
    sed -i "s/group = www-data/group = ${apache_user}/g" /etc/php/7.0/fpm/pool.d/www.conf
    sed -i "s/listen.owner = www-data/listen.owner = ${apache_user}/g" /etc/php/7.0/fpm/pool.d/www.conf
    sed -i "s/listen.group = www-data/listen.group = ${apache_user}/g" /etc/php/7.0/fpm/pool.d/www.conf
    sed -i "s/zend_extension=opcache.so/;zend_extension=opcache.so/g" /etc/php/7.0/mods-available/opcache.ini
    sed -i "s/zend_extension=xdebug.so/;zend_extension=xdebug.so/g" /etc/php/7.0/mods-available/xdebug.ini

    #increase memory limit
    touch /etc/php/7.4/mods-available/50-php_settings.ini
    touch /etc/php/7.3/mods-available/50-php_settings.ini
    touch /etc/php/7.2/mods-available/50-php_settings.ini
    touch /etc/php/7.1/mods-available/50-php_settings.ini
    touch /etc/php/7.0/mods-available/50-php_settings.ini

    > /etc/php/7.4/mods-available/50-php_settings.ini
    > /etc/php/7.3/mods-available/50-php_settings.ini
    > /etc/php/7.2/mods-available/50-php_settings.ini
    > /etc/php/7.1/mods-available/50-php_settings.ini
    > /etc/php/7.0/mods-available/50-php_settings.ini

    cat > /etc/php/7.4/mods-available/50-php_settings.ini <<'EOF'
date.timezone = Asia/Ho_Chi_Minh
expose_php = Off
memory_limit = 2048M
max_input_vars = 10000
asp_tags = off
EOF

    cat > /etc/php/7.3/mods-available/50-php_settings.ini <<'EOF'
date.timezone = Asia/Ho_Chi_Minh
expose_php = Off
memory_limit = 2048M
max_input_vars = 10000
asp_tags = off
EOF

    cat > /etc/php/7.2/mods-available/50-php_settings.ini <<'EOF'
date.timezone = Asia/Ho_Chi_Minh
expose_php = Off
memory_limit = 2048M
max_input_vars = 10000
asp_tags = off
EOF

    cat > /etc/php/7.1/mods-available/50-php_settings.ini <<'EOF'
date.timezone = Asia/Ho_Chi_Minh
expose_php = Off
memory_limit = 2048M
max_input_vars = 10000
asp_tags = off
EOF

    cat > /etc/php/7.0/mods-available/50-php_settings.ini <<'EOF'
date.timezone = Asia/Ho_Chi_Minh
expose_php = Off
memory_limit = 2048M
max_input_vars = 10000
asp_tags = off
EOF

    #grant permission on session folder
    chmod -R 777 /var/lib/php/sessions

    service php7.4-fpm restart
    service php7.3-fpm restart
    service php7.2-fpm restart
    service php7.1-fpm restart
    service php7.0-fpm restart

    update-alternatives --set php /usr/bin/php7.4
}

f_prepare_magento() {

echo "Preparing install composer ..."
sleep 1

#install composer
php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
php composer-setup.php --install-dir=/usr/local/bin --filename=composer
php -r "unlink('composer-setup.php');"

chmod +x /usr/local/bin/composer
su ${apache_user} -c "composer global require hirak/prestissimo"

#setup trust host
mkdir -p /home/${apache_user}/.ssh
printf "Host github.com\n\tStrictHostKeyChecking no\n" >> /home/${apache_user}/.ssh/config
printf "Host repo.magento.com\n\tStrictHostKeyChecking no\n" >> /home/${apache_user}/.ssh/config

chmod 600 /home/${apache_user}/.ssh/config

#install modman
curl -SL https://raw.githubusercontent.com/colinmollenhour/modman/master/modman -o modman
mv ./modman /usr/local/bin/modman
chmod +x /usr/local/bin/modman

}

# Function install LAMP stack
f_install_lamp () {
    f_install_mysql
    f_install_php
    f_install_nginx
    f_prepare_magento

    chown -R ${apache_user}:${apache_user} /home/${apache_user}
}

f_install_adminer(){
    echo "Installing adminer ..."
    sleep 1

    cd /var/www/html
    wget -O adminer.php - https://github.com/vrana/adminer/releases/download/v4.7.7/adminer-4.7.7-mysql.php
    chmod 777 adminer.php

    echo "configuring nginx to recognize adminer ..."
    > /etc/nginx/sites-available/default

    cat > /etc/nginx/sites-available/default <<EOL
server {
	listen 80 default_server;
	listen [::]:80 default_server;

	root /var/www/html;

	index index.html index.htm index.nginx-debian.html index.php;

	server_name _;

	location ~ \.php$ {
            include snippets/fastcgi-php.conf;
    	    fastcgi_pass unix:/var/run/php/php7.2-fpm.sock;
        }

	location / {
		# First attempt to serve request as file, then
		# as directory, then fall back to displaying a 404.
		try_files \$uri \$uri/ =404;
	}

}
EOL

    service nginx restart
}

f_install_extra_features() {
    f_install_adminer
}

f_messages(){
    echo "
    1. Mysql
        - username: ${apache_user} - password: ${apache_user}
        - Using localhost/adminer.php to access
        - root password: root / root in case you need.

    2. Phpstorm
        - first run: bash /home/${apache_user}/phpstorm/bin/phpstorm.sh

    3. Nginx
        - nginx is prepared for virtual host and support magento configuration with php-fpm7.0, php-fpm7.2, php-fpm7.3, php-fpm7.4
        - to setup virtual host, go to /etc/nginx/sites-available, following virtualhost.conf.sample

    4. Php
        - By default php-cli is set to php7.3
        - run below script in order to switch php-version
            sudo update-alternatives --set php /usr/bin/php7.0
            sudo update-alternatives --set php /usr/bin/php7.1
            sudo update-alternatives --set php /usr/bin/php7.2
            sudo update-alternatives --set php /usr/bin/php7.3
            sudo update-alternatives --set php /usr/bin/php7.4
"

}

# The sub main function, use to call necessary functions of installation
f_sub_main () {
    f_update_os
    f_install_lamp
    f_install_extra_features

    echo "Final chown to make sure everything running well ..."
    chown -R ${apache_user}:${apache_user} /home/${apache_user}

    #update vm.max_map_count=262144 to match with ES configuration
    sysctl -w vm.max_map_count=262144
    sysctl -w fs.inotify.max_user_watches=524288

    #make sure this options still work after reboot
    echo "fs.inotify.max_user_watches = 524288" >> /etc/sysctl.d/99-sysctl.conf
    echo "vm.max_map_count = 262144" >> /etc/sysctl.d/99-sysctl.conf

    f_messages
}

# The main function
f_main () {
    f_check_root
}
f_main

exit 0
