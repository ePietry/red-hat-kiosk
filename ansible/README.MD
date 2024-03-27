# Installation on RHEL 9 Automatisation

Ansible Playbook allowing to create ostree images for edge using Ansible.

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

Create a `inventory.yaml` file inside the Ansible folder or define the inventory path inside the `ansible.cfg` file

Add blueprint file into the blueprint folder or use the `blueprint_example.toml`

Create the initial ostree repo using `blueprint_example.toml` use the following command: 
```
ansible-playbook playbooks/initial_ostree.yaml -e blueprint=blueprint_example.toml
```


## Build the RPMS

To build RPM for kiosk-config, microshift-manifests and Google Chrome, run the `build_RPMS.yaml` playbook
```
ansible-playbook playbooks/build_RPMS.yaml
```

## Repository Creation
to build a repository containing the RPMS we created, run the 'repo_creation.yaml' playbook and indicate the desiered repo directory suring the -e argument.

For instance to create repository in the '/opt/custom-rpms/' directory use :
```
ansible-playbook playbooks/repo_creation.yaml -e repo_location=/opt/custom-rpms/
```


