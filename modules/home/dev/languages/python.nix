{ pkgs, ... }:
{
  home.packages = with pkgs; [
    python3

    uv
    ruff
    ty

    mypy
    pyright
  ];
}
