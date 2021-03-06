#!/bin/bash

set -x

while ! mysql -hdb -uroot -p$MYSQL_ROOT_PASSWORD -e "show databases" >/dev/null; do
    echo "Wait for the db";
    sleep 1
done

TULEAP_INSTALL_TIME="false"
if [ ! -f /data/etc/tuleap/conf/local.inc ]; then
    TULEAP_INSTALL_TIME="true"
    set -e

    # If tuleap directory is not in data, assume it's first boot and move
    # everything in the mounted dir
    ./boot-install.sh
fi

# Fix path
./boot-fixpath.sh

# Align data ownership with images uids/gids
./fix-owners.sh

# Update DB location
sed -i "s/^host.*/host db/" /etc/libnss-mysql.cfg
sed -i "s/^\$sys_dbhost.*/\$sys_dbhost=\"db\";/" /etc/tuleap/conf/database.inc

# Update LDAP location
sed -i "s/^\$sys_ldap_server.*/\$sys_ldap_server = \"ldap:\/\/ldap\";/" /etc/tuleap/plugins/ldap/etc/ldap.inc
sed -i "s/^\$sys_ldap_write_server.*/\$sys_ldap_write_server = \"ldap:\/\/ldap\";/" /etc/tuleap/plugins/ldap/etc/ldap.inc
[ -n "$LDAP_MANAGER_PASSWORD" ] && sed -i "s/^\$sys_ldap_write_password.*/\$sys_ldap_write_password = \"$LDAP_MANAGER_PASSWORD\";/" /etc/tuleap/plugins/ldap/etc/ldap.inc

# Allow configuration update at boot time
./boot-update-config.sh

# Update php config
perl -pi -e "s%^short_open_tag = Off%short_open_tag = On%" /etc/php.ini
perl -pi -e "s%^;date.timezone =%date.timezone = Europe/Paris%" /etc/php.ini

# Update Postfix config
perl -pi -e "s%^#myhostname = host.domain.tld%myhostname = ${VIRTUAL_HOST//_}%" /etc/postfix/main.cf
perl -pi -e "s%^alias_maps = hash:/etc/aliases%alias_maps = hash:/etc/aliases,hash:/etc/aliases.codendi%" /etc/postfix/main.cf
perl -pi -e "s%^alias_database = hash:/etc/aliases%alias_database = hash:/etc/aliases,hash:/etc/aliases.codendi%" /etc/postfix/main.cf
perl -pi -e "s%^#recipient_delimiter = %recipient_delimiter = %" /etc/postfix/main.cf

# Email whitelist
./whitelist_emails.sh
echo "transport_maps = hash:/etc/postfix/transport" >> /etc/postfix/main.cf

# Update nscd config
perl -pi -e "s%enable-cache[\t ]+group[\t ]+yes%enable-cache group no%" /etc/nscd.conf

if [ "$TULEAP_INSTALL_TIME" == "false" ]; then
    # It seems there is no way to have nscd in foreground
    /usr/sbin/nscd

    # DB upgrade (after config as we might depends on it)
    ./boot-upgrade.sh
fi

# Activate backend/crontab
/etc/init.d/tuleap start

exec supervisord -n
