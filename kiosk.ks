lang fr_FR.UTF-8
keyboard fr
timezone UTC --isUtc --ntpservers=rhel.pool.ntp.org
reboot
text

zerombr
clearpart --all --initlabel
autopart --type=plain --fstype=xfs --nohome
network --bootproto=dhcp
rootpw --iscrypted $6$3OrUXJfD.64WiZl2$4/oBFyFgIyPI6LdLCbE.h99YBrFa..pC3x3WlHNH8mUf4ssZmhlhy17CHc0n3kAvHvWecpqunVOd/4kOGB7Ms.
#Use this line if creating an Edge Installer ISO that includes a local ostree commit
#ostreesetup --osname=rhel --url=file:///ostree/repo --ref=rhel/9/x86_64/edge --nogpg
#Use this to fetch from a remote URL
ostreesetup --osname=rhel --url=http://[YOUR_SERVER_IP:PORT]/repo --ref=rhel/9/x86_64/edge --nogpg

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

#Configure the kiosk script to run firefox in kiosk mode and display our example URL
mkdir -p /home/kiosk/.local/bin/
cat > /home/kiosk/.local/bin/gnome-kiosk-script << 'EOF'
#!/bin/sh
while true; do
    firefox -kiosk https://voyage.kiosk.fr/
done
EOF

#Ensure the files are owned by our unprivileged user and the script is executable 
chown -R 1000:1000 /home/kiosk
chmod 755 /home/kiosk/.local/bin/gnome-kiosk-script

%end
