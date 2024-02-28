Name:       microshift-manifests
Version:    0.0.1
Release:    rh1
Summary:    Custom manifests for Microshift
License:    BSD
Source0:    microshift-kustomization.yaml
Source1:    microshift-main-manifest.yaml
Requires:   microshift

%description
Custom manifests for Microshift

# Since we don't recompile from source, disable the build_id checking
%global _missing_build_ids_terminate_build 0
%global _build_id_links none
%global debug_package %{nil}

# We are evil, we have no changelog !
%global source_date_epoch_from_changelog 0

%prep
cp %{S:0} kustomization.yaml
cp %{S:1} main-manifest.yaml

%build

%install
install -m 0755 -d %{buildroot}/usr/lib/microshift/manifests.d/custom/
install -m 0644 -D kustomization.yaml %{buildroot}/usr/lib/microshift/manifests.d/custom/kustomization.yaml
install -m 0644 -D main-manifest.yaml %{buildroot}/usr/lib/microshift/manifests.d/custom/main-manifest.yaml

%files
%attr(0644, root, root) /usr/lib/microshift/manifests.d/custom/kustomization.yaml
%attr(0644, root, root) /usr/lib/microshift/manifests.d/custom/main-manifest.yaml

%changelog
