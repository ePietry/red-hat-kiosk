##
## Environment setup
##

# French I18n
lang fr_FR.UTF-8

# French keyboard layout
keyboard fr

# Timezone is UTC to avoid issue with DST
timezone UTC --utc

# Configure NTP
timesource --ntp-server=rhel.pool.ntp.org

# Which action to perform after install: poweroff or reboot
reboot

# Install mode: text (interactive installs) or cmdline (unattended installs)
text

##
## Storage configuration
##

# Clear the target disk
zerombr

# Remove existing partitions
clearpart --all --initlabel

# Automatically create partitions required by hardware platform
# and add a separate /boot partition
reqpart --add-boot

# Create a PV, VG add LV for the system
part pv.01 --size=1 --grow --ondisk=vda
volgroup system pv.01
logvol /  --fstype="xfs" --size=1 --grow --name=root --vgname=system

# Create a PV and VG for Microshift
part pv.02 --size=1 --grow --ondisk=vdb
volgroup data pv.02

##
## Network configuration
##

# Configure the first network device
network  --bootproto=dhcp --device=enp1s0 --noipv6 --activate

# Configure hostname
network  --hostname=kiosk.localdomain

##
## Ostree installation
##

# Use this line if creating an Edge Installer ISO that includes a local ostree commit
ostreesetup --nogpg --osname=rhel --remote=edge --url=file:///run/install/repo/ostree/repo --ref=rhel/9/x86_64/edge

# Use this to fetch from a remote URL
#ostreesetup --osname=rhel --url=http://192.168.0.116:30239/repo --ref=rhel/9/x86_64/edge --nogpg

##
## Post install scripts
##
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
