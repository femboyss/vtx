# fish completion for vtx - (c) 2026 34 & Claude
set -l cmds -S -Syu -Ss -Si -R -Rs install remove search info update components fix profile repo doctor lang clean help
complete -c vtx -f
complete -c vtx -n "not __fish_seen_subcommand_from $cmds" -a "$cmds"
complete -c vtx -n "__fish_seen_subcommand_from profile" -a "linux windows mac"
complete -c vtx -n "__fish_seen_subcommand_from repo" -a "add remove status"
complete -c vtx -n "__fish_seen_subcommand_from lang" -a "auto en de"
complete -c vtx -n "__fish_seen_subcommand_from fix components" -a "(pacman -Slq vitra 2>/dev/null)"
complete -c vtx -n "__fish_seen_subcommand_from -S install" -a "(pacman -Slq 2>/dev/null)"
complete -c vtx -n "__fish_seen_subcommand_from -R -Rs remove" -a "(pacman -Qq 2>/dev/null)"
