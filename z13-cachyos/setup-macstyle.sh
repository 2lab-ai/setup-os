#!/usr/bin/env bash
#
# setup-macstyle.sh — Idempotent macOS-style setup for CachyOS / KDE Plasma 6 (Wayland)
# =====================================================================================
# 안전하게 몇 번이든 다시 실행 가능(idempotent). 하는 일:
#   1. 한글 입력(fcitx5-hangul) + Spectacle + wl-clipboard + CJK폰트 설치  [수동 실행 시에만]
#      + Homebrew 도구(2lab-ai/tap: llmux, herdr-mx-preview)
#   2. fcitx5 설정: 한/영 토글 = Shift+Space
#   3. IME 환경변수 + 자동시작 항목 작성
#   4. 맥 스타일 KDE 전역 단축키를 kglobalaccel D-Bus로 설정
#   5. 매 로그인마다 자기 자신을 --login 모드로 재실행하도록 등록
#
# 새 계정에서 첫 사용:
#   cp setup-macstyle.sh ~/ && bash ~/setup-macstyle.sh
#   (그 후 로그아웃/로그인 1회 → IME 환경변수 + 앱실행 단축키까지 완전 활성화)
#
# 모드:
#   (인자 없음)   전체 설정 + 패키지 설치(필요 시 sudo)
#   --login       세션 전용: 설정+단축키만, 패키지 설치 없음 (자동시작이 사용)
#   --no-install  패키지 설치 건너뜀
#
# 주의: 이 스크립트는 "이 설정을 강제"하므로, 매 로그인마다 fcitx5 설정/단축키를
#       덮어씁니다. GUI로 따로 바꾼 값은 다음 로그인에 이 스크립트 값으로 되돌아갑니다.

set -uo pipefail

MODE_LOGIN=0
DO_INSTALL=1
for a in "$@"; do
  case "$a" in
    --login)      MODE_LOGIN=1; DO_INSTALL=0 ;;
    --no-install) DO_INSTALL=0 ;;
  esac
done

log()  { printf '\033[36m[macstyle]\033[0m %s\n' "$*"; }
warn() { printf '\033[33m[macstyle] WARN:\033[0m %s\n' "$*" >&2; }

SELF="$(realpath "${BASH_SOURCE[0]}")"

# ---------------------------------------------------------------------------
# 1. 패키지 설치 (pacman --needed = idempotent)
# ---------------------------------------------------------------------------
PKGS=(
  # 한글 입력 (fcitx5 + 한글 엔진 + Qt/GTK 연동)
  fcitx5 fcitx5-hangul fcitx5-configtool fcitx5-qt fcitx5-gtk
  # 스크린샷 / 화면 녹화
  spectacle
  # 클립보드 복사·붙여넣기 (Wayland: wl-copy / wl-paste)
  wl-clipboard
  # 한글·이모지 폰트 렌더링 (새 시스템에서 글자 깨짐 방지)
  noto-fonts-cjk noto-fonts-emoji
)
if [ "$DO_INSTALL" = 1 ]; then
  if command -v pacman >/dev/null 2>&1; then
    missing=()
    for p in "${PKGS[@]}"; do pacman -Qq "$p" &>/dev/null || missing+=("$p"); done
    if [ "${#missing[@]}" -gt 0 ]; then
      log "설치할 패키지: ${missing[*]}"
      sudo pacman -S --needed --noconfirm "${missing[@]}" || warn "pacman 설치 실패(계속 진행)"
    else
      log "필요 패키지 모두 설치돼 있음."
    fi
  else
    warn "pacman 없음 → 패키지 설치 건너뜀."
  fi
fi

# ---------------------------------------------------------------------------
# 1-B. Homebrew 패키지 (2lab-ai tap) — 설치 모드에서만 (매 로그인엔 안 돌림)
# ---------------------------------------------------------------------------
BREW_PKGS=(llmux herdr-mx-preview)
if [ "$DO_INSTALL" = 1 ]; then
  if command -v brew >/dev/null 2>&1; then
    brew trust 2lab-ai/tap 2>/dev/null || true   # 사용자 지정 (없으면 무시)
    brew update || warn "brew update 실패(계속 진행)"
    for p in "${BREW_PKGS[@]}"; do
      if brew list "$p" &>/dev/null; then
        log "brew: $p 이미 설치됨"
      else
        log "brew 설치: $p"
        brew install "$p" || warn "brew install $p 실패"
      fi
    done
  else
    warn "brew(Homebrew) 없음 → llmux/herdr-mx-preview 건너뜀. https://brew.sh 설치 후 다시 실행."
  fi
