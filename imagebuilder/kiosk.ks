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
## Alternative partitioning on only one disk
##
#zerombr
#clearpart --all --initlabel
#reqpart --add-boot
#part pv.01 --size=10G --ondisk=sda
#volgroup system pv.01
#logvol /  --fstype="xfs" --size=1 --grow --name=root --vgname=system
#part pv.02 --size=1 --grow --ondisk=sda
#volgroup data pv.02

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
# Add the pull secret to CRI-O and set root user-only read/write permissions
cat > /etc/crio/openshift-pull-secret << 'EOF'
__MICROSHIFT_PULL_SECRET__
EOF
chmod 600 /etc/crio/openshift-pull-secret

# Configure the firewall with the mandatory rules for MicroShift
firewall-offline-cmd --zone=trusted --add-source=10.42.0.0/16
firewall-offline-cmd --zone=trusted --add-source=169.254.169.1

%end
