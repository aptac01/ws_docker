#!/bin/bash
# опциональная установка grunt

# завершить  скрипт если любая команда завершилась не с 0 статусом
set -e

if [[ "${INSTALL_GRUNT}" == "1" ]];
then

  curl -sL https://deb.nodesource.com/setup_22.x | bash -
  apt update -y
  apt install nodejs -y

  cd ${PRE_WORKDIR}/grunt

  # + вместо /
  sed -i "s+WORKDIR+${WORKDIR}+g" "profile.json"

  npm install
  npm install grunt-cli -g

  cd ${WORKDIR}
fi

$@