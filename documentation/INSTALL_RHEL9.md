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
sudo dnf install -y osbuild-composer composer-cli cockpit-composer git firewalld python3-toml
sudo systemctl enable --now osbuild-composer.socket
sudo systemctl enable --now firewalld
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
git clone https://github.com/ePietry/red-hat-kiosk.git
cd red-hat-kiosk
export GIT_REPO_CLONE="$PWD"
```

## Create the container image

Install podman and buildah.

```sh
sudo dnf install -y podman buildah
```

Define the target image properties.

```sh
REGISTRY="quay.io"
IMAGE_NAME="nmasse_itix/kiosk-app"
IMAGE_TAG="latest"
```

Build and push the image to the registry.

```sh
cd "$GIT_REPO_CLONE/application"
podman build -t localhost/kiosk-app:latest .
podman login "$REGISTRY"
podman tag localhost/kiosk-app:latest "$REGISTRY/$IMAGE_NAME:$IMAGE_TAG"
podman push "$REGISTRY/$IMAGE_NAME:$IMAGE_TAG"
```

## Nginx configuration

Install and configure nginx.

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

Find the IP address of the current server.

```sh
MYIP="$(ip -4 -br addr show scope global | awk 'NR == 1 { split($3, parts, "/"); print parts[1]; }')"
```

## Create the initial ostree repo

Define two helper functions.

```sh
function compose_status () {
  composer-cli compose info "$1" | awk 'NR == 1 { print $2 }'
}
function wait_for_compose () {
  status="$(compose_status "$1")"

  while [ "$status" == "RUNNING" ]; do
    echo "Waiting for build $1 to finish..."
    sleep 5
    status="$(compose_status "$1")"
  done

  echo "Build status of $1 is: $status."
  if [ "$status" == "FINISHED" ]; then
    return 0
  fi

  return 1
}
```

Bootstrap the initial ostree repository with ref = `rhel/9/x86_64/edge`.

```sh
composer-cli blueprints push /dev/fd/0 <<EOF
name = "minimal-rhel9"
description = "minimal blueprint for ostree commit"
version = "1.1.0"
modules = []
groups = []
distro = "rhel-93"
EOF
BUILDID=$(composer-cli compose start-ostree minimal-rhel9 edge-commit | awk '{print $2}')
echo "Build $BUILDID is running..."
wait_for_compose "$BUILDID"
composer-cli compose image "$BUILDID"
sudo rm -rf /var/www/repo
sudo tar -xf "$BUILDID-commit.tar" -C /var/www
ostree --repo=/var/www/repo refs
```

Create an empty commit with ref = `empty`.

> [!TIP]
> This is an optimization in order to trim 800 MB from the installer ISO image.

```sh
sudo mkdir -p /tmp/empty-tree
sudo ostree --repo=/var/www/repo commit -b "empty" --tree=dir=/tmp/empty-tree
ostree --repo=/var/www/repo refs
```

## Build the RPMS

Pre-requisites

```sh
sudo dnf install -y git rpm-build rpmdevtools
rm -f $HOME/rpmbuild
ln -sf "$GIT_REPO_CLONE/rpms" $HOME/rpmbuild
```

Build the `kiosk-config` RPM

```sh
spectool -g -R $HOME/rpmbuild/SPECS/kiosk-config.spec
rpmbuild -ba $HOME/rpmbuild/SPECS/kiosk-config.spec
```

Build the `microshift-manifests` RPM

```sh
spectool -g -R $HOME/rpmbuild/SPECS/microshift-manifests.spec
rpmbuild -ba $HOME/rpmbuild/SPECS/microshift-manifests.spec
```

Rebuild the Google Chrome RPM

```sh
sudo dnf install https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm
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
sudo dnf info kiosk-config google-chrome-stable microshift-manifests
```

## Blueprint preparation

Customize the **admin** user password if desired.
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

Create the ostree image and add it to the ostree repository with ref = `rhel/9/x86_64/edge-kiosk`.

```sh
composer-cli blueprints depsolve kiosk
BUILDID=$(composer-cli compose start-ostree kiosk edge-commit --url http://$MYIP/repo --ref "rhel/9/$(uname -m)/edge-kiosk" --parent "rhel/9/$(uname -m)/edge" | awk '{print $2}')
echo "Build $BUILDID is running..."
wait_for_compose "$BUILDID"
composer-cli compose image "${BUILDID}"
mkdir -p "/tmp/${BUILDID}-commit"
tar -xf "${BUILDID}-commit.tar" -C "/tmp/${BUILDID}-commit"
sudo ostree --repo=/var/www/repo pull-local "/tmp/${BUILDID}-commit/repo"
ostree --repo=/var/www/repo refs
ostree --repo=/var/www/repo log rhel/9/x86_64/edge-kiosk
```

## Generate the Installer ISO image

Generate the ISO image of the installer.

```sh
composer-cli blueprints push /dev/fd/0 <<EOF
name = "microshift-installer"

description = ""
version = "0.0.0"
modules = []
groups = []
packages = []
EOF
BUILDID=$(composer-cli compose start-ostree --url http://localhost/repo/ --ref empty microshift-installer edge-installer | awk '{print $2}')
echo "Build $BUILDID is running..."
wait_for_compose "$BUILDID"
composer-cli compose image "${BUILDID}"
```

> [!CAUTION]
> While it is possible to use the stock RHEL 9.3 Boot ISO image here, there are subtle differences between the stock ISO image and the one generated here.

## Prepare the Kickstart script

[Generate a pull secret](https://console.redhat.com/openshift/install/pull-secret) and set the `MICROSHIFT_PULL_SECRET` variable.

```sh
MICROSHIFT_PULL_SECRET='' # Generate one on https://console.redhat.com/openshift/install/pull-secret
```

Prepare the Kickstart script.

```sh
cd "$GIT_REPO_CLONE/imagebuilder"
sed -i.${EPOCHREALTIME:-bak} "s|__MICROSHIFT_PULL_SECRET__|$MICROSHIFT_PULL_SECRET|" kiosk.ks
sed -i.${EPOCHREALTIME:-bak} "s|__MYIP__|$MYIP|" kiosk.ks
```

## Inject the Kickstart in the ISO

```sh
sudo dnf install -y lorax pykickstart
ksvalidator kiosk.ks || echo "Kickstart has errors, please fix them!"
rm -f kiosk.iso && mkksiso -r "inst.ks" --ks kiosk.ks "${BUILDID}-installer.iso" kiosk.iso
ls -lh kiosk.iso
file kiosk.iso
```
