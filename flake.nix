{
  description = "A combination of two embedded data storage C language libraries: SQLite and LMDB";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    not-fork-src = {
      url = "https://lumosql.org/src/not-forking/tarball/4ad471fea7/Not-forking-4ad471fea7.tar.gz";
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
        notforkMirror = final.linkFarm "foo"
          (final.lib.mapAttrsToList (n: v: { name = v.expectedMirrorPath; path = v.path; }) final.fetchedFiles);
        parsedLock = builtins.fromJSON (builtins.readFile final.myNotForkDb);
        fetchedFiles = builtins.removeAttrs final.rawFetchedFiles [ "version" ];
        rawFetchedFiles =
          builtins.mapAttrs
            (n: v:
              if n == "version"
              then builtins.trace "using not-fork lockfile at version ${builtins.toString final.parsedLock.version}" final.parsedLock.version
              else if v.locked.type == "tarball"
              then
                {
                  path = builtins.fetchurl {
                    url = v.locked.url;
                    sha256 = v.locked.sha256;
                  };
                  expectedMirrorPath = n + ".tar.gz";
                }
              else if v.locked.type == "git"
              then
                {
                  path = builtins.fetchGit {
                    url = v.locked.url + ".git";
                    rev = v.locked.rev;
                    allRefs = true;
                  };
                  expectedMirrorPath = n + "-" + final.parsedLock.${n}.locked.rev;
                }
              else if v.locked.type == "fossil"
              then
                {
                  path = builtins.fetchTree "fsl+${v.locked.url}?rev=${v.locked.rev}";
                  expectedMirrorPath = n + "-" + final.parsedLock.${n}.locked.rev;
                }
              else throw "could not read lockfile"
            )
            final.parsedLock;
        myNotForkDb = final.pkgs.runCommand "foo" {
          preBuild = ''
          '';
          outputHashMode = "recursive";
          outputHashAlgo = "sha256";
          outputHash = "sha256-bMKO10u9a+eSY9kaYTBGrwFxJ12zYQKmT0a9JXNN0/M=";
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
          not-fork --input ${final.lumosql.src}/not-fork.d --online --build-json-lock=$out
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
          outputHash = "";
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
          inherit (nixpkgsFor.${system}) lumosql not-fork myNotForkDb parsedLock fetchedFiles notforkMirror;
        });
      defaultPackage = forAllSystems (system: self.packages.${system}.lumosql);
    };
}
