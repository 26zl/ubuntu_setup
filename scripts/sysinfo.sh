#!/usr/bin/env bash
# Quick system health glance (alias: sysinfo). Read-only. Prints no IP addresses,
# so the output is safe in a screenshot.
set -uo pipefail

TEAL='\033[38;2;136;192;208m'
RED='\033[38;2;191;97;106m'
RESET='\033[0m'
section() { echo -e "\n${TEAL}━━━ $1 ━━━${RESET}"; }
warn()    { echo -e "  ${RED}!${RESET} $1"; }

section "System"
echo "  $(hostnamectl --static 2>/dev/null)  ·  $(. /etc/os-release && echo "$PRETTY_NAME")  ·  $(uname -r)"
echo "  up $(uptime -p | sed 's/^up //')  ·  load $(cut -d' ' -f1-3 /proc/loadavg)"
[ -f /var/run/reboot-required ] && warn "reboot required (kernel or core library update)"

section "CPU"
grep -m1 'model name' /proc/cpuinfo | cut -d: -f2- | sed 's/^ */  /'
if command -v sensors >/dev/null; then
    t=$(sensors 2>/dev/null | awk '/Package id 0|Tctl|CPU/ {for(i=1;i<=NF;i++) if ($i ~ /^\+[0-9.]+°C/) {print $i; exit}}')
    [ -n "$t" ] && echo "  temperature $t"
fi
echo "  profile     $(powerprofilesctl get 2>/dev/null || echo n/a)"

section "Memory and disk"
free -h | awk 'NR==2 {printf "  RAM  %s used of %s (%s available)\n", $3, $2, $7} NR==3 {printf "  swap %s used of %s\n", $3, $2}'
df -h / /boot /boot/efi 2>/dev/null | awk 'NR>1 {u=$5+0; printf "  %-10s %s used of %s (%s)%s\n", $6, $3, $2, $5, (u>85 ? "  <-- over 85%" : "")}'
if command -v nvme >/dev/null; then
    for dev in /dev/nvme[0-9]n1; do
        [ -e "$dev" ] || continue
        wear=$(sudo -n nvme smart-log "$dev" 2>/dev/null | awk -F: '/percentage_used/ {gsub(/ /,"",$2); print $2}')
        [ -n "$wear" ] && echo "  $dev wear $wear"
    done
fi

section "Battery"
if [ -d /sys/class/power_supply/BAT0 ]; then
    b=/sys/class/power_supply/BAT0
    echo "  $(cat $b/capacity)% ($(cat $b/status))  ·  charge thresholds $(cat $b/charge_control_start_threshold 2>/dev/null || echo '?')–$(cat $b/charge_control_end_threshold 2>/dev/null || echo '?')%"
    full=$(cat $b/energy_full 2>/dev/null); design=$(cat $b/energy_full_design 2>/dev/null)
    [ -n "$full" ] && [ -n "$design" ] && echo "  health $((full * 100 / design))% of design capacity"
fi

section "Network"
nmcli -t -f DEVICE,TYPE,STATE,CONNECTION device status 2>/dev/null | awk -F: '$3=="connected" && $2!="loopback" {printf "  %-12s %-9s %s\n", $1, $2, $4}'
resolvectl status 2>/dev/null | awk '/Protocols/ && !done {print "  " $0; done=1}'
command -v mullvad >/dev/null && echo "  mullvad     $(mullvad status 2>/dev/null | head -1)"
command -v tailscale >/dev/null && echo "  tailscale   $(tailscale status --peers=false 2>/dev/null | head -1 | awk '{print $2, $3, $4}')"
echo "  firewall    $(systemctl is-active ufw 2>/dev/null)"

section "Top processes"
ps -eo pcpu,pmem,comm --sort=-pcpu | head -6 | awk 'NR==1 {print "  " $0} NR>1 {printf "  %5s %5s  %s\n", $1, $2, $3}'

section "Services"
failed=$(systemctl --failed --no-legend 2>/dev/null | wc -l)
[ "$failed" -eq 0 ] && echo "  0 failed units" || { warn "$failed failed units:"; systemctl --failed --no-legend | sed 's/^/    /'; }
