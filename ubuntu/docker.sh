
###############################################################################
# docker ppa
###############################################################################
apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys 58118E89F3A912897C070ADBF76221572C52609D
echo "deb https://apt.dockerproject.org/repo ubuntu-$os_codename main" > /etc/apt/sources.list.d/docker.list

apt-get update
apt-get -y install docker-engine

service docker stop

# subnet for container interfaces
bridge_ip="172.17.0.1/24"
docker_subnet="172.17.1.0/24"

echo 'DOCKER_OPTS="--bip=$bridge_ip --fixed-cidr=$docker_subnet"' >> /etc/default/docker

# Determine the docker bridge IP address (assumed to be docker0)
#bridge_ip=$(ifconfig docker0 | grep "inet addr:" | awk '{print $2}' | sed "s/.*://")

pg_version="$(psql --version | awk -F ' ' 'NR==1{ print $3 }' | awk -F '.' '{ print $1"."$2 }')"

# update postgresql.conf to listen on the bridge interface and localhost only
sed -i "s/^[#]\?listen_addresses .*/listen_addresses = '$bridge_ip, localhost'/g" /etc/postgresql/$pg_version/main/postgresql.conf

# update pg_hba.conf to allow connections from the subnet
echo "host    all             all             $docker_subnet           md5" >> /etc/postgresql/$pg_version/main/pg_hba.conf

# update ufw firewall rules to allow container->host connections
ufw allow in from ${docker_subnet} to ${bridge_ip} port $postgres_port
ufw allow in from ${docker_subnet} to ${bridge_ip} port $devpi_port
ufw allow in from ${docker_subnet} to ${bridge_ip} port $memcached_port

