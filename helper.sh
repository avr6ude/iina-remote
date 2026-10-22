#!/bin/sh
# Detaches immediately: IINA never resolves a utils.exec while another one is still running.

iina=$PPID
/bin/mkdir -p "$4"
(
    /usr/bin/dns-sd -R "" _iina-remote._tcp local "$1" &
    advert=$!
    /usr/bin/perl "$3/serve.pl" "$2" "$3" "$4" &
    server=$!
    while kill -0 "$iina" 2>/dev/null; do sleep 2; done
    kill "$advert" "$server"
) >/dev/null 2>&1 &
