#!/bin/sh
set -eu

VERSION="${NPC_VERSION:-0.26.10}"
RELEASE_BASE="${NPC_RELEASE_BASE:-https://dl.runsh.de/npc}"
DEFAULT_SERVER="${NPC_DEFAULT_SERVER:-23.141.12.66:8024}"
TIMEOUT="${NPC_TIMEOUT:-0}"
SSH_PORT="${NPC_SSH_PORT:-22}"
REPLACE_EXISTING="${NPC_REPLACE_EXISTING:-1}"
AUTOSTART="${NPC_AUTOSTART:-1}"

say() { printf '%s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

case "$TIMEOUT" in
  ''|*[!0-9]*) die "NPC_TIMEOUT must be a whole number of seconds (0 means no timeout)." ;;
esac

case "$SSH_PORT" in
  ''|*[!0-9]*) die "NPC_SSH_PORT must be a port number from 1 to 65535." ;;
esac

case "$REPLACE_EXISTING" in
  0|1) ;;
  *) die "NPC_REPLACE_EXISTING must be 0 or 1." ;;
esac

case "$AUTOSTART" in
  0|1) ;;
  *) die "NPC_AUTOSTART must be 0 or 1." ;;
esac

[ "$SSH_PORT" -ge 1 ] 2>/dev/null && [ "$SSH_PORT" -le 65535 ] 2>/dev/null || \
  die "NPC_SSH_PORT must be a port number from 1 to 65535."

OS="$(uname -s 2>/dev/null || echo unknown)"
ARCH="$(uname -m 2>/dev/null || echo unknown)"

case "$OS" in
  Linux)
    case "$ARCH" in
      x86_64|amd64)            PKG="linux_amd64_client.tar.gz" ;;
      i386|i486|i586|i686|x86) PKG="linux_386_client.tar.gz" ;;
      aarch64|arm64)           PKG="linux_arm64_client.tar.gz" ;;
      armv7l|armv7*)           PKG="linux_arm_v7_client.tar.gz" ;;
      armv6l|armv6*)           PKG="linux_arm_v6_client.tar.gz" ;;
      armv5l|armv5*)           PKG="linux_arm_v5_client.tar.gz" ;;
      mips64el|mips64le)       PKG="linux_mips64le_client.tar.gz" ;;
      mips64)                  PKG="linux_mips64_client.tar.gz" ;;
      mipsel|mipsle)           PKG="linux_mipsle_client.tar.gz" ;;
      mips)                    PKG="linux_mips_client.tar.gz" ;;
      *) die "Unsupported Linux architecture: $ARCH" ;;
    esac
    ;;
  Darwin)
    case "$ARCH" in
      x86_64|amd64)
        PKG="darwin_amd64_client.tar.gz"
        ;;
      arm64|aarch64)
        if ! /usr/bin/arch -x86_64 /usr/bin/true >/dev/null 2>&1; then
          die "Apple Silicon requires Rosetta 2 for NPS v$VERSION. Install it with: softwareupdate --install-rosetta --agree-to-license"
        fi
        say "[NPC] Apple Silicon detected; the Intel NPC binary will run through Rosetta 2."
        PKG="darwin_amd64_client.tar.gz"
        ;;
      *) die "Unsupported macOS architecture: $ARCH" ;;
    esac

    if command -v nc >/dev/null 2>&1 &&
       ! nc -z 127.0.0.1 "$SSH_PORT" >/dev/null 2>&1 &&
       ! nc -z ::1 "$SSH_PORT" >/dev/null 2>&1; then
      die "No SSH server is listening on local port $SSH_PORT. Enable System Settings > General > Sharing > Remote Login, or set NPC_SSH_PORT to the actual SSH port."
    fi
    ;;
  *) die "This installer supports Linux/NAS and macOS. Detected OS: $OS" ;;
esac

IS_ROOT=0
[ "$(id -u 2>/dev/null || echo 1)" = "0" ] && IS_ROOT=1

TMP_BASE="${TMPDIR:-/tmp}"
TMP_DIR="$TMP_BASE/npc-install-$$"
ARCHIVE="$TMP_DIR/$PKG"
URL="$RELEASE_BASE/v$VERSION/$PKG"

cleanup() { rm -rf "$TMP_DIR" 2>/dev/null || true; }
trap cleanup EXIT INT TERM
mkdir -p "$TMP_DIR"

