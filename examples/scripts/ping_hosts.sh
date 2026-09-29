#!/usr/bin/env bash
# Example script used by commands/ping_hosts.json.
# Usage: ping_hosts.sh [--hosts host1,host2] [--count N]
set -uo pipefail

HOSTS="1.1.1.1,example.com"
COUNT=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --hosts) HOSTS="$2"; shift 2 ;;
    --hosts=*) HOSTS="${1#*=}"; shift ;;
    --count) COUNT="$2"; shift 2 ;;
    --count=*) COUNT="${1#*=}"; shift ;;
    -h|--help)
      echo "Usage: ping_hosts.sh [--hosts host1,host2] [--count N]"
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

failed=0
IFS=',' read -r -a host_list <<< "$HOSTS"
for host in "${host_list[@]}"; do
  if ping -c "$COUNT" -t 3 "$host" >/dev/null 2>&1; then
    printf "  OK    %s\n" "$host"
  else
    printf "  FAIL  %s\n" "$host"
    failed=$((failed + 1))
  fi
done

exit "$failed"
