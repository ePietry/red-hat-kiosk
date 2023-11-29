lang fr_FR.UTF-8
keyboard fr
timezone UTC --isUtc --ntpservers=rhel.pool.ntp.org
reboot
text

zerombr
clearpart --all --initlabel
autopart --type=plain --fstype=xfs --nohome
network --bootproto=dhcp
rootpw --iscrypted $6$vnnc7bdpgCJMBDB.$TRBsboYscXsKPv57IHnKuy1BzLhuejJgft17s07ZQRSsgFhPI9QLPX6Spt4AiND4TaolQAR8FzMV2Osf2dhj10 
#Use this line if creating an Edge Installer ISO that includes a local ostree commit
#ostreesetup --osname=rhel --url=file:///ostree/repo --ref=rhel/9/x86_64/edge --nogpg
#Use this to fetch from a remote URL
ostreesetup --osname=rhel --url=http://192.168.0.116:30239/repo --ref=rhel/9/x86_64/edge --nogpg

%post
#Default to graphical boot target
systemctl set-default graphical.target

#Enable autologin for the user kiosk

sed -i '/^\[daemon\]/a AutomaticLoginEnable=True\nAutomaticLogin=kiosk\n' /etc/gdm/custom.conf

#Configure user kiosk to use the kiosk session
mkdir -p /var/lib/AccountsService/users
cat > /var/lib/AccountsService/users/kiosk << 'EOF'
[User]
Session=gnome-kiosk-script
SystemAccount=false
EOF

#Add url environment variable
cat >> /home/kiosk/.bashrc << 'EOF'
export KIOSK_URL=http://`ip -br a | grep -oP 'br-ex\s+UNKNOWN\s+\K[0-9.]+'`:30000
EOF

#Configure the kiosk script to run firefox in kiosk mode and display our example URL
mkdir -p /home/kiosk/.local/bin/
cat > /home/kiosk/.local/bin/gnome-kiosk-script << 'EOF'
#!/bin/sh
. ~/.bashrc
while true; do
    /usr/bin/google/chrome/chrome --password-store=basic --no-default-browser-check --no-first-run --ash-no-nudges --disable-search-engine-choice-screen -kiosk   ${KIOSK_URL}
done
EOF

#Ensure the files are owned by our unprivileged user and the script is executable 
chown -R 1001:1001 /home/kiosk
chmod 555 /home/kiosk/.local/bin/gnome-kiosk-script

/etc/crio/openshift-pull-secret

cat > /etc/crio/openshift-pull-secret << 'EOF'
<YOUR_PULL_SECRET>
EOF



%end
