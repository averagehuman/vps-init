
apt-get -y clean
apt-get -y autoremove

cat << EOF
###############################################################################
###########         FINISHED INSTALL.  (ssh on port ${sshport})      ##########
###############################################################################

Rebooting in 5 seconds...

EOF

sleep 5
shutdown -r now

