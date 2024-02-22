# Installation on RHEL 9

## Pre-requisites

RHEL 9 pre-requisites :

- RHEL 9 is installed
- The Red Hat repositories **baseos** and **appstream** are reachable

Microshift pre-requisites :

- RHEL 9.2 or 9.3
- LVM volume group (VG) with unused space

## Install Pre-requisites

```sh
sudo subscription-manager register --username $RHN_LOGIN --auto-attach
sudo subscription-manager attach --pool=$RHN_POOL_ID
sudo dnf install -y osbuild-composer composer-cli cockpit-composer
sudo systemctl enable --now osbuild-composer.socket
sudo systemctl enable --now cockpit.socket
sudo systemctl restart osbuild-composer
sudo usermod -a -G weldr "$(id -un)"
```

Check that **os-composer** is working.

```
$ source /etc/bash_completion.d/composer-cli
$ composer-cli status show
API server status:
    Database version:   0
    Database supported: true
    Schema version:     0
    API version:        1
    Backend:            osbuild-composer
    Build:              NEVRA:osbuild-composer-88.3-1.el9_3.x86_64

$ composer-cli sources list
appstream
baseos
```

## Clone this repository

```sh
git clone https://github.com/nmasse-itix/red-hat-kiosk.git
cd red-hat-kiosk
export GIT_REPO_CLONE="$PWD"
```

## Nginx configuration

```sh
sudo dnf install -y nginx
sudo systemctl enable --now nginx.service
sudo firewall-cmd --permanent --add-port={80/tcp,443/tcp}
sudo firewall-cmd --reload
sudo mkdir -p /var/www
sudo restorecon -Rv /var/www
sudo sed -i.${EPOCHREALTIME:-bak} 's|/usr/share/nginx/html|/var/www|g' /etc/nginx/nginx.conf
sudo systemctl restart nginx.service
```

## Build the RPMS

Pre-requisites

```sh
sudo dnf install -y git rpm-build rpmdevtools
rm $HOME/rpmbuild
ln -sf "$GIT_REPO_CLONE/rpms" $HOME/rpmbuild
```

Build the Kiosk Configuration RPM

```sh
spectool -g -R $HOME/rpmbuild/SPECS/kiosk-config.spec
rpmbuild -ba $HOME/rpmbuild/SPECS/kiosk-config.spec
```

Rebuild the Google Chrome RPM

```sh
mkdir $HOME/rpmbuild/VENDOR
curl -s -Lo $HOME/rpmbuild/VENDOR/google-chrome-stable_current_x86_64.rpm https://dl.google.com/linux/direct/google-chrome-stable_current_x86_64.rpm
rpmrebuild -s $HOME/rpmbuild/SPECS/google-chrome-stable.spec -p $HOME/rpmbuild/VENDOR/google-chrome-stable_current_x86_64.rpm
RPM=$(rpm -q $HOME/rpmbuild/VENDOR/google-chrome-stable_current_x86_64.rpm)
mkdir -p $HOME/rpmbuild/BUILDROOT/$RPM/
rpm2cpio $HOME/rpmbuild/VENDOR/google-chrome-stable_current_x86_64.rpm | cpio -idmv -D $HOME/rpmbuild/BUILDROOT/$RPM/
(
  set -Eeuo pipefail
  cd $HOME/rpmbuild/BUILDROOT/$RPM/
  mv opt/google/ usr/bin/
  cd usr/bin/
  rm -f google-chrome-stable
  ln -s google/chrome/google-chrome google-chrome-stable
  ln -s google/chrome/google-chrome chrome
) || echo 'Repackaging failed!'
sed -i.${EPOCHREALTIME:-bak} 's|/opt/google|/usr/bin/google|g' $HOME/rpmbuild/SPECS/google-chrome-stable.spec
rpmbuild -bb $HOME/rpmbuild/SPECS/google-chrome-stable.spec
ls -l $HOME/rpmbuild/RPMS/x86_64/
```

## Repository Creation

Customize the desired location of the RPM repository:

```sh
REPO_LOCATION="/opt/custom-rpms/"
```

Create the custom RPM repository:

```sh
sudo dnf install -y createrepo
sudo mkdir -p "$REPO_LOCATION"
sudo cp $HOME/rpmbuild/RPMS/x86_64/* "$REPO_LOCATION"
sudo createrepo "$REPO_LOCATION"
sudo tee /etc/yum.repos.d/custom.repo <<EOF
[custom]  
name = Custom RPMS  
baseurl = file://$REPO_LOCATION
enabled = 1  
gpgcheck = 0
EOF
```

Verify all packages are present.

```sh
sudo dnf clean all
sudo dnf info kiosk-config google-chrome-stable
```

## Blueprint preparation

