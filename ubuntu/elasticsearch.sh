
### Download and Install ElasticSearch
### Check http://www.elasticsearch.org/download/ for latest version of ElasticSearch and replace wget link below
wget https://download.elasticsearch.org/elasticsearch/elasticsearch/elasticsearch-1.4.4.deb
dpkg -i elasticsearch-1.4.4.deb

#enable on bootup
update-rc.d elasticsearch defaults 95 10
 
### Start ElasticSearch 
#/etc/init.d/elasticsearch start
#
### Make sure service is running
#curl http://localhost:9200
#
### Should return something like this:
#{
#  "status" : 200,
#  "name" : "Storm",
#  "version" : {
#    "number" : "1.3.1",
#    "build_hash" : "2de6dc5268c32fb49b205233c138d93aaf772015",
#    "build_timestamp" : "2014-07-28T14:45:15Z",
#    "build_snapshot" : false,
#    "lucene_version" : "4.9"
#  },
#  "tagline" : "You Know, for Search"
#}


#You will want to tune your memory as well http://stackoverflow.com/a/18152957/56069
