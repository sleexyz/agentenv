# Portable .zshrc — standalone, no home-manager
# Sourced inside agentenv containers

# Prompt (simple, no prezto dependency)
autoload -Uz promptinit && promptinit
setopt PROMPT_SUBST
PROMPT='%F{blue}%~%f %F{green}❯%f '

# History
HISTFILE="${ZDOTDIR:-$HOME}/.zsh_history"
HISTSIZE=10000
SAVEHIST=10000
setopt SHARE_HISTORY HIST_IGNORE_DUPS HIST_IGNORE_SPACE

# Options
unsetopt correct
setopt AUTO_CD INTERACTIVE_COMMENTS

# Completion
autoload -Uz compinit && compinit
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'

# Aliases
alias ls='eza'
alias vim='nvim'

# Zoxide
if command -v zoxide >/dev/null 2>&1; then
  eval "$(zoxide init zsh)"
fi

# fzf
if command -v fzf >/dev/null 2>&1; then
  source <(fzf --zsh 2>/dev/null) || true
fi
