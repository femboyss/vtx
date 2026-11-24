# bash completion for vtx - (c) 2026 34 & Claude
_vtx() {
    local cur=${COMP_WORDS[COMP_CWORD]} prev=${COMP_WORDS[1]:-}
    if (( COMP_CWORD == 1 )); then
        COMPREPLY=($(compgen -W "-S -Syu -Ss -Si -R -Rs -Q install remove search info update components fix profile repo doctor lang clean help --version" -- "$cur"))
        return
    fi
    case $prev in
        profile)    COMPREPLY=($(compgen -W "linux windows mac" -- "$cur")) ;;
        repo)       COMPREPLY=($(compgen -W "add remove status" -- "$cur")) ;;
        lang)       COMPREPLY=($(compgen -W "auto en de" -- "$cur")) ;;
        components) COMPREPLY=($(compgen -W "list install remove reinstall $(pacman -Slq vitra 2>/dev/null)" -- "$cur")) ;;
        fix)        COMPREPLY=($(compgen -W "$(pacman -Slq vitra 2>/dev/null)" -- "$cur")) ;;
        -R*|remove) COMPREPLY=($(compgen -W "$(pacman -Qq 2>/dev/null)" -- "$cur")) ;;
        -S|install) COMPREPLY=($(compgen -W "$(pacman -Slq 2>/dev/null)" -- "$cur")) ;;
    esac
}
complete -F _vtx vtx
