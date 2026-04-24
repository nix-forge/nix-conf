{ pkgs, ... }:
{
  home.packages = with pkgs; [ wrangler ];
}
