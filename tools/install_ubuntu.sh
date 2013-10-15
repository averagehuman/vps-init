#!/bin/sh

set -e

pg_version="9.1"
nginx_version="1.4.3"
home=$(pwd)


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
pyversion=$(python -c "import sys;print('%s.%s' % sys.version_info[:2])")
devpi_version="1.1"
devpi_port=3131
devpi_datadir="/var/devpi"
venv_root="/srv/python$pyversion"
eggs_root="$venv_root/.eggs"
server_root="$venv_root/var/devpi/$devpi_version"

set +e
service devpi-server status > /dev/null 2>&1
if [ $? -eq  1 ]; then
    echo ":: installing devpi-server"
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
fi

set -e

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
    \$DAEMON -t
    if [ \$? -ne 0 ]
    then exit \$?
    fi
end script

exec \$DAEMON

EOF


