{
  description = "Conversations";

  inputs.nixpkgs = {
    url = "github:NixOS/nixpkgs/nixos-21.05";
  };

  inputs.conversations-src = {
    type = "github";
    owner = "inputmice";
    repo = "conversations";
    rev = "1e1dad780b92254d691cf12a96b283e8e1d87f79";
    flake = false;
  };

  outputs = { self, nixpkgs, conversations-src }:
    let
      getVersion = input: builtins.substring 0 7 input.rev;
      conversations-version = getVersion conversations-src;

      # System types to support.
      supportedSystems = [ "x86_64-linux" ];

      # Mapping from Nix' "system" to Android's "system".
      androidSystemByNixSystem = {
        "x86_64-linux" = "linux-x86_64";
        "x86_64-darwin" = "darwin-x86_64";
      };

      # Helper function to generate an attrset '{ x86_64-linux = f "x86_64-linux"; ... }'.
      forAllSystems = f:
        nixpkgs.lib.genAttrs supportedSystems (system: f system);

      android = {
        versions = {
          tools = "26.1.1";
          platformTools = "31.0.2";
          buildTools = "30.0.2";
          ndk = [ "22.1.7171670" "21.3.6528147" ];
          cmake = "3.18.1";
          emulator = "30.6.3";
        };

        platforms = [ "28" "29" "30" ];
        abis = [ "armeabi-v7a" "arm64-v8a" ];
        extras = [ "extras;google;gcm" ];
      };


      nixpkgsFor = forAllSystems (system:
        import nixpkgs {
          inherit system;
          overlays = [ self.overlay ];
          config.android_sdk.accept_license = true;
        });

    in
    {

      # A Nixpkgs overlay.
      overlay = final: prev:
        with final.pkgs; {

          sdk = (pkgs.androidenv.composeAndroidPackages {
            toolsVersion = android.versions.tools;
            platformToolsVersion = android.versions.platformTools;
            buildToolsVersions = [ android.versions.buildTools ];
            platformVersions = android.platforms;

            includeEmulator = false;
            includeSources = false;
            includeSystemImages = false;

            systemImageTypes = [ "google_apis_playstore" ];
            abiVersions = android.abis;
            cmakeVersions = [ android.versions.cmake ];

            includeNDK = false;
            useGoogleAPIs = false;
            useGoogleTVAddOns = false;
            includeExtras = android.extras;
          });

          aapt2 = callPackage ./nix/pkgs/aapt2 { };

          patchMavenSources = callPackage ./nix/pkgs/patch-maven-srcs { };

          goMavenResolver = callPackage ./nix/pkgs/go-maven-resolver { };

          deps = {
            gradle = callPackage ./nix/deps/gradle { };
          };

          conversations = callPackage ./nix/pkgs/conversations {
            version = conversations-version;
            # Place patched source inside the android dir
            # git clone https://github.com/inputmice/conversations android
            src = ./android;
            gradleBuildType = "ConversationsFreeSystemDebug";
            inherit android;
          };
        };

      # Provide a nix-shell env to work with.
      devShell = forAllSystems (system:
        with nixpkgsFor.${system};
        mkShell rec {
          buildInputs =
            [
              sdk.androidsdk
              adoptopenjdk-jre-openj9-bin-15
              gradle_7
              goMavenResolver
            ];
          ANDROID_SDK_ROOT = "${sdk.androidsdk}/libexec/android-sdk";
          JAVA_HOME = "${adoptopenjdk-jre-openj9-bin-15.home}";
          GRADLE_OPTS = "-Dorg.gradle.project.android.aapt2FromMavenOverride=${ANDROID_SDK_ROOT}/build-tools/${android.versions.buildTools}/aapt2";
          # DEBUG_APK = "${conversations}/app-debug.apk";
        });

      # Provide some binary packages for selected system types.
      packages = forAllSystems (system: {
        inherit (nixpkgsFor.${system}) conversations;
      });

      defaultPackage =
        forAllSystems (system: self.packages.${system}.conversations);

    };
}
