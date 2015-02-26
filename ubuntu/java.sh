
###############################################################################
# oracle java ppa
###############################################################################
add-apt-repository -y ppa:webupd8team/java
echo oracle-java8-installer shared/accepted-oracle-license-v1-1 select true | /usr/bin/debconf-set-selections

apt-get -y update
apt-get -y install oracle-java8-installer

