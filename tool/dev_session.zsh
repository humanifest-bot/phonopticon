#!/bin/zsh -f
# iTerm invokes this with /bin/zsh; it need not be executable.
umask 077
cd /Users/legion/dev/humanifest/phonopticon || exit 2
while true; do
  print '\nPhonopticon — local — Legion Mac — all servers'
  print 'Starting the existing built web preview only. No build, downloads or audio.'
  /opt/homebrew/bin/python3 -B tool/dev_server.py serve &
  server_pid=$!
  trap 'kill -INT "$server_pid" 2>/dev/null' INT
  trap 'kill -TERM "$server_pid" 2>/dev/null; wait "$server_pid" 2>/dev/null; print "STOPPED — Phonopticon / local / Legion Mac / exit=143 (session terminated)"; exit 143' HUP TERM
  # Python launched asynchronously may inherit SIGINT ignored; restore in Python
  # (see dev_server.main) so Ctrl-C can stop it while the pane remains visible.
  wait "$server_pid"
  result=$?
  if kill -0 "$server_pid" 2>/dev/null; then
    wait "$server_pid"
    result=$?
  fi
  trap - INT HUP TERM
  print "\nSTOPPED — Phonopticon / local / Legion Mac / exit=$result"
  print 'Logs remain above. Enter r to restart, s for readiness, or q to close.'
  while true; do
    read -r 'choice?> '
    case "$choice" in
      r) break ;;
      s) /opt/homebrew/bin/python3 -B tool/dev_server.py status ;;
      q|'') exit "$result" ;;
      *) print 'Use r, s, or q.' ;;
    esac
  done
done
