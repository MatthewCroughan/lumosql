{
  description = "A combination of two embedded data storage C language libraries: SQLite and LMDB";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    not-fork-src = {
      url = "https://lumosql.org/src/not-forking/tarball/2df922b19f/Not-forking-2df922b19f.tar.gz";
      flake = false;
    };
    lumosql-src = {
      url = "https://lumosql.org/src/lumosql/tarball/185cc271c1/Lumosql-185cc271c1.tar.gz";
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
        parsedLock = builtins.fromJSON (builtins.readFile final.myNotForkDb);
        fetchedFiles =
          builtins.mapAttrs
            (n: v:
              if v.locked.type == "tarball"
              then builtins.fetchurl {
                url = v.locked.url;
                sha256 = v.locked.sha256;
              }
              else if v.locked.type == "git"
              then builtins.fetchGit {
                url = v.locked.url + ".git";
                rev = v.locked.rev;
              }
              else throw "could not read lockfile"
            )
            final.parsedLock;
        myNotForkDb = final.pkgs.runCommand "foo" {
          preBuild = ''
          '';
          outputHashMode = "recursive";
          outputHashAlgo = "sha256";
          outputHash = "sha256-4UiIvosXZs6R9d5QzVBs7wsNkC84rQ1GAp9rvHjE1vw=";
          buildInputs = with final; [ not-fork cacert ];
        }
        ''
          # LumoSQL's Makefile calls out to not-fork, which wants to use
          # fossil, and other tools to fetch files, which require these vars
          # set.
          export USER=1000
          export HOME=$TMP
          export TARGETS=3.38.2
          export SOURCE_DATE_EPOCH=315532800
#          find . -print0 | xargs -0 touch -ht 197001010000.01
#          find . -print0 | xargs -0 touch -ht 197001010000.01
#          not-fork --input ${final.lumosql.src}/not-fork.d --online --update --query --cache $out/not-fork-cache
#          not-fork --input ${final.lumosql.src}/not-fork.d --offline --build-json-lock=$out
          not-fork --input ${final.lumosql.src}/not-fork.d --online --prefer-tarball-for=fossil --build-json-lock=$out
        '';
        not-fork = final.perl534Packages.buildPerlPackage {
          pname = "NotFork";
          version = "0.6";
          src = not-fork-src;
          outputs = [ "out" ];
          buildInputs = with final.pkgs.perl534Packages; [ TextGlob Git final.pkgs.makeWrapper ];
          # Wrap everything in postInstall to give not-fork the runtime
          # dependencies it needs.
          postInstall = ''
            for n in "$out/bin/"*; do
              wrapProgram "$n" \
                --prefix PERL5LIB : "$PERL5LIB" \
                --prefix PATH : ${with final; lib.makeBinPath [ git fossil curl wget file gnupatch ]}
            done
          '';
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
            mv build/3.38.2/lumo/build/sqlite3 $out/bin
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
          inherit (nixpkgsFor.${system}) lumosql not-fork myNotForkDb parsedLock fetchedFiles;
        });
      defaultPackage = forAllSystems (system: self.packages.${system}.lumosql);
    };
}
