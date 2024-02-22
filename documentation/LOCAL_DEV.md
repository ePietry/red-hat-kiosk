# Local development

## Create a RHEL 9 Virtual Machine to play with os-builder and microshift

Pre-requisites :
- Fedora 39 [with Libvirt installed](https://docs.fedoraproject.org/en-US/quick-docs/virtualization-getting-started/)

Download [RHEL 9.3](https://access.redhat.com/downloads/content/rhel) and save `rhel-9.3-x86_64-kvm.qcow2` in `/var/lib/libvirt/images/base-images`.

Create a file named `user-data.yaml` with the follwing content.

```yaml
#cloud-config

users:
- name: nmasse
  gecos: Nicolas MASSE
  groups: wheel
  lock_passwd: false
  passwd: $6$...123 # generate the hash with the "mkpasswd" command
  ssh_authorized_keys:
  - ssh-ed25519 123...456

write_files:
- path: /etc/sudoers
  content: |
    Defaults   !visiblepw
    Defaults    always_set_home
    Defaults    match_group_by_gid
    Defaults    always_query_group_plugin
    Defaults    env_reset
    Defaults    env_keep =  "COLORS DISPLAY HOSTNAME HISTSIZE KDEDIR LS_COLORS"
    Defaults    env_keep += "MAIL PS1 PS2 QTDIR USERNAME LANG LC_ADDRESS LC_CTYPE"
    Defaults    env_keep += "LC_COLLATE LC_IDENTIFICATION LC_MEASUREMENT LC_MESSAGES"
    Defaults    env_keep += "LC_MONETARY LC_NAME LC_NUMERIC LC_PAPER LC_TELEPHONE"
    Defaults    env_keep += "LC_TIME LC_ALL LANGUAGE LINGUAS _XKB_CHARSET XAUTHORITY"
    Defaults    secure_path = /sbin:/bin:/usr/sbin:/usr/bin
    root    ALL=(ALL)       ALL
    %wheel  ALL=(ALL)       NOPASSWD: ALL
    #includedir /etc/sudoers.d
  permissions: '0440'
  append: false
```

Create the RHEL9 VM.

```sh
sudo mkdir -p /var/lib/libvirt/images/rhel9 /var/lib/libvirt/images/base-images
sudo dnf install -y cloud-utils genisoimage
sudo cloud-localds /var/lib/libvirt/images/rhel9/cloud-init.iso user-data.yaml

sudo virt-install --name rhel9 --autostart --noautoconsole --cpu host-passthrough \
             --vcpus 4 --ram 8192 --os-variant rhel9.3 \
             --disk path=/var/lib/libvirt/images/rhel9/rhel9.qcow2,backing_store=/var/lib/libvirt/images/base-images/rhel-9.3-x86_64-kvm.qcow2,size=100 \
             --disk path=/var/lib/libvirt/images/rhel9/data.qcow2,size=20 \
             --network network=default \
             --console pty,target.type=virtio --serial pty --import \
             --disk path=/var/lib/libvirt/images/rhel9/cloud-init.iso,readonly=on \
             --sysinfo system.serial=ds=nocloud

sudo virsh console rhel9
```

Create a PV and a VG for Microshift.

```sh
sudo pvcreate /dev/vdb
sudo vgcreate data /dev/vdb
```

## Utility script that creates a VM to install RHEL for Edge

```sh
#!/bin/bash

set -Eeuo pipefail

DOMAIN="kiosk"
BASE_IMAGE_URL="your-user@rhel9-vm:red-hat-kiosk/imagebuilder/kiosk.iso"
BASE_IMAGE_FILENAME="$(basename "$BASE_IMAGE_URL")"
OS_VARIANT="rhel9.3"

virsh destroy "$DOMAIN" || true
virsh undefine "$DOMAIN" --nvram || true

rm -rf "/var/lib/libvirt/images/$DOMAIN/"
mkdir -p "/var/lib/libvirt/images/$DOMAIN"

scp "$BASE_IMAGE_URL" "/var/lib/libvirt/images/$DOMAIN/install.iso"

virt-install --name "$DOMAIN" --autostart --cpu host-passthrough \
             --vcpus 2 --ram 4096 --os-variant "$OS_VARIANT" \
             --disk "path=/var/lib/libvirt/images/$DOMAIN/os.qcow2,size=20" \
             --disk "path=/var/lib/libvirt/images/$DOMAIN/data.qcow2,size=100" \
             --network network=default \
             --console pty,target.type=virtio --serial pty \
             --cdrom "/var/lib/libvirt/images/$DOMAIN/install.iso" \
             --boot uefi
```

Use it like follow :

```sh
eval $(ssh-agent)
ssh-add
sudo --preserve-env=SSH_AUTH_SOCK ./kiosk.sh
```

## Use Microshift

```sh
export KUBECONFIG=/var/lib/microshift/resources/kubeadmin/kubeconfig
oc get nodes
```