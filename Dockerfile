FROM alpine:3.7

LABEL maintainer="Robert C Smith <robert@robertcsmith.me>"

ENV PHP_VERSION=7.2.10
ENV PHP_INI_DIR="/usr/local/etc/php"
ENV PHP_CFLAGS="-fstack-protector-strong -fpic -fpie -O2"
ENV PHP_CPPFLAGS="$PHP_CFLAGS"
ENV PHP_LDFLAGS="-Wl,-O1 -Wl,--hash-style=both -pie"
ENV PHP_URL="https://secure.php.net/get/php-7.2.10.tar.xz/from/this/mirror"
ENV PHP_SHA256="01c2154a3a8e3c0818acbdbc1a956832c828a0380ce6d1d14fea495ea21804f0"

COPY docker-php-ext-* docker-php-entrypoint /usr/local/bin/

# 82 is the standard uid/gid for "www-data" in Alpine
# 101 is the default group id for nginx across all platforms as of v1.12
# http://git.alpinelinux.org/cgit/aports/tree/main/nginx-initscripts/nginx-initscripts.pre-install?h=v3.3.2
RUN set -xe; \
	addgroup -g 82 -S www-data; \
	addgroup -g 101 -S nginx; \
	adduser -S -H -u 82 -G nginx www-data; \
# Correct file permissions
#	chown www-data:nginx /docker-php-source /docker-php-ext-* /docker-php-entrypoint; \
#	chmod 0777 /docker-php-source /docker-php-ext-* /docker-php-entrypoint; \
# This appears in the official docker library at this point
	mkdir -p $PHP_INI_DIR/conf.d; \
# persistent / runtime deps
	apk add --no-cache --virtual .persistent-deps \
		bash \
		ca-certificates \
		curl \
		tar \
		xz \
		libressl \
	; \
# fetch
	mkdir -p /usr/src; \
	cd /usr/src; \
	wget -O php.tar.xz "$PHP_URL"; \
	if [ -n "$PHP_SHA256" ]; then \
		echo "$PHP_SHA256 *php.tar.xz" | sha256sum -c -; \
	fi;

RUN set -xe \
# build deps
	&& apk add --no-cache --virtual .build-deps \
		autoconf \
		coreutils \
		curl-dev \
		libedit-dev \
		libressl-dev \
		libsodium-dev \
		libxml2-dev \
		sqlite-dev \
		dpkg-dev dpkg \
		file \
		g++ \
		gcc \
		libc-dev \
		make \
		musl-dev \
		pkgconf \
		re2c \
	&& export CFLAGS="$PHP_CFLAGS" \
	&& export CPPFLAGS="$PHP_CPPFLAGS" \
	&& export LDFLAGS="$PHP_LDFLAGS"

RUN set -xe; \
	mkdir -p /usr/src/php; \
	if [ ! -f /usr/src/php/.docker-extracted ]; then \
		tar -Jxf /usr/src/php.tar.xz -C /usr/src/php --strip-components=1; \
		touch /usr/src/php/.docker-extracted; \
	fi;

RUN set -xe \
# Step into /usr/src/php in order to configure
	&& cd /usr/src/php \
	&& ./configure \
		--build="x86_64-linux-gnu" \
		--with-config-file-path="/usr/local/etc/php" \
		--with-config-file-scan-dir="/usr/local/etc/php/conf.d" \
\
		--enable-bcmath=shared \
		--enable-option-checking=fatal \
		--enable-mbstring \
		--enable-mysqlnd \
		--enable-fpm \
		--enable-zip \
\
		--with-fpm-user="www-data" \
		--with-fpm-group="nginx" \
		--with-mhash \
		--with-sodium=shared \
		--with-curl=shared \
		--with-libedit \
		--with-openssl \
		--with-zlib \
\
		--disable-cgi \
		--disable-short-tags \
\
	&& make -j "$(nproc)" \
	&& make install \
	&& { find /usr/local/bin / -type f -perm +0111 -exec strip --strip-all '{}' + || true; } \
	&& make clean \
\
	&& cp -v php.ini-* "$PHP_INI_DIR/" \
\
	&& docker-php-ext-enable sodium \
	&& docker-php-ext-configure gd --with-freetype-dir="/usr/include/" --with-jpeg-dir="/usr/include/" \
	&& docker-php-ext-install \
		bcmath \
		ctype \
		dom \
		gd \
		hash \
		iconv \
		intl \
		json \
		libxml \
		mbstring \
		mcrypt \
		mysqli \
		opcache \
		openssh \
		openssl \
		pdo_mysql \
		pdo_sqlite \
		SimpleXML \
		SPL \
		soap \
		xsl \
		zip \
# Runtime deps
	&& runDeps="$(scanelf --needed --nobanner --format '%n#p' --recursive /usr/local | tr ',' '\n' | sort -u | awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' )" \
	&& apk add --no-cache --virtual .php-rundeps $runDeps php7-redis \
# Update pecl to prepare xdebug and ssh install
    && pecl update-channels \
    && rm -rf /tmp/pear ~/.pearrc \
# Cleanup
	&& apk del .build-deps \
	&& docker-php-source delete \
	&& rm -rf /var/www/* \
	&& cd / \
# Directory prep
	&& mkdir -p /var/run/php/ /usr/local/etc/php-fpm.d/ /var/www/html/var/ \
	&& chown -R www-data:nginx /var/run/php/ /var/www/ \
	&& chmod -R 0660 /var/run/php/ \
	&& chmod -R 0770 /var/www/

COPY files/php.ini      ${PHP_INI_DIR}/php.ini
COPY files/php-fpm.conf /usr/local/etc/php-fpm.conf
COPY files/www.conf     /usr/local/etc/php-fpm.d/www.conf

USER www-data:nginx

VOLUME /var/run/php/
VOLUME /var/www/

ENTRYPOINT ["docker-php-entrypoint"]

CMD ["php-fpm"]
