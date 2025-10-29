echo "This will delete ALL local files and convert this machine to a NixTV!";
read -p "Do you want to continue? (y/n): " answer

if [[ "$answer" =~ ^[Yy]$ ]]; then
  echo "Installing NixTV..."

  # Set up local files
  rm -rf ~/
  mkdir ~/Desktop
  mkdir ~/Documents
  mkdir ~/Downloads
  mkdir ~/Pictures
  mkdir ~/.local
  mkdir ~/.local/share
  cp -R /etc/nixtv/config/config ~/.config
  cp -R /etc/nixtv/config/applications ~/.local/share/applications

  # The rest of the install should be hands off
  # Add Nixbook config and rebuild
  sudo sed -i '/hardware-configuration\.nix/a\      /etc/nixtv/base.nix' /etc/nixos/configuration.nix
  
  # Set up flathub repo while we have sudo
  nix-shell -p flatpak --run 'sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo'

  sudo nixos-rebuild switch

  # Add flathub and some apps
  flatpak install flathub org.mozilla.firefox -y
  flatpak install flathub io.github.ungoogled_software.ungoogled_chromium -y
  flatpak install flathub dev.heppen.webapps  -y
  flatpak install flathub de.k_bo.Televido -y
  flatpak install flathub cafe.avery.Delfin -y
  flatpak install flathub rocks.shy.VacuumTube -y
  
  reboot
else
  echo "Nixbook Install Cancelled!"
fi
