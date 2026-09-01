# LanguageTool HTTP server AppArmor discovery-policy template.
#
# `security-apparmor.nix` replaces @languageToolPackage@ with the evaluated
# Nix package output.  The profile is attached specifically by the user
# service's AppArmorProfile= setting, so it never confines LibreOffice or a
# separately launched Java program.

include <tunables/global>

profile nixos-languagetool @languageToolPackage@/bin/languagetool-http-server flags=(mediate_deleted) {
  include <abstractions/base>

  # Preserve the profile across the wrapper's Bash and Java exec chain.  The
  # Java runtime and its additional libraries are intentionally learned in
  # complain mode before any enforcement decision.
  @languageToolPackage@/bin/languagetool-http-server mrix,
  /nix/store/????????????????????????????????-bash-*/bin/bash ix,
  /nix/store/????????????????????????????????-openjdk-minimal-jre-*/bin/java ix,
  @languageToolPackage@/share/languagetool-server.jar r,
  @languageToolPackage@/share/** r,
}
