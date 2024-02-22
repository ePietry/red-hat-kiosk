# Kiosk Setup Configuration

## Pre-requisites

```sh
sudo dnf install -y git rpm-build rpmdevtools
cd rpms
rm $HOME/rpmbuild && ln -sf $PWD $HOME/rpmbuild
```

## Build the kiosk-config package

```sh
spectool -g -R $HOME/rpmbuild/SPECS/kiosk-config.spec
rpmbuild -ba $HOME/rpmbuild/SPECS/kiosk-config.spec
```

The resulting package is in `$HOME/rpmbuild/RPMS/x86_64`.

## Rebuild the Google Chrome RPM

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
```

The resulting package is in `$HOME/rpmbuild/RPMS/x86_64`.
