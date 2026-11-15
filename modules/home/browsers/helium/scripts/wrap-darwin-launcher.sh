# shellcheck shell=bash
# Sourced by Home Manager or the owning build phase.
# shellcheck disable=SC2154
heliumApp="$out/Applications/Helium.app"
heliumExe="$heliumApp/Contents/MacOS/Helium"

if [ -x "$heliumExe" ] && [ ! -e "$heliumExe-unwrapped" ]; then
  mv "$heliumExe" "$heliumExe-unwrapped"
  makeWrapper "$heliumExe-unwrapped" "$heliumExe" \
    @flagArgs@ \
    --run @lib_escapeShellArg_source_darwinHeliumPreferenceHook_source_@

  rm -f "$out/bin/helium"
  makeWrapper "$heliumExe-unwrapped" "$out/bin/helium" \
    @flagArgs@ \
    --run @lib_escapeShellArg_source_darwinHeliumPreferenceHook_source_@
fi
