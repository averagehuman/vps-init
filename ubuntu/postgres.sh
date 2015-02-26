
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

# lock postgres system account (use the just created superuser instead)
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

# update postgres port
sed -i -e "s/^port .*/port = $postgres_port/" /etc/postgresql/$pg_version/main/postgresql.conf
# listen to requests from localhost only
sed -i -e "s/^[#]\?listen_addresses.*/listen_addresses = 'localhost'/" /etc/postgresql/$pg_version/main/postgresql.conf

