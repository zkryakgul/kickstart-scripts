#!/bin/bash

LIBRARY_PATH="../../lib/"

cd "$(dirname "$0")"
# source all necessary files
for f in $LIBRARY_PATH*; do
 . $f
done

PLUGINS="git zsh-syntax-highlighting zsh-autosuggestions"
THEME="powerlevel10k/powerlevel10k"

warn "Warning:"
echo -ne "\nYou need to install the Meslo Nerd Font for the best usage. You can install it with the following instructions: \n"
echo -ne "\nhttps://github.com/romkatv/powerlevel10k#meslo-nerd-font-patched-for-powerlevel10khttps://github.com/romkatv/powerlevel10k#meslo-nerd-font-patched-for-powerlevel10k\n\n\n"

# Update
sudo apt-get update

# Install dependencies
sudo apt-get install -y zsh curl git fonts-font-awesome

warn "Please type \"exit\" when the following command put you into the zsh. Otherwise installation process can't be continue!"
read -p "Press any key to continue.. " -n 1 -r
# Install oh-my-zsh

sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

# Auto-suggestions plugin
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions

# Syntax higlighting plugin
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting

# Powerlevel10k theme
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k

# Apply the new plugins on .zshrc
sed -i "/plugins=/c\plugins=($PLUGINS)" ~/.zshrc
sed -i "/ZSH_THEME=/c\ZSH_THEME=\"$THEME\"" ~/.zshrc