say "[NPC] OS: $OS"
say "[NPC] Architecture: $ARCH"
say "[NPC] Package: $PKG"
say "[NPC] Version: $VERSION"
say "[NPC] Download: $URL"
say "[NPC] Local SSH target port: $SSH_PORT"

if command -v curl >/dev/null 2>&1; then
  if ! curl -kfsSL --retry 2 --connect-timeout 15 -o "$ARCHIVE" "$URL"; then
    if [ "$OS" = "Darwin" ] && [ -z "${NPC_RELEASE_BASE:-}" ]; then
      URL="https://github.com/ehang-io/nps/releases/download/v$VERSION/$PKG"
      say "[NPC] Package is unavailable from the mirror; falling back to: $URL"
      curl -fsSL --retry 2 --connect-timeout 15 -o "$ARCHIVE" "$URL"
    else
      die "Failed to download $URL"
    fi
  fi
elif command -v wget >/dev/null 2>&1; then
  if ! wget --no-check-certificate -O "$ARCHIVE" "$URL"; then
    if [ "$OS" = "Darwin" ] && [ -z "${NPC_RELEASE_BASE:-}" ]; then
      URL="https://github.com/ehang-io/nps/releases/download/v$VERSION/$PKG"
      say "[NPC] Package is unavailable from the mirror; falling back to: $URL"
      wget -O "$ARCHIVE" "$URL"
    else
      die "Failed to download $URL"
    fi
  fi
else
  die "curl or wget is required"
fi

command -v tar >/dev/null 2>&1 || die "tar is required"
tar -xzf "$ARCHIVE" -C "$TMP_DIR"
[ -f "$TMP_DIR/npc" ] || die "npc binary was not found after extraction"

INSTALL_DIR=""
if [ -n "${NPC_INSTALL_DIR:-}" ]; then
  CANDIDATES="$NPC_INSTALL_DIR"
elif [ "$IS_ROOT" = "1" ]; then
  CANDIDATES="/usr/local/npc /opt/npc $HOME/npc"
else
  CANDIDATES="$HOME/.local/npc $HOME/npc"
fi

for dir in $CANDIDATES; do
  STAGED_NPC="$dir/.npc-install-$$"
  if mkdir -p "$dir" 2>/dev/null && cp "$TMP_DIR/npc" "$STAGED_NPC" 2>/dev/null && chmod 755 "$STAGED_NPC" 2>/dev/null; then
    if "$STAGED_NPC" -version >/dev/null 2>&1 && mv -f "$STAGED_NPC" "$dir/npc" 2>/dev/null; then
      INSTALL_DIR="$dir"
      break
    fi
  fi
  rm -f "$STAGED_NPC" 2>/dev/null || true
done

[ -n "$INSTALL_DIR" ] || die "Could not find a writable and executable install directory. Set NPC_INSTALL_DIR to a persistent executable path."

NPC_BIN="$INSTALL_DIR/npc"
LOG_FILE="$INSTALL_DIR/npc.log"

say "[NPC] Installed successfully: $NPC_BIN"
"$NPC_BIN" -version

if [ "$IS_ROOT" = "1" ] && [ -d /usr/local/bin ] && [ -w /usr/local/bin ]; then
  ln -sf "$NPC_BIN" /usr/local/bin/npc 2>/dev/null || true
fi

SERVER="${NPC_SERVER:-}"
VKEY="${NPC_VKEY:-}"
TYPE="${NPC_TYPE:-tcp}"

if [ -z "$SERVER" ]; then
  if [ -t 0 ]; then
    printf '\nNPS server [%s]: ' "$DEFAULT_SERVER"
    read -r SERVER_INPUT || true
    SERVER="${SERVER_INPUT:-$DEFAULT_SERVER}"
  else
    SERVER="$DEFAULT_SERVER"
  fi
fi

if [ -z "$VKEY" ]; then
  if [ -t 0 ]; then
    printf 'VKey: '
    if command -v stty >/dev/null 2>&1; then
      stty -echo 2>/dev/null || true
      read -r VKEY || true
      stty echo 2>/dev/null || true
      printf '\n'
    else
      read -r VKEY || true
    fi
  fi
fi

if [ -z "$VKEY" ]; then
  cat <<EOF2

[NPC] Installation finished. VKey was not supplied, so NPC was not started.
Run manually:
  $NPC_BIN -server=$SERVER -vkey=YOUR_VKEY -type=$TYPE

