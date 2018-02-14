# Radeon Open Compute packages for NixOS

## Installation

This overlay should work with the latest nixos-unstable channel. To use these
packages, clone this repo somewhere and then add `(import /path/to/this/repo)`
to `nixpkgs.overlays` in configuration.nix.

Add these lines to configuration.nix to enable the ROCm stack:
```
  boot.kernelPackages = pkgs.linuxPackages_rocm;
  hardware.firmware = [ pkgs.rocm_compute_firmware ];
  hardware.opengl.enable = true;
  hardware.opengl.extraPackages = [ pkgs.rocm-opencl-icd ]
```

After a `nixos-rebuild` and a reboot, both of these should work:
```
  nix-shell -p rocminfo --run rocminfo
  nix-shell -p opencl-info --run opencl-info
```

(for the former, it may be necessary to link the rocm overlay into
~/.config/nixpkgs/overlays/ so that the rocminfo package is available.)

OpenCL applications should work, and `glxinfo` should report that the Mesa
stack is running hardware-accelerated on an AMD gpu.

### NixOS 17.09/older unstable

If you are using a recent version of nixpkgs that does not contain commit
f620b1b (such as the nixos-17.09 channel), this overlay is likely to work if
commit 5750406 is reverted.  However, this configuration is not frequently
tested, and is not guaranteed to work.

## Hardware support

So far, this has only been tested with a Radeon Vega Frontier Edition.  Other
cards supported by the upstream ROCm should also work, but have not been
tested.