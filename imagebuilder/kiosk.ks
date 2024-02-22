lang fr_FR.UTF-8
keyboard fr
timezone UTC --utc
timesource --ntp-server=rhel.pool.ntp.org
reboot
text

zerombr
clearpart --all --initlabel
autopart --type=plain --fstype=xfs --nohome
network --bootproto=dhcp
rootpw --iscrypted __ROOT_PASSWORD_HASH__

# Use this line if creating an Edge Installer ISO that includes a local ostree commit
ostreesetup --nogpg --osname=rhel --remote=edge --url=file:///run/install/repo/ostree/repo --ref=rhel/9/x86_64/edge

# Use this to fetch from a remote URL
#ostreesetup --osname=rhel --url=http://192.168.0.116:30239/repo --ref=rhel/9/x86_64/edge --nogpg

%post --log=/var/log/anaconda/post-install.log --erroronfail
# Default to graphical boot target
systemctl set-default graphical.target

# Enable autologin for the user kiosk
sed -i '/^\[daemon\]/a AutomaticLoginEnable=True\nAutomaticLogin=kiosk\n' /etc/gdm/custom.conf

# Configure user kiosk to use the kiosk session
mkdir -p /var/lib/AccountsService/users
cat > /var/lib/AccountsService/users/kiosk << 'EOF'
[User]
Session=gnome-kiosk-script
SystemAccount=false
EOF

# Add url environment variable
cat >> /home/kiosk/.bashrc << 'EOF'
export KIOSK_URL=http://`ip -br a | grep -oP 'br-ex\s+UNKNOWN\s+\K[0-9.]+'`:30000
EOF

# Configure the kiosk script to run firefox in kiosk mode and display our example URL
mkdir -p /home/kiosk/.local/bin/
cat > /home/kiosk/.local/bin/gnome-kiosk-script << 'EOF'
#!/bin/sh
. ~/.bashrc
while true; do
    /usr/bin/google/chrome/chrome --password-store=basic --no-default-browser-check --no-first-run --ash-no-nudges --disable-search-engine-choice-screen -kiosk   ${KIOSK_URL}
done
EOF

# Ensure the files are owned by our unprivileged user and the script is executable 
chown -R 1001:1001 /home/kiosk
chmod 555 /home/kiosk/.local/bin/gnome-kiosk-script

# Add the pull secret to CRI-O and set root user-only read/write permissions
cat > /etc/crio/openshift-pull-secret << 'EOF'
__MICROSHIFT_PULL_SECRET__
EOF
chmod 600 /etc/crio/openshift-pull-secret

# Configure the firewall with the mandatory rules for MicroShift
firewall-offline-cmd --zone=trusted --add-source=10.42.0.0/16
firewall-offline-cmd --zone=trusted --add-source=169.254.169.1

%end
