#!@bash@
# shellcheck shell=bash
extension_root="$HOME/Library/Application Support/net.imput.helium/nix-managed-extensions"
extension_update_url=@extensionUpdateUrl@
extension_dirs=""
@mkdir@ -p "$extension_root"

while IFS= read -r extension_id; do
  [ -n "$extension_id" ] || continue
  extension_dir="$extension_root/$extension_id"
  [ -d "$extension_dir" ] && extension_dirs="${extension_dirs:+$extension_dirs,}$extension_dir"
done <@extensionIdsFile@

(
  update_lock="$extension_root/.update-lock"
  @mkdir@ "$update_lock" 2>/dev/null || exit 0
  trap '@rmdir@ "$update_lock"' EXIT
  while IFS= read -r extension_id; do
    [ -n "$extension_id" ] || continue
    extension_dir="$extension_root/$extension_id"
    temporary_dir="$(@mktemp@ -d "$extension_root/.${extension_id}.XXXXXX")"
    if [ -n "$temporary_dir" ]; then
      if @curl@ --fail --location --retry 0 --connect-timeout 3 --max-time 8 --silent --show-error \
        --output "$temporary_dir/extension.crx" \
        "$extension_update_url?response=redirect&acceptformat=crx2,crx3&prodversion=9999.0.0.0&x=id%3D${extension_id}%26installsource%3Dondemand%26uc" &&
        @python@ @crxToZip@ "$temporary_dir/extension.crx" "$temporary_dir/extension.zip" &&
        @unzip@ -q "$temporary_dir/extension.zip" -d "$temporary_dir/unpacked" &&
        [ -f "$temporary_dir/unpacked/manifest.json" ]; then
        @rm@ -rf "$extension_dir.next" "$extension_dir"
        @mv@ "$temporary_dir/unpacked" "$extension_dir.next"
        @mv@ "$extension_dir.next" "$extension_dir"
      fi
      @rm@ -rf "$temporary_dir"
    fi
    # The browser has already received the current extension list. A newly
    # downloaded extension is intentionally picked up on the next launch.
  done <@extensionIdsFile@
) >/dev/null 2>&1 &

[ -z "$extension_dirs" ] || set -- "--load-extension=$extension_dirs" "$@"