Customize the **kiosk** and **admin** user password if desired.
Set the **admin** user SSH public key (if it's not you).

```sh
ADMIN_PASSWORD="$(openssl rand -base64 9)"
echo "Admin password is '$ADMIN_PASSWORD'"
ADMIN_SSH_PUBLIC_KEY="$(ssh-add -L | head -n 1)"
echo "Admin SSH public key: $ADMIN_SSH_PUBLIC_KEY"
```

Prepare the os-builder blueprint.

```sh
sudo subscription-manager repos --enable rhocp-4.14-for-rhel-9-$(uname -m)-rpms --enable fast-datapath-for-rhel-9-$(uname -m)-rpms
sudo dnf info microshift
sudo dnf install -y mkpasswd podman
cd "$GIT_REPO_CLONE/imagebuilder"
ADMIN_PASSWORD_HASH="$(mkpasswd -m bcrypt "$ADMIN_PASSWORD")"
sed -i.${EPOCHREALTIME:-bak} "s|__ADMIN_PASSWORD__|$ADMIN_PASSWORD_HASH|" kiosk.toml
sed -i.${EPOCHREALTIME:-bak} "s|__ADMIN_SSH_PUBLIC_KEY__|$ADMIN_SSH_PUBLIC_KEY|" kiosk.toml
composer-cli sources add /dev/fd/0 <<EOF
check_gpg = false
check_ssl = false
id = "custom"
name = "custom packages for RHEL"
system = false
type = "yum-baseurl"
url = "file://$REPO_LOCATION"
EOF
composer-cli sources add /dev/fd/0 <<EOF
id = "rhocp-4.14"
name = "Red Hat OpenShift Container Platform 4.14 for RHEL 9"
type = "yum-baseurl"
url = "https://cdn.redhat.com/content/dist/layered/rhel9/$(uname -m)/rhocp/4.14/os"
check_gpg = true
check_ssl = true
system = false
rhsm = true
EOF
composer-cli sources add /dev/fd/0 <<EOF
id = "fast-datapath"
name = "Fast Datapath for RHEL 9"
type = "yum-baseurl"
url = "https://cdn.redhat.com/content/dist/layered/rhel9/$(uname -m)/fast-datapath/os"
check_gpg = true
check_ssl = true
system = false
rhsm = true
EOF
composer-cli sources add /dev/fd/0 <<EOF
id = "epel"
name = "Extra Packages for Enterprise Linux"
type = "yum-baseurl"
url = "http://mirror.in2p3.fr/pub/epel/9/Everything/x86_64/"
check_gpg = false
check_ssl = false
system = false
rhsm = false
EOF
composer-cli blueprints push kiosk.toml
```

## Ostree construction

Create the ostree image.

```sh
composer-cli blueprints depsolve kiosk
BUILDID=$(composer-cli compose start-ostree --ref "rhel/9/$(uname -m)/edge" kiosk edge-container | awk '{print $2}')
echo "Build $BUILDID is running..."
composer-cli compose status
```

Download the ostree server and run it.

```sh
CONTAINER_IMAGE_FILE="$(composer-cli compose image "${BUILDID}")"
IMAGEID="$(podman load < "${BUILDID}-container.tar" | grep -o -P '(?<=sha256[@:])[a-z0-9]*')"
echo "Using image with id = $IMAGEID"
podman rm -i minimal-microshift-server
podman run -d --name=minimal-microshift-server -p 8085:8080 ${IMAGEID}
```

## Build the ISO

```sh
composer-cli blueprints push /dev/fd/0 <<EOF
name = "microshift-installer"

description = ""
version = "0.0.0"
modules = []
groups = []
packages = []
EOF
BUILDID=$(composer-cli compose start-ostree --url http://localhost:8085/repo/ --ref "rhel/9/$(uname -m)/edge" microshift-installer edge-installer | awk '{print $2}')
composer-cli compose status
composer-cli compose image "${BUILDID}"
```

## Prepare the Kickstart script

[Generate a pull secret](https://console.redhat.com/openshift/install/pull-secret) and set the `MICROSHIFT_PULL_SECRET` variable.

```sh
MICROSHIFT_PULL_SECRET='' # Generate one on https://console.redhat.com/openshift/install/pull-secret
```

Prepare the Kickstart script.

```sh
cd "$GIT_REPO_CLONE/imagebuilder"
sed -i.${EPOCHREALTIME:-bak} "s|__MICROSHIFT_PULL_SECRET__|$MICROSHIFT_PULL_SECRET|" kiosk.ks
```

## Inject the Kickstart in the ISO

```sh
sudo dnf install -y lorax pykickstart
ksvalidator kiosk.ks || echo "Kickstart has errors, please fix them!"
rm -f kiosk.iso && mkksiso -r "inst.ks inst.stage2" --ks kiosk.ks "${BUILDID}-installer.iso" kiosk.iso
```
