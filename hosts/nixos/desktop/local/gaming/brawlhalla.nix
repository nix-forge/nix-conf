{ pkgs, ... }: {
  # AIR stores these preferences in binary AMF3 shared objects beside account
  # state. Export only the desired fields; never replace the whole save file.
  # See docs/research/brawlhalla-research.md for application and verification limits.
  environment.etc."brawlhalla/settings.json".source =
    (pkgs.formats.json { }).generate "brawlhalla-settings.json"
      {
        steamLaunchOptions = "-setfps 240";
        wootingProfile = "FPS";
        keyboard = {
          left1 = 65;
          right1 = 68;
          down1 = 83;
          up1 = 255;
          upnotjump1 = 87;
          newjump1 = 32;
          light1 = 74;
          heavy1 = 75;
          throw1 = 76;
          dodge1 = 16;
          score1 = 9;
          slash1 = 191;
          left2 = 255;
          right2 = 255;
          down2 = 255;
          up2 = 255;
          upnotjump2 = 255;
          newjump2 = 255;
          light2 = 255;
          heavy2 = 255;
          throw2 = 255;
          dodge2 = 255;
          score2 = 255;
          slash2 = 255;
          lightattackonly = true;
          treatupasjump = true;
        };
        preferences = {
          bhWindowMode = 0; # Fullscreen.
          bhCameraMode = 0; # Default camera.
          bhHUDNamesMode = 1; # HUD only.
          bhHUDIconsMode = 1; # All team icons.
          bhHUDSizeMode = 0;
          bhAccessibilityMode = 3; # Medium background blur.
          bhQueueTrainingMode = true;
          bhSoundVolumeInverted = 0.3; # 70% effects.
          bhMusicVolumeInverted = 1.0; # Muted music.
          bhShowDamageNumbers = false;
          bhShowStockTimer = false; # Show timer at one minute.
          bhCombatBroadcastMode = 0;
        };
      };
}
