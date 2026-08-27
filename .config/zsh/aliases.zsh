alias ls="eza --icons=always"
alias tree="eza --tree --icons=always"

compdef eza=ls

if command -v bat >/dev/null 2>&1; then
  alias cat="bat"
elif command -v batcat >/dev/null 2>&1; then
  alias bat="batcat"
  alias cat="batcat"
fi

if command -v fdfind >/dev/null 2>&1; then
  alias fd="fdfind"
fi

alias grep="rg --color=auto"
alias diff="diff --color=auto"
alias df="df -h"

alias -- -='cd -'

# nvim aliases
alias vim="nvim"
alias vgit='vim +Git +only'
