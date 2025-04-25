#!/bin/bash

# завершить  скрипт если любая команда завершилась не с 0 статусом
set -e

# куча вспомогательных функций
source ${PREFIX}/docker-functions.sh
source ${PREFIX}/create-db1.sh
source ${PREFIX}/create-db2.sh
source ${PREFIX}/create-db3.sh

# Create any missing folders
mkdir -p "${VOLUME}/system"
mkdir -p "${VOLUME}/log"
mkdir -p "${VOLUME}/data"
if [[ ! -e "${VOLUME}/etc/" ]]; then
    cp -R "${PREFIX}/skel/etc" "${VOLUME}/"
fi

# если запускаем контейнер в первый раз - генерим пароль и записываем его в файлик
generate_firebird_password

fbtry

# опционально создаём пользователей
create_db_users

# создаём и настраиваем все нужные базы
create_db1
create_db2
create_db3

fbkill

$@