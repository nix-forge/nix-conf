# shellcheck shell=bash
: "${CC:?Nix supplies the compiler}" "${witnessSource:?Nix supplies the source}" "${out:?Nix supplies the output}"
"$CC" -std=c11 -Wall -Wextra -Werror -fPIC -shared "$witnessSource" -ldl -lEGL -o "$out"