Or install/start non-interactively:
  NPC_SERVER='$SERVER' NPC_VKEY='YOUR_VKEY' sh -c "\$(curl -kfsSL https://dl.runsh.de/npc/install.sh)"
EOF2
  exit 0
fi

CARRIAGE_RETURN=$(printf '\r')
case "$SERVER$VKEY$TYPE" in
  *"$CARRIAGE_RETURN"*) die "NPC connection values must not contain line breaks." ;;
esac
[ "$(printf '%s' "$SERVER$VKEY$TYPE" | wc -l | tr -d ' ')" = "0" ] || \
  die "NPC connection values must not contain line breaks."

NOW_EPOCH="$(date +%s)"
if [ "$TIMEOUT" -gt 0 ]; then
  EXPIRES_AT=$((NOW_EPOCH + TIMEOUT))
else
  EXPIRES_AT=0
fi

RUNNER="$INSTALL_DIR/npc-startup.sh"
STARTUP_CONFIG="$INSTALL_DIR/npc-startup.conf"

stop_managed_startup() {
  if [ "$OS" = "Linux" ] && [ "$IS_ROOT" = "1" ] && command -v systemctl >/dev/null 2>&1; then
    systemctl stop npc.service >/dev/null 2>&1 || true
  elif [ "$OS" = "Darwin" ] && [ "$IS_ROOT" = "1" ] && command -v launchctl >/dev/null 2>&1; then
    launchctl bootout system/de.runsh.npc >/dev/null 2>&1 || true
  fi
}

install_runner() {
  umask 077
  {
    printf '%s\n' "$NPC_BIN"
    printf '%s\n' "$SERVER"
    printf '%s\n' "$VKEY"
    printf '%s\n' "$TYPE"
    printf '%s\n' "$EXPIRES_AT"
    printf '%s\n' "$LOG_FILE"
  } > "$STARTUP_CONFIG"

  cat > "$RUNNER" <<'EOF_RUNNER'
#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
CONFIG="$SCRIPT_DIR/npc-startup.conf"
[ -r "$CONFIG" ] || exit 1
NPC_BIN=$(sed -n '1p' "$CONFIG")
SERVER=$(sed -n '2p' "$CONFIG")
VKEY=$(sed -n '3p' "$CONFIG")
TYPE=$(sed -n '4p' "$CONFIG")
EXPIRES_AT=$(sed -n '5p' "$CONFIG")
LOG_FILE=$(sed -n '6p' "$CONFIG")
case "$EXPIRES_AT" in ''|*[!0-9]*) exit 1 ;; esac
NOW=$(date +%s)
if [ "$EXPIRES_AT" -gt 0 ] && [ "$NOW" -ge "$EXPIRES_AT" ]; then exit 0; fi

"$NPC_BIN" -server="$SERVER" -vkey="$VKEY" -type="$TYPE" </dev/null >>"$LOG_FILE" 2>&1 &
NPC_PID=$!
TIMER_PID=
cleanup() {
  [ -z "$TIMER_PID" ] || kill "$TIMER_PID" 2>/dev/null || true
  kill "$NPC_PID" 2>/dev/null || true
}
trap cleanup INT TERM EXIT
if [ "$EXPIRES_AT" -gt 0 ]; then
  REMAINING=$((EXPIRES_AT - NOW))
  ( sleep "$REMAINING"; kill "$NPC_PID" 2>/dev/null || exit 0; sleep 5; kill -9 "$NPC_PID" 2>/dev/null || true ) &
  TIMER_PID=$!
fi
set +e
wait "$NPC_PID"
STATUS=$?
set -e
trap - INT TERM EXIT
[ -z "$TIMER_PID" ] || kill "$TIMER_PID" 2>/dev/null || true
NOW=$(date +%s)
if [ "$EXPIRES_AT" -gt 0 ] && [ "$NOW" -ge "$EXPIRES_AT" ]; then exit 0; fi
[ "$STATUS" -ne 0 ] || STATUS=1
exit "$STATUS"
EOF_RUNNER
  chmod 700 "$RUNNER"
}

enable_managed_startup() {
  [ "$AUTOSTART" = "1" ] || return 1
  [ "$IS_ROOT" = "1" ] || return 1
  case "$RUNNER" in *[!A-Za-z0-9_./-]*) return 1 ;; esac
  install_runner

  if [ "$OS" = "Linux" ] && command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
    cat > /etc/systemd/system/npc.service <<EOF_SERVICE
