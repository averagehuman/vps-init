#!/bin/bash

set -e

os_codename="$(lsb_release -c | awk '{ print $2 }')"
os_release="$(lsb_release -r | awk '{ print $2 }')"

cat << EOF
###############################################################################
#####   BEGINNING SERVER PROVISIONING (Ubuntu $os_release $os_codename)   #####
###############################################################################

EOF

