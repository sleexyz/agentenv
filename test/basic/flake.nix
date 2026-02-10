{
  description = "Basic test flake for agentenv";

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
              hello
              jq
              curl
            ];

            shellHook = ''
              echo "=== agentenv dev shell ==="
              echo "hello version: $(hello --version 2>&1 | head -1)"
              echo "jq version: $(jq --version)"
              echo "Working directory: $(pwd)"
              echo "=========================="
            '';
          };
        });
    };
}
