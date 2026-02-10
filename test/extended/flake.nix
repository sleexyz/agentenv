{
  description = "Extended test flake for agentenv — overlapping deps with basic";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
  };

  outputs = { self, nixpkgs }:
    let
      systems = [ "aarch64-linux" "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      devShells = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            buildInputs = with pkgs; [
              jq
              curl
              ripgrep
            ];

            shellHook = ''
              echo "=== agentenv extended dev shell ==="
              echo "jq version: $(jq --version)"
              echo "ripgrep version: $(rg --version | head -1)"
              echo "Working directory: $(pwd)"
              echo "===================================="
            '';
          };
        });
    };
}
