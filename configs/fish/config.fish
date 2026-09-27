# fish config — the interactive shell inside kitty and Ptyxis; bash stays the
# login shell. Every tool hook is guarded so a missing tool stays silent.

set -g fish_greeting

fish_add_path ~/.local/bin ~/bin

# Homebrew (only if installed; gh, mise, yazi and sops come from it)
if test -x /home/linuxbrew/.linuxbrew/bin/brew; and not set -q HOMEBREW_PREFIX
    eval (/home/linuxbrew/.linuxbrew/bin/brew shellenv fish)
end

set -gx EDITOR nvim
set -gx VISUAL nvim

# eza — modern ls
alias ls='eza --icons --group-directories-first'
alias ll='eza --icons --group-directories-first -lh --git'
alias la='eza --icons --group-directories-first -lha --git'
alias tree='eza --icons --tree'

# bat — syntax-highlighted cat (Ubuntu ships it as batcat; apply-user.sh links ~/.local/bin/bat)
alias cat='bat --pager=never'
set -gx MANPAGER "sh -c 'col -bx | bat -l man -p'"

# color for the classics
alias grep='grep --color=auto'
alias diff='diff --color=auto'

# git
alias gs='git status'
alias gd='git diff'
alias lg='lazygit'
set -gx GIT_PAGER delta

# rootless Podman is the Docker host for docker-compatible tooling (compose,
# testcontainers) unless a real Docker daemon is installed
if test -S /var/run/docker.sock
    # Docker Engine present: `docker` must reach it. A DOCKER_HOST that still
    # points at Podman can be inherited from the session (the profile.d hook of
    # a removed podman-docker) — drop it
    if string match -q '*/podman/podman.sock' -- "$DOCKER_HOST"
        set -e DOCKER_HOST
    end
else if test -S "$XDG_RUNTIME_DIR/podman/podman.sock"
    set -gx DOCKER_HOST "unix://$XDG_RUNTIME_DIR/podman/podman.sock"
end

# yazi — cd into the directory you quit yazi in
function ya
    set tmp (mktemp -t "yazi-cwd.XXXXXX")
    yazi $argv --cwd-file=$tmp
    if set cwd (command cat -- $tmp); and test -n "$cwd"; and test "$cwd" != "$PWD"
        cd -- $cwd
    end
    rm -f -- $tmp
end

command -q mise; and mise activate fish | source
command -q direnv; and direnv hook fish | source
command -q zoxide; and zoxide init fish | source
command -q fzf; and fzf --fish | source
command -q starship; and starship init fish | source
