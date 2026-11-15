{
  resolve =
    {
      lib,
      polarity,
      colors,
    }:
    let
      # Base16 permits missing variant metadata, including generated palettes.
      # Compare encoded RGB brightness to classify their appearance direction.
      # Actual text contrast is checked separately by rendering GTK controls.
      brightness =
        base:
        2126 * lib.toInt colors."${base}-rgb-r"
        + 7152 * lib.toInt colors."${base}-rgb-g"
        + 722 * lib.toInt colors."${base}-rgb-b";
    in
    if polarity != "either" then
      polarity
    else if
      builtins.elem (colors.variant or "unspecified") [
        "dark"
        "light"
      ]
    then
      colors.variant
    else if brightness "base00" < brightness "base05" then
      "dark"
    else
      "light";
}
