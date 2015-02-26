
###############################################################################
# install devpi-server
###############################################################################
install_root="/opt"
eggs_root="$install_root/.eggs"
venv_root="$install_root/devpi-server"
data_root="/var/opt/devpi"

mkdir -p $install_root
mkdir -p $eggs_root
mkdir -p $data_root


echo ":: installing devpi-server"
#create a virtualenv at $venv_root
if [ ! -e "$venv_root" ]; then
    orb init "$venv_root"
fi

pushd $venv_root
orb install -U devpi-server
popd

cat > /etc/supervisor/conf.d/devpi-server.conf <<EOF

[program:devpi-server]
command = ${venv_root}/bin/devpi-server --host=localhost --port=${devpi_port} --serverdir=${data_root} --refresh=600
priority = 999
startsecs = 5
redirect_stderr = True
autostart = True
autorestart = True
user = devpi
process_name = devpi-server

EOF


index_url="http://localhost:$devpi_port/root/pypi/+simple/"

# buildout config
mkdir -p /home/admin/.buildout

cat > /home/admin/.buildout/default.cfg <<EOF

[buildout]
eggs-directory = $eggs_root
index = $index_url

EOF

# pip config
mkdir -p /home/admin/.pip
cat > /home/admin/.pip/pip.conf <<EOF

[global]
index-url = $index_url

EOF

chown -R devpi:devpi $data_root
chown -R admin:admin $venv_root
chown -R admin:admin $eggs_root
chown -R admin:admin /home/admin/.buildout
chown -R admin:admin /home/admin/.pip

