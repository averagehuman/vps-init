#!/bin/bash

set -e


###############################################################################
# create admin, www and devpi users
###############################################################################
groupadd -r -f admin
groupadd -r -f www
groupadd -r -f devpi
groupadd -r -f docker
if [ ! $(grep '^admin:' /etc/passwd) ]; then
    useradd -r -m -s /bin/bash -g admin -G www,devpi,docker admin
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
passwd -l docker

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
cp etc/10periodic /etc/apt/apt.conf.d/
cp etc/50unattended-upgrades /etc/apt/apt.conf.d/
chown root:root /etc/apt/apt.conf.d/50unattended-upgrades
chmod 644 /etc/apt/apt.conf.d/50unattended-upgrades
chown root:root /etc/apt/apt.conf.d/10periodic
chmod 644 /etc/apt/apt.conf.d/10periodic

###############################################################################
# oracle java ppa
###############################################################################
add-apt-repository -y ppa:webupd8team/java

###############################################################################
# docker ppa
###############################################################################
apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 36A1D7869245C8950F966E92D8576A8BA88D21E9
echo deb http://get.docker.io/ubuntu docker main > /etc/apt/sources.list.d/docker.list

###############################################################################
# varnish ppa
###############################################################################
#if [ -z "$(grep 'varnish-3.0' /etc/apt/sources.list)" ]; then
#    curl http://repo.varnish-cache.org/debian/GPG-key.txt | apt-key add -
#    echo "deb http://repo.varnish-cache.org/ubuntu/ precise varnish-3.0" | tee -a /etc/apt/sources.list
#fi

apt-get -y update
apt-get -y dist-upgrade
apt-get -y install build-essential apt-transport-https
apt-get -y install unattended-upgrades python-software-properties
apt-get -y install postgresql libpq-dev
apt-get -y install python-dev
apt-get -y install vim git-core unzip
apt-get -y install memcached supervisor ufw

apt-get -y install lxc-docker
apt-get -y install oracle-java7-installer

apt-get -y clean
apt-get -y autoremove

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
# install devpi-server
###############################################################################
pyversion=$(python -c "import sys;print('%s.%s' % sys.version_info[:2])")
devpi_port=3131
install_root="/opt"
install_parent="/opt/python$pyversion"
eggs_root="$install_root/.eggs"
venv_root="$install_parent/devpi.env"
data_root="/var/opt/devpi"

mkdir -p $eggs_root
mkdir -p $install_parent
mkdir -p $data_root


echo ":: installing devpi-server"
#create a virtualenv at $venv_root
if [ ! -e "$venv_root" ]; then
    orb init "$venv_root"
fi

pushd $venv_root
orb install -U devpi-server
popd

chown -R admin:admin $venv_root
chown -R devpi:devpi $data_root

cat > /etc/supervisor/conf.d/devpi-server.conf <<EOF

[program:devpi-server]
command = ${venv_root}/bin/devpi-server --host=localhost --port=${devpi_port} --serverdir=${data_root} --refresh=60
priority = 999
startsecs = 5
redirect_stderr = True
autostart = True
autorestart = True
user = devpi
process_name = devpi-server

EOF


###############################################################################
# buildout/pip support
###############################################################################
index_url="http://localhost:$devpi_port/root/pypi/+simple/"

mkdir -p /home/admin/.buildout
mkdir -p /home/admin/.pip

cat > /home/admin/.buildout/default.cfg <<EOF

[buildout]
eggs-directory = $eggs_root
index = $index_url

EOF

cat > /home/admin/.pip/pip.conf <<EOF

[global]
index-url = $index_url

EOF

chown -R admin:admin $eggs_root
chown -R admin:admin /home/admin/.buildout
chown -R admin:admin /home/admin/.pip

###############################################################################
# create postgres superuser 'admin' for peer authentication
###############################################################################
echo ":: creating postgres superuser"
#password=$(< /dev/urandom tr -dc A-Za-z0-9 | head -c30)
exists=$(su - postgres -c "psql -tqc \"SELECT count(1) FROM pg_catalog.pg_user WHERE usename = 'admin'\"")
if [ $exists = 0 ]; then
    su - postgres -c "createuser -s admin"
fi
exists=$(su - postgres -c "psql -lqt | cut -d \| -f 1 | grep -w admin | wc -l")
if [ $exists = 0 ]; then
    su - postgres -c "createdb -O admin admin"
fi

# lock postgres account (use the just created superuser instead)
passwd -l postgres

###############################################################################
# update postgres config
###############################################################################
echo ":: updating postgres config"

pg_version="$(psql --version | awk -F ' ' 'NR==1{ print $3 }' | awk -F '.' '{ print $1"."$2 }')"

# use our own pg_hba.conf (peer authentication for admin user, md5 for local connections)
cp etc/pg_hba.conf /etc/postgresql/$pg_version/main/pg_hba.conf
chown postgres:postgres /etc/postgresql/$pg_version/main/pg_hba.conf
chmod 640 /etc/postgresql/$pg_version/main/pg_hba.conf

# listen to requests from localhost only
sed -i -e "s/#listen_addresses.*/listen_addresses = 'localhost'/" /etc/postgresql/$pg_version/main/postgresql.conf

###############################################################################
# disable memcached
###############################################################################
#sed -i -e "s/^ENABLE_MEMCACHED\b.*/ENABLE_MEMCACHED=no/g" /etc/default/memcached

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


sshport="$(grep -i -x '^Port [0-9]*' /etc/ssh/sshd_config | awk '{ print $2 }')"

cat << EOF
###############################################################################
######            FINISHED INSTALL - SYSTEM RESTART REQUIRED            #######
###############################################################################

SSH PORT = ${sshport}

###############################################################################
###############################################################################

EOF



