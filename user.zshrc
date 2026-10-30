cat >> ~/.zshrc <<'EOF'

alias dir='ls -aFhl --color'
alias edit='/bin/nano -w'

export EDITOR="/bin/nano"

PROMPT='%B%F{green}[%D{%Y-%m-%d_%H:%M:%S}]%F{magenta}[%n@%m:%~]$%f%b '

EOF
