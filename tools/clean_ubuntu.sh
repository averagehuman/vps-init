#!/bin/bash

###############################################################################
#
# Tidy up after running both `server-init` and `server-install`
#
###############################################################################


set -e


sed -i.orig -e "s/^PasswordAuthentication .*/PasswordAuthentication no/g" /etc/ssh/sshd_config
sed -i.orig -e "s/^PermitRootLogin .*/PermitRootLogin no/g" /etc/ssh/sshd_config

