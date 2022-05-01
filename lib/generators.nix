{ lib, ... }: let
    inherit (builtins) isPath isString;
    inherit (lib) flatten kube pathExists attrValues mapAttrs
        recImportDirs recursiveMerge recursiveModuleTraverse;
in rec {
    # Builds a Fractal flake with the standard directory structure
    makeStdFlake = {
        inputs, # Inputs from the top-level flake
        flakes ? {}, # Flakes to import modules from
        namespace ? null # Configuration namespace used for modules generated with substituters
    }: let
        inherit (inputs) self;
        root = self.outPath;
    in {
        kube = {
            # output of all the clusters we can build
            clusters = let
                dir = root + "/clusters";
            in if !(pathExists dir) then {} else recImportDirs {
                inherit dir;
                _import = n: kube.clusterConfiguration {
                    configuration = dir + "/${n}";
                    extraModules = flatten (map (f: f.kube.modules) (flakes ++ [self]));
                    extraSpecialArgs = { inherit inputs self; };
                };
            };

            # output of all modules used to make clusters
            modules = let
                path = root + "/modules";
                ip = f: path: if pathExists path then f path else [];
                sub = type: import ./substituters/module.nix {
                    inherit type namespace;
                };
            in flatten [
                (ip recursiveModuleTraverse (path + "/base"))
                (ip recursiveModuleTraverse (path + "/crds"))
                (ip (p: attrValues (kube.componentImport p (sub "features"))) (path + "/features"))
                (ip (p: attrValues (kube.componentImport p (sub "operators"))) (path + "/operators"))
                (ip (p: attrValues (kube.componentImport p (sub "services"))) (path + "/services"))
            ];

            packages = let
                path = root + "/packages";
                sub = import ./substituters/package.nix;
            in if pathExists path then mapAttrs (_: p: import p)
                (kube.componentImport path sub) else {};
        };
    };
}