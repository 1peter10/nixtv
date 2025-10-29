{ config, lib, pkgs, ... }:
let
  nixChannel = "https://nixos.org/channels/nixos-unstable"; 

  ## Notify Users Script
  notifyUsersScript = pkgs.writeScript "notify-users.sh" ''
    set -eu

    title="$1"
    body="$2"

    users=$(${pkgs.systemd}/bin/loginctl list-sessions --no-legend | ${pkgs.gawk}/bin/awk '{print $1}' | while read session; do
      loginctl show-session "$session" -p Name | cut -d'=' -f2
    done | sort -u)

    for user in $users; do
      [ -n "$user" ] || continue
      uid=$(id -u "$user") || continue
      [ -S "/run/user/$uid/bus" ] || continue

      # Send notification
      ${pkgs.sudo}/bin/sudo -u "$user" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
        ${pkgs.libnotify}/bin/notify-send "$title" "$body" || true

      # Fix for gnome software nagging user
      ${pkgs.sudo}/bin/sudo -u "$user" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
        ${pkgs.dconf}/bin/dconf write /org/gnome/software/flatpak-updates false || true

    done

  '';

  ## Update Git and Channel Script
  updateGitScript = pkgs.writeScript "update-git.sh" ''
    set -eu
    
    # Update nixtv configs
    ${pkgs.git}/bin/git -C /etc/nixtv reset --hard
    ${pkgs.git}/bin/git -C /etc/nixtv clean -fd
    ${pkgs.git}/bin/git -C /etc/nixtv pull --rebase

    currentChannel=$(${pkgs.nix}/bin/nix-channel --list | ${pkgs.gnugrep}/bin/grep '^nixos' | ${pkgs.gawk}/bin/awk '{print $2}')
    targetChannel="${nixChannel}"

    if [ "$currentChannel" != "$targetChannel" ]; then
      ${pkgs.nix}/bin/nix-channel --add "$targetChannel" nixos
      ${pkgs.nix}/bin/nix-channel --update
    fi
  '';

  ## Install Flatpak Apps Script
  installFlatpakAppsScript = pkgs.writeScript "install-flatpak-apps.sh" ''
    set -eu

    if ${pkgs.flatpak}/bin/flatpak list --app | ${pkgs.gnugrep}/bin/grep -q "org.mozilla.firefox"; then
      echo "Flatpaks already installed"
    else


      # Install Flatpak applications
      ${notifyUsersScript} "Installing Firefox" "Please wait while we install Mozilla Firefox..."
      ${pkgs.flatpak}/bin/flatpak install flathub org.mozilla.firefox -y

      ${notifyUsersScript} "Installing Ungoogled Chromium" "Please wait while we install Ungoogled Chromium..."
      ${pkgs.flatpak}/bin/flatpak install flathub io.github.ungoogled_software.ungoogled_chromium -y
      
      ${notifyUsersScript} "Installing Quick Web Apps" "Please wait while we install Quick Web Apps ..."
      ${pkgs.flatpak}/bin/flatpak install flathub dev.heppen.webapps  -y

      ${notifyUsersScript} "Installing Televido" "Please wait while we install Televido..."
      ${pkgs.flatpak}/bin/flatpak install flathub de.k_bo.Televido -y

      ${notifyUsersScript} "Installing Delfin" "Please wait while we install Delfin..."
      ${pkgs.flatpak}/bin/flatpak install flathub cafe.avery.Delfin -y

      ${notifyUsersScript} "Installing Vacuum Tube" "Please wait while we install Vaccum Tube..."
      ${pkgs.flatpak}/bin/flatpak install flathub rocks.shy.VacuumTube -y

      users=$(${pkgs.systemd}/bin/loginctl list-sessions --no-legend | ${pkgs.gawk}/bin/awk '{print $1}' | while read session; do
        loginctl show-session "$session" -p Name | cut -d'=' -f2
      done | sort -u)

      for user in $users; do
        [ -n "$user" ] || continue
        uid=$(id -u "$user") || continue
        [ -S "/run/user/$uid/bus" ] || continue

        cp /etc/nixtv/config/flatpak_links/* /home/$user/Desktop/
        chown $user /home/$user/Desktop/*
      
        ${notifyUsersScript} "Installing Applications Complete" "Please Log out or restart to start using NixTV and it's applications!"
      done
    fi

  '';
in
{
  zramSwap.enable = true;

  # Enable the X11 windowing system.
  nixpkgs.config.allowUnfree = true;
  hardware.bluetooth.enable = true;


  # GNOME
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;

  # To disable installing GNOME's suite of applications
  # and only be left with GNOME shell.
  services.gnome.core-apps.enable = false;
  services.gnome.core-developer-tools.enable = false;
  services.gnome.games.enable = false;
  environment.gnome.excludePackages = with pkgs; [ gnome-tour gnome-user-docs ];

  services.input-remapper.enable = true;
  services.gvfs.enable = true;
  xdg.portal.enable = true;

  # Enable Printing
  services.printing.enable = true;
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
  };

  environment.systemPackages = with pkgs; [
    git
    libnotify
    gawk
    gnugrep
    neovim
    ripgrep
    sudo
    dconf
    adwaita-fonts
    gnome-calculator
    gnome-calendar
    gnome-console
    nautilus
    flatpak
    xdg-desktop-portal
    xdg-desktop-portal-gtk
    xdg-desktop-portal-gnome
    system-config-printer
  ];

  services.flatpak.enable = true;

  # Install Flatpak Applications Service
  systemd.services."install-flatpak-apps" = {
    script = ''
      set -eu
      ${installFlatpakAppsScript}
    '';
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      Restart = "on-failure";
      RestartSec = "30s";
    };

    after = [ "network-online.target" "flatpak-system-helper.service" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
  };

  nix.gc = {
    automatic = true;
    dates = "Mon 3:40";
    options = "--delete-older-than 14d";
  };
  
  # Auto update config, flatpak and channel
  systemd.timers."auto-update-config" = {
  wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Tue..Sun";
      Persistent = true;
      Unit = "auto-update-config.service";
    };
  };

  systemd.services."auto-update-config" = {
    script = ''
      set -eu

      ${updateGitScript}

      # Flatpak Updates
      ${pkgs.flatpak}/bin/flatpak update --noninteractive --assumeyes
    '';
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      Restart = "on-failure";
      RestartSec = "30s";
      CPUWeight = "20";
      IOWeight = "20";
    };

    after = [ "network-online.target" "graphical.target" ];
    wants = [ "network-online.target" ];
  };

  # Auto Upgrade NixOS
  systemd.timers."auto-upgrade" = {
  wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Mon";
      Persistent = true;
      Unit = "auto-upgrade.service";
    };
  };

  systemd.services."auto-upgrade" = {
    script = ''
      set -eu
      export PATH=${pkgs.nixos-rebuild}/bin:${pkgs.nix}/bin:${pkgs.systemd}/bin:${pkgs.util-linux}/bin:${pkgs.coreutils-full}/bin:$PATH
      export NIX_PATH="nixpkgs=/nix/var/nix/profiles/per-user/root/channels/nixos nixos-config=/etc/nixos/configuration.nix"

      ${updateGitScript}

      ${notifyUsersScript} "Starting System Updates" "System updates are installing in the background.  You can continue to use your computer while these are running."
            
      ${pkgs.nixos-rebuild}/bin/nixos-rebuild boot --upgrade

      ${notifyUsersScript} "System Updates Complete" "Updates are complete!  Simply reboot the computer whenever is convenient to apply updates."
    '';
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      Restart = "on-failure";
      RestartSec = "30s";
      CPUWeight = "20";
      IOWeight = "20";
    };

    after = [ "network-online.target" "graphical.target" ];
    wants = [ "network-online.target" ];
  };

  # Fix for the pesky "insecure" broadcom
  nixpkgs.config.allowInsecurePredicate = pkg:
    builtins.elem (lib.getName pkg) [
    "broadcom-sta" # aka “wl”
  ];
  
}