fi

# ---------------------------------------------------------------------------
# 2. 설정 파일 작성 (idempotent 덮어쓰기)
# ---------------------------------------------------------------------------
mkdir -p "$HOME/.config/environment.d" \
         "$HOME/.config/autostart" \
         "$HOME/.config/fcitx5" \
         "$HOME/.local/bin"

# IME 환경변수
cat > "$HOME/.config/environment.d/im.conf" <<'EOF'
GTK_IM_MODULE=fcitx
QT_IM_MODULE=fcitx
XMODIFIERS=@im=fcitx
SDL_IM_MODULE=fcitx
GLFW_IM_MODULE=ibus
EOF

# fcitx5 프로필: keyboard-us + hangul
cat > "$HOME/.config/fcitx5/profile" <<'EOF'
[Groups/0]
Name=Default
Default Layout=us
DefaultIM=hangul

[Groups/0/Items/0]
Name=keyboard-us
Layout=

[Groups/0/Items/1]
Name=hangul
Layout=

[GroupOrder]
0=Default
EOF

# fcitx5 설정: 한/영 토글 = Shift+Space (그 외 space 토글 전부 제거)
#  ※ 빈 리스트는 반드시 인라인 'Key=' 형식이어야 fcitx 기본값(Super+space 등)을 덮어씀.
#    '[Hotkey/Key]' 빈 서브섹션은 무시되고 기본값이 살아남으므로 쓰지 말 것.
cat > "$HOME/.config/fcitx5/config" <<'EOF'
[Hotkey]
EnumerateWithTriggerKeys=False
EnumerateSkipFirst=False
AltTriggerKeys=
EnumerateForwardKeys=
EnumerateBackwardKeys=
EnumerateGroupForwardKeys=
EnumerateGroupBackwardKeys=

[Hotkey/TriggerKeys]
0=Shift+space
1=Hangul

[Behavior]
ActiveByDefault=False
ShareInputState=All
PreeditEnabledByDefault=True
EOF

# 자동시작: fcitx5
cat > "$HOME/.config/autostart/org.fcitx.Fcitx5.desktop" <<'EOF'
[Desktop Entry]
Name=Fcitx 5
Exec=fcitx5
Icon=fcitx
Terminal=false
Type=Application
Categories=System;Utility;
StartupNotify=false
X-KDE-autostart-phase=1
X-GNOME-Autostart-Phase=Applications
EOF

# 자동시작: Spectacle 백그라운드(스크린샷 단축키용)
cat > "$HOME/.config/autostart/org.kde.spectacle-bg.desktop" <<'EOF'
[Desktop Entry]
Name=Spectacle (background shortcuts)
Exec=spectacle --dbus
Icon=spectacle
Terminal=false
Type=Application
X-KDE-autostart-phase=2
StartupNotify=false
EOF

# 자기 자신을 ~/.local/bin 에 설치하고 매 로그인 재적용 등록
TARGET="$HOME/.local/bin/setup-macstyle.sh"
if [ "$SELF" != "$TARGET" ]; then cp "$SELF" "$TARGET"; fi
chmod +x "$TARGET"

cat > "$HOME/.config/autostart/zz-macstyle-setup.desktop" <<EOF
[Desktop Entry]
Name=mac-style setup (per-login apply)
Exec=$TARGET --login
Icon=preferences-desktop-keyboard
Terminal=false
Type=Application
X-KDE-autostart-phase=2
StartupNotify=false
EOF

log "설정 파일 작성 완료."

