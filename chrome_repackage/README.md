# Google Chrome RPM Installation Guide

This guide provides step-by-step instructions for downloading and rebuilding the Google Chrome RPM package on a RPM-based Linux distribution.

## Prerequisites

Before you proceed, ensure that you have the following prerequisites installed on your system:

- `rpmrebuild`: A tool for rebuilding RPM packages.
- `rpmbuild`: The RPM Package Manager build tool.

## Installation Steps

1. **Download Google RPM**

    ```bash
    # Replace <URL> with the actual download URL
    wget <URL>/google-chrome-stable-119.0.6045.199-1.x86_64.rpm
    ```

2. **Rebuild the RPM Package**

    ```bash
    rpmrebuild -s google-chrome-stable.spec -p google-chrome-stable-119.0.6045.199-1.x86_64.rpm
    ```

3. **Extract the Contents**

    ```bash
    rpm2cpio google-chrome-stable-119.0.6045.199-1.x86_64.rpm | cpio -idmv
    ```

4. **Move Google Chrome to the Desired Location**

    ```bash
    mv opt/google usr/bin/
    ```

5. **Create Symbolic Links**

    ```bash
    cd usr/bin/
    rm -f google-chrome-stable
    ln -s google/chrome/google-chrome google-chrome-stable
    ln -s google/chrome/google-chrome chrome
    cd ../..
    ```

6. **Create RPM Build Directory**

    ```bash
    mkdir -p $HOME/rpmbuild/BUILDROOT/google-chrome-stable-119.0.6045.199-1.x86_64
    ```

7. **Copy Files to RPM Build Directory**

    ```bash
    for i in etc usr; do cp -r $i $HOME/rpmbuild/BUILDROOT/google-chrome-stable-119.0.6045.199-1.x86_64/; done
    ```

8. **Build the RPM Package**

    ```bash
    rpmbuild -bb google-chrome-stable.spec
    ```

After completing these steps, you should have successfully downloaded, rebuilt, and repackaged the Google Chrome RPM for your system. The resulting RPM package will be available in the RPM build directory (`$HOME/rpmbuild/RPMS/x86_64/`).

Note: Ensure that you replace `<URL>` with the actual download URL of the Google Chrome RPM.

