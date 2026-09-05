# Sunshine AppArmor discovery-policy template for this NixOS desktop.
#
# `security-apparmor.nix` substitutes @sunshinePackage@,
# @sunshineAppsFile@, and @sunshineStateDir@ from evaluated NixOS options.
# This lets the attachment and Sunshine-owned files follow the selected package
# and generated configuration across updates without a hard-coded store hash.
# The profile is deliberately loaded in complain mode: accesses that are not
# yet represented below remain available but are audited.
#
# After exercising normal Moonlight desktop and Steam sessions, review only the
# Sunshine-related audit events with aa-logprof.  Transcribe reviewed rules
# here; do not treat /var/cache/apparmor/logprof output as source of truth.

include <tunables/global>

# `mediate_deleted` keeps accesses to already-open, deleted files subject to
# policy.  Deliberately retain the secure default `no_attach_disconnected`:
# upstream cautions that `attach_disconnected` can alias disconnected paths to
# ordinary filesystem paths and should only be enabled for a proven need.
profile nixos-sunshine @sunshinePackage@/bin/sunshine flags=(mediate_deleted) {
  # Base runtime access is intentionally explicit.  Additional permissions are
  # learned during the complain-mode pilot and later minimized for enforcement.
  include <abstractions/base>

  # Permit the initial executable mapping, then keep Sunshine's packaged
  # wrapper in this profile.  NixOS launches `sunshine`, which execs the hidden
  # `.sunshine-wrapped` binary; without this explicit inherit transition the
  # real daemon would fall into a null child profile and the audit data would
  # incorrectly include every descendant process.
  @sunshinePackage@/bin/sunshine mr,
  @sunshinePackage@/bin/.sunshine-wrapped rix,

  # This desktop's declarative application list deliberately launches only
  # this Steam command as `detached`.  Steam subsequently starts Bubblewrap,
  # which needs a broad, independent game runtime (including user namespaces
  # and sandbox capabilities).  Do not grant those powers to the networked
  # Sunshine daemon, and do not make all Nix-store programs executable.
  #
  # A Nix FHS launcher is an interpreted shell script.  AppArmor mediates its
  # shebang interpreter before the script's own path, so a direct transition on
  # the script would not be sufficient in enforce mode.  Keep that tiny setup
  # chain in the Sunshine profile: the Nix Bash interpreter, its runtime, and
  # the sole external helper the generated launcher invokes.  These rules do
  # *not* permit arbitrary store executables.
  # `lib.getExe config.programs.steam.package` resolves through a `bin/steam`
  # symlink to the generated `steam-…-bwrap` shell launcher in the store
  # root.  Keep this pattern exact: it permits only that declaratively selected
  # Steam launcher to run its setup logic.
  /nix/store/????????????????????????????????-steam-*-bwrap rix,
  /nix/store/????????????????????????????????-bash-*/bin/bash ix,
  /nix/store/????????????????????????????????-coreutils-*/bin/coreutils mrix,
  /nix/store/????????????????????????????????-glibc-*/lib/ld-linux-x86-64.so.2 mr,
  /nix/store/????????????????????????????????-glibc-*/lib/lib*.so* mr,
  /nix/store/????????????????????????????????-gmp-with-cxx-*/lib/libgmp.so* mr,
  /nix/store/????????????????????????????????-acl-*/lib/libacl.so* mr,
  /nix/store/????????????????????????????????-attr-*/lib/libattr.so* mr,
  /nix/store/????????????????????????????????-steam-*-fhsenv-rootfs/ r,
  /nix/store/????????????????????????????????-steam-*-fhsenv-rootfs/** r,
  # The generated FHS launcher enumerates only the root's immediate mount
  # points to construct Bubblewrap bind arguments.  Grant metadata/listing
  # access to those directory inodes, not recursive content access.
  / r,
  /{boot,home,mnt,opt,root,run,srv,sys,var}/ r,

  # The generated launcher is an interpreted shell script.  Its final exec is
  # the packaged Bubblewrap binary, so that exact hand-off also needs the
  # unconfined transition.  Without it complain mode creates a null child
  # profile, while enforce mode would block Steam before it starts.  This is
  # intentionally limited to Nix's Bubblewrap package—not a generic shell or
  # arbitrary store executable—because a Steam runtime cannot safely inherit
  # the network-facing Sunshine daemon's confinement.  `Ux` is used here (at
  # the compiled binary, not the script) so its environment is safely scrubbed
  # as the Steam runtime leaves the daemon's security boundary.
  /nix/store/????????????????????????????????-bubblewrap-*/bin/bwrap Ux,

  # Reviewed Sunshine runtime access, taken from successful Moonlight/Steam
  # sessions in complain mode.  Nix store closures are immutable, so these
  # rules allow only the required mappings/reads, never writes.
  /nix/store/????????????????????????????????-glibc-*/lib/gconv/ r,
  /nix/store/????????????????????????????????-glibc-*/lib/gconv/** r,
  # Sunshine, its optional GTK status indicator, and their runtime-selected
  # audio/graphics backends load shared objects from Nix's immutable store.
  # Permit mappings only of shared libraries below package `lib/` directories:
  # this intentionally does *not* allow store executables, arbitrary data,
  # configuration, or writes.  The fixed 32-character store-hash shape avoids
  # the pathological compiler blow-up caused by a leading `*` store glob.
  /nix/store/????????????????????????????????-*/lib/**.so* mr,
  @sunshinePackage@/assets/apps.json r,
  @sunshinePackage@/assets/*.png r,
  @sunshineAppsFile@ r,
  /nix/store/????????????????????????????????-graphics-drivers/share/glvnd/egl_vendor.d/ r,
  /nix/store/????????????????????????????????-graphics-drivers/share/glvnd/egl_vendor.d/*.json r,
  /nix/store/????????????????????????????????-mesa-*/share/glvnd/egl_vendor.d/*.json r,
  /nix/store/????????????????????????????????-nvidia-x11-*/share/glvnd/egl_vendor.d/*.json r,
  /nix/store/????????????????????????????????-nvidia-x11-*-bin/share/nvidia/nvidia-application-profiles-rc r,

  # Sunshine's authenticated state and its rotating diagnostic log belong to
  # this desktop user.  Keep all mutable state within this one application
  # directory; no broader home-directory access is granted.
  @sunshineStateDir@/ rw,
  @sunshineStateDir@/** rwk,

  # Sunshine's NVIDIA encoder and its Wayland DRM capture path need DRM card
  # and render nodes. Their numeric suffixes depend on driver probe order, so
  # match only those two DRM node classes rather than one unstable number.
  /dev/dri/card[0-9]* rw,
  /dev/dri/renderD[0-9]* rw,
  /dev/nvidia0 rw,
  /dev/nvidiactl rw,
  /dev/nvidia-modeset rw,
  /dev/tty rw,
  /dev/uinput rw,

  # Read-only hardware discovery: DRM topology and the active interface MAC
  # address used by Sunshine's network identification.
  @{sys}/devices/**/drm/ r,
  @{sys}/devices/**/net/*/address r,
  @{sys}/devices/virtual/input/input*/ r,
  @{sys}/devices/system/node/ r,
  /proc/driver/nvidia/params r,
  /proc/sys/vm/mmap_min_addr r,
  /dev/char/195:254 w,
  /proc/*/task/*/comm w,
}
