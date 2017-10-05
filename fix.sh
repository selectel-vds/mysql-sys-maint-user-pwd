#!/bin/bash

# Check the bash shell script is being run by root
if [ "${UID}" -ne 0 ]; then
	    cat <<EOF
This script must be run as root. Please run:
    sudo bash $(readlink -f ${0})
EOF
fi

cat <<EOF
This script changes the MySQL system maintenance user password.

This process entails:
- reading the current password
- generating a new password
- updating the password in MySQL
- updating the password in /etc/mysql/debian.cnf
- restarting MySQL

EOF

if [ ! -f /etc/mysql/debian.cnf ]; then
    echo "This system is not affected."
    exit 0
fi

# Start logging
log_file="/root/mysql-upd-pwd-$(date +%d_%m_%Y).log"
exec > >(tee ${log_file}) 2>&1
echo "Logging to ${log_file}"

# Change password for debian-sys-maint
dsm_usr="$(awk '/user/{print $NF; exit;}' /etc/mysql/debian.cnf)"
old_dsm_usr_pwd="$(awk '/password/{print $NF; exit;}' /etc/mysql/debian.cnf)"
rndm_dsm_pwd="$(< /dev/urandom tr -dc A-Za-z0-9 | head -c 32;echo)"

# Check Codename and selection of appropriate commands
codename=$(lsb_release -c -s)
if [ "${codename}" == "trusty" ]; then
	restart_cmd="/sbin/restart mysql"
	passwd_update_cmd="use mysql; update user set password=password('${rndm_dsm_pwd}') where user='${dsm_usr}'; GRANT ALL PRIVILEGES ON *.* TO '${dsm_usr}'@'localhost' IDENTIFIED BY '${rndm_dsm_pwd}'"
elif [ "${codename}" == "xenial" ]; then
	restart_cmd="/bin/systemctl restart mysql.service"
	passwd_update_cmd="ALTER USER '${dsm_usr}'@'localhost' IDENTIFIED BY '${rndm_dsm_pwd}'"
else
	echo "This script doesn't support your distribution"
fi
	
echo "Updating ${dsm_usr} with new password"
mysql -u${dsm_usr} -p${old_dsm_usr_pwd} -e "${passwd_update_cmd};"

# Backuping previous configuration file
cp /etc/mysql/debian.cnf /etc/mysql/debian.cnf.bak-$(date +%d_%m_%Y)

# Update debian.cnf with new password
cat > /etc/mysql/debian.cnf <<EOF
# Automatically generated for Debian scripts. DO NOT TOUCH!
[client]
host     = localhost
user     = ${dsm_usr}
password = ${rndm_dsm_pwd}
socket   = /var/run/mysqld/mysqld.sock
[mysql_upgrade]
host     = localhost
user     = ${dsm_usr}
password = ${rndm_dsm_pwd}
socket   = /var/run/mysqld/mysqld.sock
EOF

# Restart your MySQL to apply changes
${restart_cmd}

# Finish
echo "Done. Your system is no longer affected."