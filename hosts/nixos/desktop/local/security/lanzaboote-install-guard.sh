# shellcheck shell=bash
# Lanzaboote's protectedSystem selects a profile by resolved store path. Check
# that it resolves to the exact generation reported by the EFI boot loader.
install_requested=false
limit=""
protected_system=""
generation_links=()
arguments=("$@")

for ((index = 0; index < ${#arguments[@]}; index++)); do
  case "${arguments[index]}" in
  install) install_requested=true ;;
  --configuration-limit)
    index=$((index + 1))
    limit="${arguments[index]:-}"
    ;;
  --protected-system=*) protected_system="${arguments[index]#--protected-system=}" ;;
  /nix/var/nix/profiles/system-[0-9]*-link)
    generation_links+=("${arguments[index]}")
    ;;
  esac
done

if "$install_requested"; then
  if [[ ! $limit =~ ^[1-9][0-9]*$ || -z $protected_system || ${#generation_links[@]} -eq 0 ]]; then
    echo "lzbt: cannot verify the protected boot generation before installation" >&2
    exit 1
  fi

  entry_file=/sys/firmware/efi/efivars/LoaderEntrySelected-4a67b082-0a4c-41cf-b6c7-440b29bb8c4f
  if [[ ! -r $entry_file ]]; then
    echo "lzbt: cannot read the running EFI entry; refusing to prune boot measurements" >&2
    exit 1
  fi
  # EFI variables begin with four attribute bytes; this entry name is UTF-16LE
  # with ASCII characters and interleaved NUL bytes.
  current_entry="$(tail -c +5 "$entry_file" | tr -d '\000')"
  if [[ $current_entry =~ ^nixos-generation-([0-9]+)-.*\.efi$ ]]; then
    current_generation="${BASH_REMATCH[1]}"
  else
    echo "lzbt: cannot identify the running NixOS EFI entry" >&2
    exit 1
  fi

  current_link="/nix/var/nix/profiles/system-${current_generation}-link"
  if ! protected_target="$(readlink -f -- "$protected_system")" ||
    ! current_target="$(readlink -f -- "$current_link")" ||
    [[ $protected_target != "$current_target" ]]; then
    echo "lzbt: protected system does not match booted generation $current_generation" >&2
    exit 1
  fi

  matches=0
  for link in "${generation_links[@]}"; do
    if ! target="$(readlink -f -- "$link")"; then
      echo "lzbt: cannot resolve generation link $link" >&2
      exit 1
    fi
    if [[ $target == "$protected_target" ]]; then
      matches=$((matches + 1))
    fi
  done
  if ((matches != 1)); then
    echo "lzbt: booted system matches $matches profile links; cannot protect its exact EFI entry" >&2
    exit 1
  fi
fi
