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
sudo sed -i.bak 's|/usr/share/nginx/html|/var/www|g' /etc/nginx/nginx.conf
sudo systemctl restart nginx.service
```

## Rebuild of Google Chrome

```sh
sudo dnf install -y git rpm-build
sudo dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm
sudo dnf install -y rpmrebuild
cd "$GIT_REPO_CLONE/chrome_repackage"
curl -s -Lo google-chrome-stable_current_x86_64.rpm https://dl.google.com/linux/direct/google-chrome-stable_current_x86_64.rpm
rpmrebuild -s google-chrome-stable.spec -p google-chrome-stable_current_x86_64.rpm
rpm2cpio google-chrome-stable_current_x86_64.rpm | cpio -idmv
mv opt/google/ usr/bin/
cd usr/bin/
rm -f google-chrome-stable
ln -s google/chrome/google-chrome google-chrome-stable
ln -s google/chrome/google-chrome chrome
cd ../..
RPM=$(rpm -q google-chrome-stable_current_x86_64.rpm)
mkdir -p $HOME/rpmbuild/BUILDROOT/$RPM/
for i in etc usr; do cp -r $i $HOME/rpmbuild/BUILDROOT/$RPM/; done
sed -i.bak 's|/opt/google|/usr/bin/google|g' google-chrome-stable.spec
rpmbuild -bb google-chrome-stable.spec
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
sudo dnf info google-chrome-stable
```

## Blueprint preparation

Customize the **kiosk** and **admin** user password if desired.

```sh
KIOSK_PASSWORD="$(openssl rand -base64 9)"
echo "Kiosk password is '$KIOSK_PASSWORD'"
ADMIN_PASSWORD="$(openssl rand -base64 9)"
echo "Admin password is '$ADMIN_PASSWORD'"
```

Prepare the os-builder blueprint.

```sh
sudo subscription-manager repos --enable rhocp-4.14-for-rhel-9-$(uname -m)-rpms --enable fast-datapath-for-rhel-9-$(uname -m)-rpms
sudo dnf info microshift
sudo dnf install -y mkpasswd podman
cd "$GIT_REPO_CLONE/imagebuilder"
KIOSK_PASSWORD_HASH="$(mkpasswd -m bcrypt "$KIOSK_PASSWORD")"
ADMIN_PASSWORD_HASH="$(mkpasswd -m bcrypt "$ADMIN_PASSWORD")"
sed -i.orig1 "s|__KIOSK_PASSWORD__|$KIOSK_PASSWORD_HASH|" kiosk.toml
sed -i.orig2 "s|__ADMIN_PASSWORD__|$ADMIN_PASSWORD_HASH|" kiosk.toml
ADMIN_SSH_PUBLIC_KEY="$(ssh-add -L | head -n 1)"
echo "Admin SSH public key: $ADMIN_SSH_PUBLIC_KEY"
sed -i.orig3 "s|__ADMIN_SSH_PUBLIC_KEY__|$ADMIN_SSH_PUBLIC_KEY|" kiosk.toml
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

Customize the **root** user password if desired.

```sh
ROOT_PASSWORD="$(openssl rand -base64 9)"
echo "Root password is '$ROOT_PASSWORD'"
```

[Generate a registry token](https://access.redhat.com/terms-based-registry/) and set the `MICROSHIFT_PULL_SECRET` variable.

```sh
MICROSHIFT_PULL_SECRET="1.2.3" # Generated by https://access.redhat.com/terms-based-registry/
```

Prepare the Kickstart script.

```sh
cd "$GIT_REPO_CLONE/imagebuilder"
__ROOT_PASSWORD_HASH__="$(mkpasswd -m bcrypt "$ROOT_PASSWORD")"
sed -i.orig1 "s|__MICROSHIFT_PULL_SECRET__|$MICROSHIFT_PULL_SECRET|" kiosk.ks
sed -i.orig2 "s|__ROOT_PASSWORD_HASH__|$__ROOT_PASSWORD_HASH__|" kiosk.ks
```

## Inject the Kickstart in the ISO

```sh
sudo dnf install -y lorax
mkksiso kiosk.ks "${BUILDID}-installer.iso" kiosk.iso
```
