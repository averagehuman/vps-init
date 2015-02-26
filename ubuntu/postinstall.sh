#!/bin/bash

###############################################################################
#
# Tidy up after running `server-init`
#
###############################################################################


set -e


sed -i -e "s/^[#]\?PasswordAuthentication .*/PasswordAuthentication no/g" /etc/ssh/sshd_config
sed -i -e "s/^[#]\?PermitRootLogin .*/PermitRootLogin no/g" /etc/ssh/sshd_config

