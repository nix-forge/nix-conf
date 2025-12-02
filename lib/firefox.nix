{ lib }:
{
  toUserJS =
    kv:
    lib.concatLines (
      lib.mapAttrsToList (
        k: v: "user_pref(${builtins.toJSON k}, ${builtins.toJSON v});"
      ) kv
    );
}
