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
# docker needs 3.8 kernel (and restart)
###############################################################################
apt-get -y update
if [ "$(lsb_release -r | awk '{ print $2 }')" = "12.04" ]; then
    apt-get install linux-image-generic-lts-raring linux-headers-generic-lts-raring
fi

###############################################################################
# configure unattended system upgrades
###############################################################################
cp etc/50unattended-upgrades /etc/apt/apt.conf.d/
chown root:root /etc/apt/apt.conf.d/50unattended-upgrades
chmod 644 /etc/apt/apt.conf.d/50unattended-upgrades

###############################################################################
# enable ufw
###############################################################################
sshport=$(python -c "from random import randint; print randint(10000,30000)")
sed -i.orig -e "s/^Port .*/Port $sshport/g" /etc/ssh/sshd_config

ufw default deny incoming
ufw allow http
ufw allow $sshport
sed -i.orig -e 's/DEFAULT_FORWARD_POLICY=.*/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw
ufw enable

echo "CHANGED SSH PORT: $sshport (restart to take effect)"