[Unit]
Description=NPS NPC client
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$RUNNER
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF_SERVICE
    chmod 644 /etc/systemd/system/npc.service
    systemctl daemon-reload
    systemctl enable npc.service >/dev/null
    systemctl start npc.service
    sleep 2
    systemctl is-active --quiet npc.service || die "npc.service failed to start. Run: systemctl status npc.service"
    say "[NPC] Started as systemd service and enabled at boot."
    say "[NPC] Service: npc.service"
    return 0
  fi

  if [ "$OS" = "Darwin" ] && command -v launchctl >/dev/null 2>&1; then
    PLIST=/Library/LaunchDaemons/de.runsh.npc.plist
    cat > "$PLIST" <<EOF_PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>de.runsh.npc</string>
<key>ProgramArguments</key><array><string>$RUNNER</string></array>
<key>RunAtLoad</key><true/>
<key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
<key>ProcessType</key><string>Background</string>
</dict></plist>
EOF_PLIST
    chmod 600 "$PLIST"
    launchctl bootstrap system "$PLIST"
    launchctl enable system/de.runsh.npc >/dev/null 2>&1 || true
    launchctl kickstart -k system/de.runsh.npc
    sleep 2
    launchctl print system/de.runsh.npc >/dev/null 2>&1 || die "launchd job failed to load."
    say "[NPC] Started as a launchd daemon and enabled at boot."
    say "[NPC] Service: de.runsh.npc"
    return 0
  fi
  return 1
}

find_npc_pids() {
  if command -v pidof >/dev/null 2>&1; then
    pidof npc 2>/dev/null || true
  elif command -v pgrep >/dev/null 2>&1; then
    pgrep -x npc 2>/dev/null || true
  elif [ -d /proc ]; then
    for proc_dir in /proc/[0-9]*; do
      [ -r "$proc_dir/comm" ] || continue
      IFS= read -r proc_name < "$proc_dir/comm" || true
      [ "$proc_name" = "npc" ] && printf '%s ' "${proc_dir##*/}"
    done
  else
    ps 2>/dev/null | awk '$NF == "npc" || $NF ~ /\/npc$/ { print $1 }'
  fi
}

if [ "$REPLACE_EXISTING" = "1" ]; then stop_managed_startup; fi
OLD_NPC_PIDS="$(find_npc_pids)"
if [ -n "$OLD_NPC_PIDS" ]; then
  if [ "$REPLACE_EXISTING" = "0" ]; then
    say "[NPC] An npc process is already running. Installation completed; no second process was started."
    say "[NPC] Existing PID(s): $OLD_NPC_PIDS"
    say "[NPC] Set NPC_REPLACE_EXISTING=1 to stop the old process and start this connection."
    exit 0
  fi

  say "[NPC] Stopping existing npc process(es): $OLD_NPC_PIDS"
  for old_pid in $OLD_NPC_PIDS; do
    kill "$old_pid" 2>/dev/null || true
  done

  WAITED=0
  while [ "$WAITED" -lt 10 ] && [ -n "$(find_npc_pids)" ]; do
    sleep 1
    WAITED=$((WAITED + 1))
  done

  REMAINING_NPC_PIDS="$(find_npc_pids)"
  if [ -n "$REMAINING_NPC_PIDS" ]; then
    say "[NPC] Existing npc did not stop after 10 seconds; forcing stop: $REMAINING_NPC_PIDS"
    for old_pid in $REMAINING_NPC_PIDS; do
      kill -9 "$old_pid" 2>/dev/null || true
    done
    sleep 1
  fi

  REMAINING_NPC_PIDS="$(find_npc_pids)"
  [ -z "$REMAINING_NPC_PIDS" ] || \
    die "Could not stop existing npc process(es): $REMAINING_NPC_PIDS. Check for a service or watchdog that restarts npc."
  say "[NPC] Existing npc process stopped."
fi

if enable_managed_startup; then
  say "[NPC] Server: $SERVER"
  say "[NPC] Local SSH target: 127.0.0.1:$SSH_PORT"
  say "[NPC] Log: $LOG_FILE"
  if [ "$TIMEOUT" -gt 0 ]; then
    say "[NPC] Absolute expiry: $EXPIRES_AT (Unix time); reboot does not reset it."
  else
    say "[NPC] Automatic stop: disabled"
  fi
  exit 0
