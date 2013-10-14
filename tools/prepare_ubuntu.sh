#!/bin/sh

set -e

pg_version="9.1"
nginx_version="1.4.3"
home=$(pwd)

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
cp ssh_config /home/admin/.ssh
cp authorized_keys /home/admin/.ssh
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

mkdir -p /srv
for d in static media; do
    mkdir -p /var/www/$d
    chown www:www /var/www/$d
    if [ ! -e /srv/$d ]; then
        ln -s /var/www/$d /srv/$d
    fi
done



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
apt-get -y install postgresql libpq-dev
apt-get -y install python-dev
apt-get -y install vim git-core ufw unzip
apt-get -y install memcached
apt-get -y clean


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
# install devpi-server
###############################################################################
service devpi-server status > /dev/null 2>&1
if [ $? -eq  1 ]; then
    pyversion=$(python -c "import sys;print('%s.%s' % sys.version_info[:2])")
    devpi_version="1.1"
    devpi_port=3131
    devpi_datadir="/var/devpi"
    venv_root="/srv/python$pyversion"
    eggs_root="$venv_root/.eggs"
    server_root="$venv_root/var/devpi/$devpi_version"

    #create a virtualenv at $venv_root
    if [ ! -e "$venv_root" ]; then
        virtualenv "$venv_root"
    fi

    mkdir -p $eggs_root

    rm -rf $server_root
    mkdir -p $venv_root/var/devpi
    rm -rf devpi-installer-master
    wget -O devpi-installer.zip https://github.com/averagehuman/devpi-installer/archive/master.zip
    unzip devpi-installer.zip
    mv devpi-installer-master $server_root

    cat > $server_root/base.cfg <<EOF

[buildout]
eggs-directory = $eggs_root

[cfg]
version = $devpi_version
host=localhost
port=$devpi_port
outside_url=
bottleserver=auto
debug=0
refresh=60
bypass_cdn=0
secretfile=.secret
serverdir=$devpi_datadir
aliasdir=/srv/devpi-server
user=devpi
group=devpi

EOF

    cd $server_root && make deploy

    cp $server_root/etc/devpi.upstart /etc/init/devpi-server.conf

    if [ ! -e /srv/devpi-server ]; then
        ln -s $server_root /srv/devpi-server
    fi

    chown -R admin:admin $venv_root
    chown -R devpi:devpi $venv_root/var/devpi
    chown -R devpi:devpi $devpi_datadir

    ###############################################################################
    # buildout/pip support
    ###############################################################################
    cd $home
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
fi

###############################################################################
# create postgres superuser 'admin' for peer authentication
###############################################################################
cd $home
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
cd $home
echo ":: updating postgres config"

# use our own pg_hba.conf (peer authentication for admin user, md5 for local connections)
cp pg_hba.conf /etc/postgresql/$pg_version/main/pg_hba.conf
chown postgres:postgres /etc/postgresql/$pg_version/main/pg_hba.conf
chmod 640 /etc/postgresql/$pg_version/main/pg_hba.conf

# listen to requests from localhost only
sed -i -e "s/#listen_addresses.*/listen_addresses = 'localhost'/" /etc/postgresql/$pg_version/main/postgresql.conf

###############################################################################
# disable memcached
###############################################################################
#sed -i -e "s/^ENABLE_MEMCACHED\b.*/ENABLE_MEMCACHED=no/g" /etc/default/memcached

###############################################################################
# install nginx
###############################################################################
sudo apt-get -y install libpcre3-dev zlib1g-dev libssl-dev

tmpdir="/tmp/nginx-install-$(date +%y%m%d-%H%M%S)"
prefix="/srv/nginx"

mkdir -p  $tmpdir
cd $tmpdir
wget http://nginx.org/download/nginx-${nginx_version}.tar.gz
tar -xvf nginx-${nginx_version}.tar.gz
cd nginx-${nginx_version}
./configure \
    --prefix=$prefix \
    --pid-path=$prefix/run/nginx.pid \
    --lock-path=$prefix/run/nginx.lock \
    --http-client-body-temp-path=$prefix/run/client_body_temp \
    --http-proxy-temp-path=$prefix/run/proxy_temp \
    --http-fastcgi-temp-path=$prefix/run/fastcgi_temp \
    --http-uwsgi-temp-path=$prefix/run/uwsgi_temp \
    --user=www \
    --group=www \
    --with-http_ssl_module \
    --without-http_scgi_module \
    --without-http_ssi_module

make && make install

cat > /etc/init/nginx.conf <<EOF

description "nginx http daemon"
author "Philipp Klose"

start on (filesystem and net-device-up IFACE=lo)
stop on runlevel [!2345]

env DAEMON=$prefix/sbin/nginx
env PID=$prefix/run/nginx.pid

expect fork
respawn
respawn limit 10 5
#oom never

pre-start script
    $DAEMON -t
    if [ $? -ne 0 ]
    then exit $?
    fi
end script

exec $DAEMON

EOF

cd $home
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

