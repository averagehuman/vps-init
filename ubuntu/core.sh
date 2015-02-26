
###############################################################################
# create system users
# create docker group
###############################################################################
groupadd -r -f admin
groupadd -r -f -g $WORKER_DEFAULT_UID $WORKER_DEFAULT
groupadd -r -f devpi
groupadd -r -f docker
if [ ! $(grep '^admin:' /etc/passwd) ]; then
    useradd -r -m -s /bin/bash -g admin -G staff,$WORKER_DEFAULT,devpi,docker admin
fi
if [ ! $(grep '^$WORKER_DEFAULT:' /etc/passwd) ]; then
    useradd -r -M -s /usr/sbin/nologin -d /nonexistent -u $WORKER_DEFAULT_UID -g $WORKER_DEFAULT $WORKER_DEFAULT
fi
if [ ! $(grep '^devpi:' /etc/passwd) ]; then
    useradd -r -M -s /usr/sbin/nologin -d /nonexistent -g devpi devpi
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

passwd -l $WORKER_DEFAULT
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
# create shared directory for communication between processes
###############################################################################

mkdir -p /var/run/$WORKER_DEFAULT-shared

###############################################################################
# create static folders
###############################################################################

for d in assets media; do
    mkdir -p /srv/www/$d
done

chown admin:admin /srv/www/assets
chown $WORKER_DEFAULT:admin /srv/www/media
chmod 775 /srv/www/media


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
cp etc/10periodic /etc/apt/apt.conf.d/
cp etc/50unattended-upgrades /etc/apt/apt.conf.d/
chown root:root /etc/apt/apt.conf.d/50unattended-upgrades
chmod 644 /etc/apt/apt.conf.d/50unattended-upgrades
chown root:root /etc/apt/apt.conf.d/10periodic
chmod 644 /etc/apt/apt.conf.d/10periodic

apt-get -y update
apt-get -y dist-upgrade
apt-get -y install build-essential apt-transport-https
apt-get -y install unattended-upgrades python-software-properties
apt-get -y install postgresql libpq-dev
apt-get -y install python-dev
apt-get -y install postgresql-client libpq-dev
apt-get -y install libtiff5-dev libjpeg8-dev zlib1g-dev
apt-get -y install libfreetype6 libfreetype6-dev libreadline6-dev
apt-get -y install liblcms2-dev libwebp-dev tcl8.6-dev tk8.6-dev python-tk

apt-get -y install vim git-core unzip
apt-get -y install memcached supervisor ufw pound


###############################################################################
# get more recent setuptools, pip and virtualenv than system defaults
###############################################################################
# use default easy_install to install latest pip
apt-get -y install python-setuptools
easy_install pip
# remove default setuptools
apt-get -y remove python-setuptools
# get latest setuptools
pip install -U setuptools
# get latest virtualenv
pip install -U virtualenv
# install orb
pip install -U orb


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


###############################################################################
# configure memcached
###############################################################################

sed -i -e 's/^p .*/p $memcached_port/' /etc/memcached.conf
mv /etc/memcached.conf /etc/memcached_default.conf
cp etc/local_memcached.conf /etc