fi

if [ "$AUTOSTART" = "1" ]; then
  say "[NPC] Boot startup was not enabled because root and systemd/launchd are required; using background mode."
fi

: > "$LOG_FILE" 2>/dev/null || true

if command -v setsid >/dev/null 2>&1; then
  setsid "$NPC_BIN" -server="$SERVER" -vkey="$VKEY" -type="$TYPE" </dev/null >>"$LOG_FILE" 2>&1 &
  NPC_PID=$!
  DETACH_METHOD="setsid"
elif command -v nohup >/dev/null 2>&1; then
  nohup "$NPC_BIN" -server="$SERVER" -vkey="$VKEY" -type="$TYPE" </dev/null >>"$LOG_FILE" 2>&1 &
  NPC_PID=$!
  DETACH_METHOD="nohup"
elif command -v busybox >/dev/null 2>&1 && busybox nohup true >/dev/null 2>&1; then
  busybox nohup "$NPC_BIN" -server="$SERVER" -vkey="$VKEY" -type="$TYPE" </dev/null >>"$LOG_FILE" 2>&1 &
  NPC_PID=$!
  DETACH_METHOD="busybox nohup"
else
  "$NPC_BIN" -server="$SERVER" -vkey="$VKEY" -type="$TYPE" </dev/null >>"$LOG_FILE" 2>&1 &
  NPC_PID=$!
  DETACH_METHOD="shell background (may stop after logout on some systems)"
fi

sleep 2

if kill -0 "$NPC_PID" 2>/dev/null; then
  say "[NPC] Started successfully in background."
  say "[NPC] PID: $NPC_PID"
  say "[NPC] Server: $SERVER"
  say "[NPC] Local SSH target: 127.0.0.1:$SSH_PORT"
  say "[NPC] Detach: $DETACH_METHOD"
  say "[NPC] Log: $LOG_FILE"

  if [ "$TIMEOUT" -gt 0 ]; then
    WATCHDOG_LOG="$INSTALL_DIR/npc-watchdog.log"
    WATCHDOG_SCRIPT='
pid=$1
seconds=$2
expected=$3
log_file=$4
remaining=$seconds

while [ "$remaining" -gt 0 ]; do
  step=30
  [ "$remaining" -lt "$step" ] && step=$remaining
  sleep "$step"
  kill -0 "$pid" 2>/dev/null || exit 0
  remaining=$((remaining - step))
done

if [ -e "/proc/$pid/exe" ] && command -v readlink >/dev/null 2>&1; then
  current=$(readlink "/proc/$pid/exe" 2>/dev/null || true)
  [ "$current" = "$expected" ] || exit 0
fi

printf "%s [NPC] Session timeout reached; stopping PID %s.\n" "$(date 2>/dev/null || true)" "$pid" >>"$log_file"
kill "$pid" 2>/dev/null || exit 0
sleep 5
kill -9 "$pid" 2>/dev/null || true
'

    if command -v nohup >/dev/null 2>&1; then
      nohup sh -c "$WATCHDOG_SCRIPT" sh "$NPC_PID" "$TIMEOUT" "$NPC_BIN" "$WATCHDOG_LOG" </dev/null >/dev/null 2>&1 &
    elif command -v busybox >/dev/null 2>&1 && busybox nohup true >/dev/null 2>&1; then
      busybox nohup sh -c "$WATCHDOG_SCRIPT" sh "$NPC_PID" "$TIMEOUT" "$NPC_BIN" "$WATCHDOG_LOG" </dev/null >/dev/null 2>&1 &
    else
      sh -c "$WATCHDOG_SCRIPT" sh "$NPC_PID" "$TIMEOUT" "$NPC_BIN" "$WATCHDOG_LOG" </dev/null >/dev/null 2>&1 &
    fi

    say "[NPC] Automatic stop: ${TIMEOUT} seconds"
    say "[NPC] Watchdog log: $WATCHDOG_LOG"
  else
    say "[NPC] Automatic stop: disabled"
  fi

  if command -v tail >/dev/null 2>&1; then
    tail -n 10 "$LOG_FILE" 2>/dev/null || true
  fi
else
  say "[NPC] Process exited shortly after start. Log follows:"
  cat "$LOG_FILE" 2>/dev/null || true
  exit 1
fi
