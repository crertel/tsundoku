{
  description = "Tsundoku Phoenix development environment";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs, ... }:
    let
      systems = [ "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixpkgs-fmt);

      packages = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.callPackage ./nix/package.nix { };
          tsundoku = pkgs.callPackage ./nix/package.nix { };
        });

      nixosModules.default = import ./nix/module.nix { inherit self; };
      nixosModules.tsundoku = self.nixosModules.default;

      devShells = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          beamPkgs = pkgs.beam.packagesWith pkgs.beam.interpreters.erlang_27;
        in
        {
          default = pkgs.mkShell {
            packages = [
              beamPkgs.erlang
              beamPkgs.elixir_1_18
              beamPkgs.hex
              beamPkgs.elixir-ls

              pkgs.esbuild
              pkgs.inotify-tools
              pkgs.postgresql_17
              pkgs.tailwindcss
              pkgs.web-ext
            ];

            ERL_AFLAGS = "-kernel shell_history enabled";
            MIX_ESBUILD_PATH = "${pkgs.esbuild}/bin/esbuild";
            MIX_ESBUILD_VERSION = pkgs.esbuild.version;
            MIX_TAILWIND_PATH = "${pkgs.tailwindcss}/bin/tailwindcss";
            MIX_TAILWIND_VERSION = pkgs.tailwindcss.version;

            shellHook = ''
              export MIX_HOME="$PWD/.nix-mix"
              export HEX_HOME="$PWD/.nix-hex"
              mkdir -p "$MIX_HOME" "$HEX_HOME"
              export ERL_LIBS="$HEX_HOME/lib/erlang/lib"
              export PATH="$MIX_HOME/bin:$MIX_HOME/escripts:$HEX_HOME/bin:$PATH"
              mix local.hex --if-missing --force
              mix local.rebar --if-missing --force
            '';
          };
        });
    };
}
