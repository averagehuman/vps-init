#!/bin/sh

set -e


###############################################################################
# create admin, www and devpi users
###############################################################################
groupadd -r -f admin
groupadd -r -f www
groupadd -r -f devpi
if [ ! $(grep '^admin:' /etc/passwd) ]; then
    useradd -r -m -s /bin/bash -g admin -G www,devpi admin
fi
if [ ! $(grep '^www:' /etc/passwd) ]; then
    useradd -r -M -s /bin/false -d /nonexistent -g www www
fi
if [ ! $(grep '^devpi:' /etc/passwd) ]; then
    useradd -r -M -s /bin/false -d /nonexistent -g devpi devpi
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

passwd -l www
passwd -l devpi

###############################################################################
# ssh key setup
###############################################################################
cp etc/ssh_config /home/admin/.ssh
cp etc/authorized_keys /home/admin/.ssh
if [ -e server-admin-keys.zip ]; then
    echo ":: unpacking ssh keys"
    unzip server-admin-keys.zip
    cp server-admin-keys/* /home/admin/.ssh/
    rm -rf server-admin-keys
fi
chown -R admin:admin /home/admin/.ssh

###############################################################################
# create static folders
###############################################################################

for d in assets media; do
    mkdir -p /var/www/$d
done

chown admin:admin /var/www/assets
chown www:admin /var/www/media
chmod 775 /var/www/media



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
# add varnish ppa
###############################################################################
#if [ -z "$(grep 'varnish-3.0' /etc/apt/sources.list)" ]; then
#    curl http://repo.varnish-cache.org/debian/GPG-key.txt | apt-key add -
#    echo "deb http://repo.varnish-cache.org/ubuntu/ precise varnish-3.0" | tee -a /etc/apt/sources.list
#fi

###############################################################################
# apt-get package update
###############################################################################
apt-get -y update
apt-get -y dist-upgrade
apt-get -y install linux-headers-$(uname -r) build-essential
apt-get -y install unattended-upgrades python-software-properties
apt-get -y install postgresql libpq-dev
apt-get -y install python-dev
apt-get -y install vim git-core ufw unzip
apt-get -y install memcached
apt-get -y clean

###############################################################################
# oracle java
###############################################################################
add-apt-repository -y ppa:webupd8team/java
apt-get -y update
apt-get -y install oracle-java7-installer

###############################################################################
# configure unattended system upgrades
###############################################################################
cp etc/50unattended-upgrades /etc/apt/apt.conf.d/
chown root:root /etc/apt/apt.conf.d/50unattended-upgrades
chmod 644 /etc/apt/apt.conf.d/50unattended-upgrades

###############################################################################
# get more recent setuptools, pip and virtualenv than system defaults
###############################################################################
# use default easy_install to install latest pip
apt-get -y install python-setuptools
easy_install pip
# get latest setuptools
pip install -U setuptools
# remove default setuptools
apt-get -y remove python-setuptools
# get latest virtualenv
pip install virtualenv

###############################################################################
# enable ufw
###############################################################################
sshport=$(python -c "from random import randint; print randint(10000,30000)")
sed -i.orig -e "s/^Port .*/Port $sshport/g" /etc/ssh/sshd_config

ufw default deny incoming
ufw allow http
ufw allow $sshport
ufw enable

echo "CHANGED SSH PORT: $sshport (restart to take effect)"

