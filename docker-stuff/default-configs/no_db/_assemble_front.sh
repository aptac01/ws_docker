#!/bin/bash
# сборка фронта через grunt

# завершить  скрипт если любая команда завершилась не с 0 статусом
set -e

if [[ "${INSTALL_GRUNT}" == "1" ]];
then

  cd ${PRE_WORKDIR}/grunt

  grunt assemble --force

  echo "... собрали фронт ..."

  cd ${WORKDIR}

else

  echo "... grunt не установлен, пропускаем сборку фронта..."

fi

$@