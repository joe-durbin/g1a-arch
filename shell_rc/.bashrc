#
# ~/.bashrc
#

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

alias grep='grep --color=auto'
PS1='[\u@\h \W]\$ '

export VISUAL="nvim"
export EDITOR="nvim"

alias ff='fastfetch'
alias p='~/.config/my_scripts/pkg-manager.sh p'
alias y='~/.config/my_scripts/pkg-manager.sh y'
alias r='~/.config/my_scripts/pkg-manager.sh r'
alias pkg-sync='~/.config/my_scripts/pkg-manager.sh sync'
alias wp-pick='~/.config/my_scripts/wallpaper-pick.sh'
alias wp-set='~/.config/my_scripts/wallpaper-set.sh'
alias nf='~/.config/my_scripts/nerdpick.sh'

alias clip='wl-copy'

# Flatpak stuff
# alias discord='flatpak run com.discordapp.Discord --no-sandbox --enable-features=UseOzonePlatform --ozone-platform=wayland'

alias ..='cd ..'
alias waybar-reload='pkill -USR2 waybar'
alias vi='nvim'
alias vim='nvim'
alias nano='nvim'
alias ls='eza -l --icons --group-directories-first'
alias cat='bat -p'

alias k='kubectl'

#eval "$(navi widget bash)"
#eval "$(atuin init bash)"

export CARAPACE_LENIENT=1
export CARAPACE_MATCH=1
#source <(carapace _carapace bash)

eval "$(starship init bash)"
