{
  description = "agentenv test environment — personal tools";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = { nixpkgs, ... }: let
    pkgs = nixpkgs.legacyPackages.aarch64-linux;
  in {
    packages.default = pkgs.buildEnv {
      name = "personal-tools";
      paths = with pkgs; [
        # Core unix (replaces base image packages we remove)
        coreutils
        bashInteractive
        findutils
        gnugrep
        gnused
        gnutar
        gzip
        less
        which
        curl

        # Personal tools
        zsh
        neovim
        tmux
        ripgrep
        fd
        fzf
        jq
        tree
        htop
        eza
        zoxide
        unzip
        wget
        git
        helix
      ];
    };
  };
}
