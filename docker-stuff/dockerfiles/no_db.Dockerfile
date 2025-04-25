# php7.4_apache_debian11_composer

FROM  php:7.4.33-apache-bullseye

ARG INSTALL_GRUNT
ENV INSTALL_GRUNT=${INSTALL_GRUNT:-"0"}

ENV ADMIN_EMAIL webmaster@localhost
ENV PHP_TIME_ZONE Asia/Barnaul
ENV PHP_MEMORY_LIMIT 256M
ENV PHP_UPLOAD_MAX_FILESIZE 32M
ENV PHP_POST_MAX_SIZE 32M
ENV TZ=Asia/Barnaul
ENV PRE_WORKDIR /var/www
ENV WORKDIR ${PRE_WORKDIR}/webstac

# -----
# Подключаем php'шный репо.
# Разраб PHP заблокировал РФ по ip и сменил gpg ключ
# https://github.com/oerdnj/deb.sury.org/issues/2155
# ключ в файле - с его сайта, скачанный из под vpn (https://packages.sury.org/php/apt.gpg), скачан 05.09.2024
# репо - какое-то зеркало из интернета
# -----
COPY default-configs/no_db/sury.org.key.gpg /etc/apt/trusted.gpg.d/php.gpg
RUN apt-get update \
  && apt-get install -y -f apt-transport-https \
        lsb-release \
        ca-certificates \
  && sh -c 'echo "deb https://ftp.mpi-inf.mpg.de/mirrors/linux/mirror/deb.sury.org/repositories/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list' \
  && apt update

RUN apt-get install -y -f \
        libicu-dev \
		libjpeg-dev \
		libfreetype6-dev \
		libmagickwand-dev \
		libonig-dev \
		libpng-dev \
		libpq-dev \
		libwebp-dev \
		libxml2-dev \
		libzip-dev \
        libcurl4 \
        libcurl4-openssl-dev \
        pkg-config \
		acl \
		cron \
		curl \
		git \
		zip \
		zlib1g-dev \
        mc \
	&& apt-get clean \
	&& rm -rf /var/lib/apt/lists/*

RUN pecl install imagick \
	&& docker-php-ext-configure gd \
		--with-freetype \
		--with-jpeg \
		--with-webp \
	&& docker-php-ext-configure pgsql -with-pgsql=/usr/local/pgsql \
	&& docker-php-ext-configure bcmath --enable-bcmath \
	&& docker-php-ext-install \
		bcmath \
		exif \
		gd \
		gettext \
		intl \
		mysqli \
		opcache \
		pdo_mysql \
		pdo_pgsql \
		pgsql \
		zip \
        mbstring \
        curl \
	&& docker-php-ext-enable \
		imagick

RUN pecl install xdebug-3.1.3 \
	&& docker-php-ext-enable xdebug

# -----
# ставим и настраиваем composer
# -----

RUN curl -sS https://getcomposer.org/installer | php \
	&& mv composer.phar /usr/local/bin/composer \
	&& composer self-update

# -----
# Ставим расширение interbase в php (драйвер для firebird'а)
# этот кусок взял отсюда - https://github.com/tina4stack/tina4-php/blob/master/dockers/php7.4/Dockerfile
# -----

RUN apt-get update
RUN apt-get install -y firebird-dev
RUN git clone --depth 1 --branch v3.0.1 https://github.com/FirebirdSQL/php-firebird.git
WORKDIR php-firebird
RUN phpize
RUN CPPFLAGS=-I/usr/include/firebird ./configure
RUN make
RUN make install
RUN echo "extension=interbase.so" > /usr/local/etc/php/conf.d/docker-php-ext-interbase.ini

# -----
# конфиги apache и php
# -----
COPY default-configs/no_db/000-default.conf $APACHE_CONFDIR/sites-available/000-default.conf
COPY default-configs/no_db/php-override.ini $PHP_INI_DIR/conf.d/php-override.ini

ARG SESS_DIR=/var/lib/php/sessions
RUN mkdir -p $SESS_DIR \
    && chown -R www-data:www-data $SESS_DIR \
    && chmod 770 $SESS_DIR

# -----
# настраиваем apache
# -----

RUN a2enmod rewrite \
    && a2enmod authz_core \
	&& mkdir -p /etc/cron.d/ \
    && ln -sf /dev/stderr /var/log/apache2/error.log

# -----
# Настраиваем наше приложение
# -----

# текущая папка внутри контейнера
WORKDIR ${WORKDIR}

# копируем из текущей папки на хосте в текущую папку контейнера
COPY .. .

# -----
# настройка и установка node и grunt
# -----

RUN mkdir ${PRE_WORKDIR}/grunt

COPY default-configs/no_db/grunt/ ${PRE_WORKDIR}/grunt
RUN default-configs/no_db/_install_grunt.sh

# открываем порты в контейнере
EXPOSE 80