{
  port,
  pkgs,
  lib,
  config,
  ...
}:
let
  mcVersion = "1.21";
  serverVersion = lib.replaceStrings [ "." ] [ "_" ] "fabric-${mcVersion}";

  fetchurl = pkgs.fetchurl;
in
{
  enable = true;
  openFirewall = true;
  autoStart = true; # if false then use systemctl start minecraft-server-${servername}

  package = pkgs.minecraftServers.${serverVersion};

  jvmOpts =
    let
      ram = "4G";
    in
    builtins.concatStringsSep " " [
      "-Xms${ram}"
      "-Xmx${ram}"
      "-XX:+UseG1GC"
      "-XX:+ParallelRefProcEnabled"
      "-XX:MaxGCPauseMillis=200"
      "-XX:+UnlockExperimentalVMOptions"
      "-XX:+DisableExplicitGC"
      "-XX:+AlwaysPreTouch"
      "-XX:G1HeapWastePercent=5"
      "-XX:G1MixedGCCountTarget=4"
      "-XX:G1MixedGCLiveThresholdPercent=90"
      "-XX:G1RSetUpdatingPauseTimePercent=5"
      "-XX:SurvivorRatio=32"
      "-XX:+PerfDisableSharedMem"
      "-XX:MaxTenuringThreshold=1"
      "-Dusing.aikars.flags=https://mcflags.emc.gs"
      "-Daikars.new.flags=true"

      # for under 12GB RAM
      "-XX:G1NewSizePercent=30"
      "-XX:G1MaxNewSizePercent=40"
      "-XX:G1HeapRegionSize=8M"
      "-XX:G1ReservePercent=20"
      "-XX:InitiatingHeapOccupancyPercent=15"

      # for over 12GB RAM
      # "-XX:G1NewSizePercent=40"
      # "-XX:G1MaxNewSizePercent=50"
      # "-XX:G1HeapRegionSize=16M"
      # "-XX:G1ReservePercent=15"
      # "-XX:InitiatingHeapOccupancyPercent=20"
    ];

  serverProperties = {
    server-port = port;
    "query.port" = port;
    difficulty = 3; # 0: peaceful, 1: easy, 2: normal, 3: hard
    enforce-secure-profile = true; # true: only allow secure profiles to join
    gamemode = 1; # 0: survival, 1: creative, 2: adventure, 3: spectator
    force-gamemode = true; # true: force gamemode on join
    motd = "Welcome to the server!"; # server message
    pvp = true; # true: players can attack each other
    simulation-distance = 10; # distance in chunks from the player that the server will simulate
    view-distance = 16; # distance in chunks from the player that the server will send to the player
  };

  symlinks = {
    mods = pkgs.linkFarmFromDrvs "mods" (
      builtins.attrValues {
        # Fabric API
        FabricAPI = fetchurl {
          url = "https://cdn.modrinth.com/data/P7dR8mSH/versions/1cXs6RWI/fabric-api-0.100.3%2B1.21.jar";
          sha512 = "3257d1fe02c9f7710feec955d4e91bd1de69bbe930a3779602ea7c78920ca1f9cef3c4450158cabaddc330d2d4a96a2558d8f136c770b2657886797f2452eb24";
        };

        # Server Optimization
        Lithium = fetchurl {
          url = "https://cdn.modrinth.com/data/gvQqBUqZ/versions/OC4JOVBe/lithium-fabric-mc1.21-0.12.5.jar";
          sha512 = "3054de66ffaad9184c44fabafa2a8f858f18e76302c971218f5b36f84b0de9306b076fd2d4a4df2ab56df2676093edda9602dcdb5d2301b4006d2770205d728e";
        };
        FerriteCore = fetchurl {
          url = "https://cdn.modrinth.com/data/uXXizFIs/versions/wmIZ4wP4/ferritecore-7.0.0-fabric.jar";
          sha512 = "0f2f9b5aebd71ef3064fc94df964296ac6ee8ea12221098b9df037bdcaaca7bccd473c981795f4d57ff3d49da3ef81f13a42566880b9f11dc64645e9c8ad5d4f";
        };
        # ModernFix = fetchurl {
        #   url = "https://cdn.modrinth.com/data/nmDcB62a/versions/AFvoBfkx/modernfix-fabric-5.18.3%2Bmc1.21.jar";
        #   sha512 = "45e021ec676ba3b8dc3d895d132b76ee8a681a1d73d19677f5c22d2ca7617607a941d5c56e729c2bb242980d0e3abe8ff095d962d550f4a3f1efef0e9aff4c15";
        # };
        Debugify = fetchurl {
          url = "https://cdn.modrinth.com/data/QwxR6Gcd/versions/mOk69fib/Debugify-1.21%2B1.0.jar";
          sha512 = "6fa9c2eec2382f0d188356702c69cd1ed86a152a033c963a318658353686c2d873c6c34c3e748879258c407310f4a1822aa4d23efdedfc2d4d8b31be40f4aa91";
        };
        C2M = fetchurl {
          url = "https://cdn.modrinth.com/data/VSNURh3q/versions/BTWFOuYd/c2me-fabric-mc1.21-0.2.0%2Balpha.11.101.jar";
          sha512 = "ae59a500368ef3b0754f7c9f94ff1668c8bf391eadf88284ee2587181147b97ce6b30b728800c5e28ad67ef3b6ff8f82011f5e4aeecee6e29447c02866cae40f";
        };
        # LetMeDespawn = fetchurl {
        #   url = "https://cdn.modrinth.com/data/vE2FN5qn/versions/7OSOHbMe/letmedespawn-1.3.0.jar";
        #   sha512 = "68cf59c23859bd03725f0029591d77607897f0bce83ca0d1b856c667c4b53bbe7b07fdca3de923643c33fec5af46afe3cf47619fe126260c5f5ed077c00e3beb";
        # };
        ServerCore = fetchurl {
          url = "https://cdn.modrinth.com/data/4WWQxlQP/versions/FW5dMqws/servercore-fabric-1.5.3%2B1.21.jar";
          sha512 = "c762bab034aa00964680833d374beef021d9cd83a8bf0d1c625040571c196d2aa9488c3b0c4a8d6bd16b25ea008b07262f9856fb0d872bc5a579af42b18bd263";
        };
        RecipeCooldown = fetchurl {
          url = "https://cdn.modrinth.com/data/7LEWYKTV/versions/oe5KEgWu/RecipeCooldown-1.0.0.jar";
          sha512 = "84d52e7dbb2aa780b1ba0ec436a58135b1af53f5612bdfeaafb701df10f91df09fad15c7b2dc23552a0a362bc38fd65765f6e82737a45faa163b8dbe89fe7101";
        };

        # Food
        # AppleSkin = fetchurl {
        #   url = "https://cdn.modrinth.com/data/EsAfCjCV/versions/YxFxnyd4/appleskin-fabric-mc1.21-3.0.2.jar";
        #   sha512 = "9d1259c87e19c6c1edb5d326cde6015b3d37a5da31bd0fb0b747f3c0d2c0b7d58a773f324f4d95c7984b25d7d2d9d783537be69187d54298d39fa2b4c865d682";
        # };

        # Structures
        Explorify = fetchurl {
          url = "https://cdn.modrinth.com/data/HSfsxuTo/versions/FMLZeLnv/Explorify%20v1.5.0%20f10-48.jar";
          sha512 = "f19b97f46b37a69617a1e042c6e00178a89cfd678593ab7c4ccd6a397caafbb21d74a23f45dfdb5b1ab00e4d64d68d1ffc715eb1d153e1cc652224edbd68ac28";
        };

        # Debugify Dependencies
        YetAnotherConfigLib = fetchurl {
          url = "https://cdn.modrinth.com/data/1eAoo2KR/versions/Y8Wa10Re/YetAnotherConfigLib-3.5.0%2B1.21-fabric.jar";
          sha512 = "954bd6b364892afb569973e6beabcd8cce5a22b70747d124e5059b716475a82344ccf586b1ba38ab0b21e6d42485894f398b22285c81f1fff619f9b709a9fe3e";
        };
        ModMenu = fetchurl {
          url = "https://cdn.modrinth.com/data/mOgUt4GM/versions/lJ1xXMce/modmenu-11.0.0.jar";
          sha512 = "c8613d518304accf94fc83f5b6c35baf561ac1cf725f466a6c8f58e57e4143a3799a5e871c4fb69c7cf0b543f450d17b22ca59521a4df8319ecd53bd56458ec4";
        };
      }
    );
  };
}
