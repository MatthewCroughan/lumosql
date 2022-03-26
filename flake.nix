{
  description = "A combination of two embedded data storage C language libraries: SQLite and LMDB";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-21.11";
    not-fork-src = {
      url = "https://lumosql.org/dist/not-fork-0.5.tar.gz";
      flake = false;
    };
    lumosql-src = {
      url = "https://lumosql.org/dist/lumosql-2022-03-07.tar.gz";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, not-fork-src, lumosql-src }:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs supportedSystems (system: f system);
      nixpkgsFor = forAllSystems (system: import nixpkgs { inherit system; overlays = [ self.overlay ]; });
    in
    {
      overlay = final: prev: {
        not-fork = final.perl532Packages.buildPerlPackage {
          pname = "NotFork";
          version = "0.5";
          src = not-fork-src;
          outputs = [ "out" ];
          buildInputs = with final.pkgs.perl532Packages; [ TextGlob Git ];
        };
        lumosql = final.stdenv.mkDerivation {
          name = "lumosql";
          src = lumosql-src;
          outputHashMode = "recursive";
          outputHashAlgo = "sha256";
          outputHash = "sha256-61paS4HoJOPKkMrmLfc0fJbt9RH64wcVfGeit5zCT9k=";
          # This is a proof of concept, so the installPhase is hardcoded to
          # take the output of build/3.18.2 and put it into the result
          installPhase = ''
            mkdir -p $out/bin
            cp build/3.38.2/lumo/build/sqlite3 $out/bin
          '';
          preBuild = ''
            # LumoSQL's Makefile calls out to not-fork, which wants to use
            # fossil, and other tools to fetch files.
            export USER=1000
            export HOME=$TMP
            export TARGETS=3.38.2
          '';
          buildInputs = with final; [ tcl tclx which cacert ];
          nativeBuildInputs = with final; [ not-fork fossil git wget curl file ];
        };
      };
      packages = forAllSystems (system:
        {
          inherit (nixpkgsFor.${system}) lumosql not-fork;
        });
      defaultPackage = forAllSystems (system: self.packages.${system}.lumosql);
    };
}
