{ pkgs, ... }:
{
  home.packages = with pkgs; [ railway ];
}
