
###############################################################################
# docker ppa
###############################################################################
apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 36A1D7869245C8950F966E92D8576A8BA88D21E9
echo deb http://get.docker.io/ubuntu docker main > /etc/apt/sources.list.d/docker.list

apt-get update
apt-get -y install lxc-docker

# Determine the docker bridge IP address (assumed to be docker0)
bridge_ip=$(ifconfig docker0 | grep "inet addr:" | awk '{print $2}' | sed "s/.*://")
 
# subnet for container interfaces
docker_subnet="172.17.1.0/24"
 
pg_version="$(psql --version | awk -F ' ' 'NR==1{ print $3 }' | awk -F '.' '{ print $1"."$2 }')"

# update postgresql.conf to listen only on the bridge interface
sed -i "s/^[#]\?listen_addresses .*/listen_addresses = '$bridge_ip'/g" /etc/postgresql/$pg_version/main/postgresql.conf
 
# update pg_hba.conf to allow connections from the subnet
echo "host    all             all             $docker_subnet           md5" >> /etc/postgresql/$pg_version/main/pg_hba.conf
 
# update ufw firewall rules to allow container->host connections
ufw allow in from ${docker_subnet} to ${bridge_ip} port $postgres_port
ufw allow in from ${docker_subnet} to ${bridge_ip} port $devpi_port
ufw allow in from ${docker_subnet} to ${bridge_ip} port $memcached_port