# ---------------------------------------------------------------------------
# 3. KDE 전역 단축키 (kglobalaccel D-Bus) — 라이브 적용 + 파일 영속화
# ---------------------------------------------------------------------------
apply_shortcuts() {
  local dest=org.kde.kglobalaccel obj=/kglobalaccel
  local meth=org.kde.KGlobalAccel.setForeignShortcut
  command -v gdbus >/dev/null 2>&1 || { warn "gdbus 없음 → 단축키 건너뜀"; return; }

  # kglobalaccel(KWin)이 버스에 올라올 때까지 대기 (최대 ~15s)
  local i
  for i in $(seq 1 30); do
    if gdbus call --session --dest "$dest" --object-path "$obj" \
         --method org.kde.KGlobalAccel.shortcutKeys "['kwin','Expose','x','x']" >/dev/null 2>&1; then
      break
    fi
    sleep 0.5
  done

  set_sc() {
    gdbus call --session --dest "$dest" --object-path "$obj" --method "$meth" "$1" "$2" >/dev/null 2>&1 \
      && log "  ✓ $3" || warn "  ✗ $3"
  }

  # 타일링 → Meta+Shift+화살표 (Meta+화살표 비우기)
  set_sc "['kwin','Window Quick Tile Left','KWin','창 왼쪽']"   "[318767122]" "타일링 왼쪽 = Meta+Shift+Left"
  set_sc "['kwin','Window Quick Tile Right','KWin','창 오른쪽']" "[318767124]" "타일링 오른쪽 = Meta+Shift+Right"
  set_sc "['kwin','Window Quick Tile Top','KWin','창 위']"      "[318767123]" "타일링 위 = Meta+Shift+Up"
  set_sc "['kwin','Window Quick Tile Bottom','KWin','창 아래']"  "[318767125]" "타일링 아래 = Meta+Shift+Down"
  # Meta+Up = Overview(한눈에 보기 = 맥 Mission Control): 창 + 상단 가상데스크톱 스트립으로 정리
  #  (Expose 는 창만 나열이라 안 씀; 기본값 Ctrl+F9/Meta+F9 로 복원)
  set_sc "['kwin','Expose','KWin','보이는 창 바꾸기']" "[83886136, 285212728]" "Expose = Ctrl+F9/Meta+F9(기본)"
  set_sc "['kwin','Overview','KWin','한눈에 보기']" "[285212691, 268435543]" "창정리 Overview = Meta+Up (Meta+W 유지)"
  # 가상 데스크톱 전환 = Meta+Left/Right (Meta+Ctrl 유지)
  set_sc "['kwin','Switch One Desktop to the Left','KWin','왼쪽 데스크톱']"   "[285212690, 352321554]" "데스크톱 왼쪽 = Meta+Left"
  set_sc "['kwin','Switch One Desktop to the Right','KWin','오른쪽 데스크톱']" "[285212692, 352321556]" "데스크톱 오른쪽 = Meta+Right"
  # KRunner = Ctrl+Space (+ Alt+F2). Alt+Space는 의도적으로 제외.
  set_sc "['org.kde.krunner.desktop','_launch','KRunner','KRunner']" "[67108896, 150994993]" "앱검색 = Ctrl+Space"
  # Spectacle: 영역 스크린샷 / 영역 녹화
  #  ※ Shift+4=$ 이므로 숫자키코드 + 심볼키코드 둘 다 등록해야 물리키가 매칭됨
  #    Ctrl+Shift+4 = 숫자4(100663348) + $(100663332)
  #    Ctrl+Shift+5 = 숫자5(100663349) + %(100663333)
  set_sc "['org.kde.spectacle.desktop','RectangularRegionScreenShot','Spectacle','영역 스크린샷']" "[100663348, 100663332, 67108900, 67108916]" "스크린샷 = Ctrl+Shift+4"
  set_sc "['org.kde.spectacle.desktop','RecordRegion','Spectacle','영역 녹화']" "[100663349, 100663333, 67108901, 67108917]" "녹화 = Ctrl+Shift+5"
  # 화면 잠금 = Ctrl+Meta+Q (Meta+L 유지)
  set_sc "['ksmserver','Lock Session','ksmserver','세션 잠금']" "[335544401, 268435532]" "화면잠금 = Ctrl+Meta+Q"
}

RT="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
if [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ] || [ -S "$RT/bus" ]; then
  export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=$RT/bus}"
  log "KDE 단축키 적용 중..."
  apply_shortcuts
else
  warn "D-Bus 세션 없음 → 단축키는 다음 로그인에 적용됨."
fi

# ---------------------------------------------------------------------------
# 4. IME / 스크린샷 서비스 실행 보장 (없을 때만)
# ---------------------------------------------------------------------------
if command -v fcitx5 >/dev/null 2>&1 && ! pgrep -x fcitx5 >/dev/null 2>&1; then
  setsid fcitx5 -d >/dev/null 2>&1 < /dev/null &
  log "fcitx5 시작함"
fi
if command -v spectacle >/dev/null 2>&1 && ! pgrep -f 'spectacle --dbus' >/dev/null 2>&1; then
  setsid spectacle --dbus >/dev/null 2>&1 < /dev/null &
  log "spectacle --dbus 시작함"
fi

log "완료. (최초 설치 시: 로그아웃 후 재로그인 1회 → IME 환경변수 + 앱실행 단축키 완전 활성화)"
