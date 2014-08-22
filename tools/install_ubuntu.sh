#!/bin/bash

###############################################################################
#
# Provisioning for a typical web server running on Ubuntu 12.04 - 14.04
#
###############################################################################


set -e

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
apt-get -y install vim git-core ufw unzip
apt-get -y install memcached supervisor

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


