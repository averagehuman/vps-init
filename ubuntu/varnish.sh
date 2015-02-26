
curl https://repo.varnish-cache.org/GPG-key.txt | apt-key add -
if [ "$(lsb_release -r | awk '{ print $2 }')" = "12.04" ]; then
    os_release="precise";
else
    os_release="trusty";
fi
echo "deb https://repo.varnish-cache.org/ubuntu/ $os_release varnish-4.0" > /etc/apt/sources.list.d/varnish-cache.list
apt-get update
apt-get -y install varnish
