{
  # Use the vendor bundle name. Retire the former path through the guarded
  # lifecycle transaction so both names cannot remain eligible launch targets.
  macos.applications.protectedApps.codex.previousBundles = [ "ChatGPT Managed.app" ];
}
