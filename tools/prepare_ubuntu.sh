#!/bin/sh

set -e

pg_version="9.1"

###############################################################################
# create admin user
###############################################################################
groupadd -r -f admin
if [ ! $(grep '^admin:' /etc/passwd) ]; then
    useradd -r -m -g admin admin
    chsh -s /bin/bash admin
fi
if [ ! -d /home/admin/.ssh ]; then
    mkdir /home/admin/.ssh
    chown admin:admin /home/admin/.ssh
    chmod 700 /home/admin/.ssh
fi

if [ -e .adminpass ]; then
    tr -d '\n' < .adminpass | chpasswd
    chown admin:admin .adminpass;
    chmod 600 .adminpass;
else
    # ssh-only authentication
    passwd -l admin
fi

###############################################################################
# update sudoers file
###############################################################################
cat > /etc/sudoers <<EOF
#
# This file MUST be edited with the 'visudo' command as root.
#
# Please consider adding local content in /etc/sudoers.d/ instead of
# directly modifying this file.
#
# See the man page for details on how to write a sudoers file.
#
Defaults	env_reset
Defaults	exempt_group=admin
Defaults	secure_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# Host alias specification

# User alias specification

# Cmnd alias specification

# User privilege specification
root	ALL=(ALL:ALL) ALL

# Members of the admin group may gain root privileges
%admin  ALL=NOPASSWD:ALL

# Allow members of group sudo to execute any command
%sudo	ALL=(ALL:ALL) ALL


EOF

chmod 440 /etc/sudoers

###############################################################################
# apt-get package update
###############################################################################
apt-get -y update
apt-get -y dist-upgrade
apt-get -y install linux-headers-$(uname -r) build-essential
apt-get -y install postgresql libpq-dev
apt-get -y install python-dev python-virtualenv
apt-get -y install vim git-core ufw unzip
apt-get -y clean

# remove setuptools
#command dpkg -s python-setuptools >/dev/null 2>&1
#if [ $? -eq 0 ]; then
#    echo ":: removing setuptools"
#    apt-get -y remove python-setuptools
#fi

###############################################################################
# install orb (virtualenv utility)
###############################################################################
if [ -e orb ]; then
    echo ":: installing orb utility to /usr/local/bin/orb"
    if [ -e /usr/local/bin/orb ]; then
        cp /usr/local/bin/orb /usr/local/bin/_orb
    fi
    cp orb /usr/local/bin
fi

###############################################################################
# create postgres superuser 'admin' for peer authentication
###############################################################################
echo ":: creating postgres superuser"
#password=$(< /dev/urandom tr -dc A-Za-z0-9 | head -c30)
exists=$(su postgres -c "psql -tqc \"SELECT count(1) FROM pg_catalog.pg_user WHERE usename = 'admin'\"")
if [ $exists = 0 ]; then
    su postgres -c "createuser -s admin"
fi
exists=$(su postgres -c "psql -lqt | cut -d \| -f 1 | grep -w admin | wc -l")
if [ $exists = 0 ]; then
    su postgres -c "createdb -O admin admin"
fi

# lock postgres account (use the just created superuser instead)
passwd -l postgres

###############################################################################
# update postgres config
###############################################################################
echo ":: updating postgres config"

# use our own pg_hba.conf (peer authentication for admin user, md5 for local connections)
cp pg_hba.conf /etc/postgresql/$pg_version/main/pg_hba.conf
chown postgres:postgres /etc/postgresql/$pg_version/main/pg_hba.conf
chmod 640 /etc/postgresql/$pg_version/main/pg_hba.conf

# listen to requests from localhost only
sed -i -e "s/#listen_addresses.*/listen_addresses = 'localhost'/" /etc/postgresql/$pg_version/main/postgresql.conf

###############################################################################
# ssh key setup
###############################################################################
echo ":: unpacking ssh keys"
unzip remote-keys.zip
cp remote-keys/* /home/admin/.ssh/
rm -rf remote-keys
chown -R admin:admin /home/admin/.ssh

sshport=$(python -c "from random import randint; print randint(10000,30000)")
sed -i.orig -e "s/^Port .*/Port $sshport/g" /etc/ssh/sshd_config

###############################################################################
# enable ufw
###############################################################################
ufw default deny incoming
ufw allow http
ufw allow $sshport
ufw enable

echo "CHANGED SSH PORT: $sshport (restart to take effect)"

