#!/bin/sh

set -e

pg_version="9.1"
home=$(pwd)


###############################################################################
# install orb (virtualenv utility)
###############################################################################
if [ -e etc/orb ]; then
    echo ":: installing orb utility to /usr/local/bin/orb"
    if [ -e /usr/local/bin/orb ]; then
        cp /usr/local/bin/orb /usr/local/bin/_orb
    fi
    cp etc/orb /usr/local/bin
fi

###############################################################################
# install devpi-server
###############################################################################
pyversion=$(python -c "import sys;print('%s.%s' % sys.version_info[:2])")
devpi_version="1.2"
devpi_port=3131
devpi_datadir="/var/devpi"
install_root="/opt"
venv_root="$install_root/python$pyversion"
eggs_root="$install_root/.eggs"
server_root="$venv_root/src/devpi/$devpi_version"

mkdir -p $install_root
mkdir -p $eggs_root

echo ":: installing devpi-server"
#create a virtualenv at $venv_root
if [ ! -e "$venv_root" ]; then
    virtualenv "$venv_root"
fi

mkdir -p $eggs_root

rm -rf $server_root
mkdir -p $venv_root/src/devpi
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
aliasdir=$install_root/devpi-server
user=devpi
group=devpi

EOF

cd $server_root && make install

if [ ! -e $install_root/devpi-server ]; then
    ln -s $server_root $install_root/devpi-server
fi

chown -R admin:admin $venv_root
chown -R devpi:devpi $venv_root/src/devpi
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
cp etc/pg_hba.conf /etc/postgresql/$pg_version/main/pg_hba.conf
chown postgres:postgres /etc/postgresql/$pg_version/main/pg_hba.conf
chmod 640 /etc/postgresql/$pg_version/main/pg_hba.conf

# listen to requests from localhost only
sed -i -e "s/#listen_addresses.*/listen_addresses = 'localhost'/" /etc/postgresql/$pg_version/main/postgresql.conf

###############################################################################
# disable memcached
###############################################################################
#sed -i -e "s/^ENABLE_MEMCACHED\b.*/ENABLE_MEMCACHED=no/g" /etc/default/memcached


