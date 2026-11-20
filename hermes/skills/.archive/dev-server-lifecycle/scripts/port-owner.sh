#!/usr/bin/env bash
# Report which processes own listening TCP ports, whether each is supervised, and
# which ones match a dev-server command. Run BEFORE starting or killing a server.
#
#   ./port-owner.sh            # all listeners
#   ./port-owner.sh 8000       # one port, with extra detail
#
# A listener that was not started by you is the user's. Do not clear its port.

set -uo pipefail

ports=("$@")
hr() { printf '%s\n' "------------------------------------------------------------"; }

printf '\n== listening TCP sockets ==\n'
if ! command -v ss >/dev/null 2>&1; then
    echo "ss unavailable; falling back to netstat"
    netstat -ltnp 2>/dev/null || echo "no socket listing possible"
    exit 0
fi

ss -ltnpH 2>/dev/null | awk '
{
    split($4, a, ":"); port = a[length(a)];
    proc = "?"; pid = "?";
    if (match($0, /users:\(\("[^"]+",pid=[0-9]+/)) {
        s = substr($0, RSTART, RLENGTH);
        if (match(s, /pid=[0-9]+/)) pid = substr(s, RSTART + 4, RLENGTH - 4);
        if (match(s, /\("[^"]+"/)) proc = substr(s, RSTART + 2, RLENGTH - 3);
    }
    printf "%-8s %-22s pid=%-8s %s\n", port, proc, pid, $6
}' | sort -k1,1V

printf '\n== dev-server-ish processes ==\n'
pgrep -af 'artisan serve|next dev|next start|vite preview|rails s|uvicorn|gunicorn|manage.py runserver|http.server|php -S|node .*server' \
    || echo "none matched"

printf '\n== supervised units (systemd --user) ==\n'
if command -v systemctl >/dev/null 2>&1; then
    systemctl --user list-units --type=service --state=running --no-pager --no-legend 2>/dev/null \
        | grep -Ei 'serve|web|app|php|node|laravel|next' \
        || echo "no matching user units running"
else
    echo "systemctl unavailable"
fi

for port in "${ports[@]}"; do
    hr
    printf '== detail for port %s ==\n' "$port"
    if ss -ltn "sport = :$port" 2>/dev/null | grep -q LISTEN; then
        ss -ltnp "sport = :$port" 2>/dev/null
        pids=$(ss -ltnpH "sport = :$port" 2>/dev/null | grep -oP 'pid=\K[0-9]+' | sort -u)
        for pid in $pids; do
            printf '  started: %s\n' "$(ps -o lstart= -p "$pid" 2>/dev/null | sed 's/^ *//')"
        done
        echo "  -> LISTENING: verify whether you started it before clearing this port."
    else
        echo "  free - safe to bind."
    fi
done
[ "${#ports[@]}" -gt 0 ] && hr
exit 0