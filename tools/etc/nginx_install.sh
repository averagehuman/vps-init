###############################################################################
# install nginx
###############################################################################
nginx_version="1.4.3"
sudo apt-get -y install libpcre3-dev zlib1g-dev libssl-dev

prefix="/srv/nginx"

if [ -e "$prefix/sbin/nginx" ]; then
    echo "nginx already installed at $prefix/sbin/nginx"
else
    tmpdir="/tmp/nginx-install-$(date +%y%m%d-%H%M%S)"
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

    chown -R www:www $prefix/logs

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

cat > /etc/logrotate.d/nginx <<EOF

/srv/nginx/logs/*.log {
	daily
	missingok
	rotate 52
	compress
	delaycompress
	notifempty
	create 0640 www www
	sharedscripts
	postrotate
		[ ! -f $prefix/nginx.pid ] || kill -USR1 `cat $prefix/nginx.pid`
	endscript
}

EOF

fi


