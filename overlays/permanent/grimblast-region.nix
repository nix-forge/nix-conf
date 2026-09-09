# Region capture deliberately excludes clickable monitor rectangles.
package:
package.overrideAttrs (old: {
  postPatch = (old.postPatch or "") + ''
    substituteInPlace grimblast --replace-fail 'slurp -o ' 'slurp '
  '';
})
