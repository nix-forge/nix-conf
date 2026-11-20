# Render module-option and build-hook strings without import-from-derivation.
# Callers escape values for the destination language. Null retains a literal token.
src: replacements:
let
  content = if builtins.isAttrs src then src.text else builtins.readFile src;
  origin = if builtins.isAttrs src then src.name or "inline text" else toString src;
  names = builtins.attrNames replacements;
  marker = name: "@${name}@";
  value =
    name:
    let
      input = replacements.${name};
    in
    if input == null then
      marker name
    else if builtins.isPath input then
      "${input}"
    else
      toString input;
  validName = name: builtins.match "[a-zA-Z_][a-zA-Z0-9_]*" name != null;
  present = name: builtins.length (builtins.split (marker name) content) > 1;
  tokens = map builtins.head (
    builtins.filter builtins.isList (builtins.split "@([a-zA-Z_][a-zA-Z0-9_]*)@" content)
  );
  missing = builtins.filter (name: !(builtins.hasAttr name replacements)) tokens;
  extra = builtins.filter (name: !(present name)) names;
in
if !(builtins.all validName names) then
  throw "renderText: invalid placeholder name"
else if missing != [ ] then
  throw "renderText: missing replacements in ${origin}: ${builtins.concatStringsSep ", " missing}"
else if extra != [ ] then
  throw "renderText: unused replacements in ${origin}: ${builtins.concatStringsSep ", " extra}"
else
  builtins.replaceStrings (map marker names) (map value names) content
