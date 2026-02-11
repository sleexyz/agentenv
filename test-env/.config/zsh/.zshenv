# Portable .zshenv — standalone, no home-manager
# Sourced for all zsh invocations (interactive and non-interactive)

export EDITOR=nvim
export VISUAL=nvim
export PAGER=less
export LANG=en_US.UTF-8

# ZDOTDIR tells zsh where to find .zshrc
export ZDOTDIR="${ZDOTDIR:-$HOME/.config/zsh}"
