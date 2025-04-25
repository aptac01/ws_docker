# SuperServer doesn't include an embedded engine in its build
# so we have to launch firebird in the background while this script runs
# fbtry and fbkill are used to quietly launch and remove firebird in the
# background and make sure its available before managing users/creating the db
pidfile=/var/run/firebird/firebird.pid

fbtry() {
    if [ -f $pidfile -a -d "/proc/`cat $pidfile`" ];  then
        return
    fi;
    ${PREFIX}/bin/fbguard -pidfile $pidfile -daemon
    # Try every second to access the firebird port, timout after 10 seconds and just hope it came up on a different port
    timeout 10 sh -c 'until nc -z $0 $1; do sleep 1; done' localhost 3050
}
fbkill() {
    if [ -f $pidfile ]; then
        pid=`cat $pidfile`
        kill "$pid" || true
        while kill -0 "$pid" 2> /dev/null; do
            sleep 0.5
        done
    fi
}

createNewPassword() {
    # openssl generates random data.
        openssl </dev/null >/dev/null 2>/dev/null
    if [ $? -eq 0 ]
    then
        # We generate 40 random chars, strip any '/''s and get the first 20
        NewPasswd=`openssl rand -base64 40 | tr -d '/' | cut -c1-20`
    fi

        # If openssl is missing...
        if [ -z "$NewPasswd" ]
        then
                NewPasswd=`dd if=/dev/urandom bs=10 count=1 2>/dev/null | od -x | head -n 1 | tr -d ' ' | cut -c8-27`
        fi

        # On some systems even this routines may be missing. So if
        # the specific one isn't available then keep the original password.
    if [ -z "$NewPasswd" ]
    then
        NewPasswd="masterkey"
    fi

        echo "$NewPasswd"
}

# usage: file_env VAR [DEFAULT]
#    ie: file_env 'XYZ_DB_PASSWORD' 'example'
# (will allow for "$XYZ_DB_PASSWORD_FILE" to fill in the value of
#  "$XYZ_DB_PASSWORD" from a file, especially for Docker's secrets feature)
file_env() {
    local var="$1"
    local fileVar="${var}_FILE"
    local def="${2:-}"
    if [ "${!var:-}" ] && [ "${!fileVar:-}" ]; then
        echo >&2 "error: both $var and $fileVar are set (but are exclusive)"
        exit 1
    fi
    local val="$def"
    if [ "${!var:-}" ]; then
        val="${!var}"
    elif [ "${!fileVar:-}" ]; then
        val="$(< "${!fileVar}")"
    fi
    export "$var"="$val"
    unset "$fileVar"
}

read_var() {
    local file="$1"
    local var="$2"

    echo $(source "${file}"; printf "%s" "${!var}");
}

generate_firebird_password() {

    if [ ! -f "${VOLUME}/system/security2.fdb" ]; then
        cp ${PREFIX}/skel/security2.fdb ${VOLUME}/system/security2.fdb
        chown firebird.firebird ${VOLUME}/system/security2.fdb

        file_env 'ISC_PASSWORD'
        if [ -z ${ISC_PASSWORD} ]; then
           ISC_PASSWORD=$(createNewPassword)
           echo "setting 'SYSDBA' password to '${ISC_PASSWORD}'"
        fi

        fbtry

        ${PREFIX}/bin/gsec -user SYSDBA -password "$(read_var ${VOLUME}/etc/SYSDBA.password ISC_PASSWD)" -modify SYSDBA -pw ${ISC_PASSWORD}
        #    ${PREFIX}/bin/isql -user sysdba employee <<EOL
        #create or alter user SYSDBA password '${ISC_PASSWORD}';
        #commit;
        #quit;
        #EOL

        cat > ${VOLUME}/etc/SYSDBA.password <<EOL
# Firebird generated password for user SYSDBA is:

ISC_USER=SYSDBA
ISC_PASSWD=${ISC_PASSWORD}
# Your password can be changed to a more suitable one using the
# ${PREFIX}/bin/gsec utility.

# Set for interop with 3.0
ISC_PASSWORD=${ISC_PASSWORD}
EOL

        fbkill
    fi

    if [ -f "${VOLUME}/etc/SYSDBA.password" ]; then
        source ${VOLUME}/etc/SYSDBA.password
    fi;
}

# создание всех юзеров через gsec
create_db_users() {

    echo "...создаём пользователей БД..."

    create_db_user user1 1

    create_db_user user2 1

    echo "...готово..."
}

# создание одного юзера через gsec
# user_name - название юзера
# silent - если 0 или не передать - будет показано сообщение об ошибке в случае если пользователь уже есть
create_db_user() {
    local user_name="$1"
    local silent="$2"

    # Проверяем что юзер есть в базе
    user_exists=$(check_db_user_exists ${user_name})

    if [[ "${silent}" -eq 0 && ${user_exists} ]];
    then
        echo "Попытка создать пользователя \"${user_name}\", но он уже есть в security-базе."
        echo "Удалите пользователя из терминала командой"
        echo "\"${PREFIX}/bin/gsec -user SYSDBA -password %password% -delete ${user_name}\""
        echo "Или SQL запросом"
        echo "\"DROP USER ${user_name}\""
        echo "Или удалите файл ${VOLUME}/system/security2.fdb "
        echo "и перезапустите образ compose"

        return 0
    fi

    if [[ "${silent}" -eq 1 && ${user_exists} ]];
    then
        echo "...${user_name} уже создан..."

        return 0
    fi

    local passw_file_name=${VOLUME}/etc/${user_name}.password

    if [ -f "${passw_file_name}" ];
    then

        local passw=$(<${passw_file_name})
    else

        local passw=$(createNewPassword)
        echo ${passw} > ${passw_file_name}
        echo "setting '${user_name}' password to '${passw}'"
    fi

    ${PREFIX}/bin/gsec -user SYSDBA -password ${ISC_PASSWORD} -add ${user_name} -pw ${passw}

    echo "...создали ${user_name}..."
}

check_db_user_exists() {
    local user="$1"
    echo "$(${PREFIX}/bin/gsec -user SYSDBA -password ${ISC_PASSWORD} -display ${user})"
}

# добавляет алиас БД в нужный файл
add_alias() {
    local alias="$1"
    local db_path="$2"

    echo "
${alias} = ${VOLUME}${db_path}" >> ${VOLUME}/etc/aliases.conf
}

# тут были еще функции, но я их удалил