#!/usr/bin/env bash
# setup-vscode-copilot.sh
#
# All-in-one bootstrap cho Understand-Anything trên VS Code + GitHub Copilot.
# Idempotent — chạy lại được bao nhiêu lần cũng không sao.
#
# Việc nó làm:
#   1. Cài/cập nhật corepack mới + pnpm@10.6.2
#   2. Chạy install.sh vscode (clone repo + symlink 8 skill vào ~/.copilot/skills)
#   3. pnpm install ở repo cache để build core (cần cho /understand chạy)
#   4. In hướng dẫn next-step (restart VS Code)
#
# Usage:
#   curl -fsSL <url-tới-script-này> | bash
#   hoặc:  bash setup-vscode-copilot.sh

set -euo pipefail

UA_REPO_DIR="${UA_DIR:-$HOME/.understand-anything/repo}"
UA_INSTALL_URL="https://raw.githubusercontent.com/Lum1104/Understand-Anything/main/install.sh"

step() { printf '\n\033[1;36m▸ %s\033[0m\n' "$*"; }
ok()   { printf '  \033[1;32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[1;33m!\033[0m %s\n' "$*" >&2; }
die()  { printf '  \033[1;31m✗\033[0m %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 0. Sanity: cần git và node ≥ 22
# ---------------------------------------------------------------------------
step "Kiểm tra prerequisites"
command -v git  >/dev/null || die "Cần git. Cài rồi chạy lại."
command -v node >/dev/null || die "Cần Node.js ≥ 22. Cài (nvm/volta/fnm) rồi chạy lại."
NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]')"
if [[ "$NODE_MAJOR" -lt 22 ]]; then
  die "Node.js phiên bản $NODE_MAJOR — cần ≥ 22. Update Node rồi chạy lại."
fi
ok "node $(node --version), git $(git --version | awk '{print $3}')"

# ---------------------------------------------------------------------------
# 1. corepack + pnpm@10.6.2
# ---------------------------------------------------------------------------
step "Bootstrap pnpm@10.6.2 qua corepack"
if command -v corepack >/dev/null; then
  COREPACK_VER="$(corepack --version 2>/dev/null || echo 0.0.0)"
  COREPACK_MAJOR="$(printf '%s\n' "$COREPACK_VER" | cut -d. -f1)"
  COREPACK_MINOR="$(printf '%s\n' "$COREPACK_VER" | cut -d. -f2)"
  # corepack < 0.30 có signing keys cũ → không verify được pnpm 10.x
  if (( COREPACK_MAJOR == 0 && COREPACK_MINOR < 30 )); then
    warn "corepack $COREPACK_VER quá cũ — đang upgrade (cần npm)"
    npm install -g corepack@latest >/dev/null
  fi
fi
corepack enable >/dev/null
corepack prepare pnpm@10.6.2 --activate >/dev/null
PNPM_VER="$(pnpm --version)"
[[ "$PNPM_VER" == 10.* ]] || die "pnpm bootstrap thất bại (got $PNPM_VER)"
ok "pnpm $PNPM_VER"

# ---------------------------------------------------------------------------
# 2. Chạy installer chính thức cho VS Code
# ---------------------------------------------------------------------------
step "Cài Understand-Anything skills cho VS Code Copilot"
TMP_INSTALLER="$(mktemp)"
trap 'rm -f "$TMP_INSTALLER"' EXIT
curl -fsSL "$UA_INSTALL_URL" -o "$TMP_INSTALLER"
chmod +x "$TMP_INSTALLER"
"$TMP_INSTALLER" vscode

# ---------------------------------------------------------------------------
# 3. Pre-build core trong repo cache (để /understand chạy không bị thiếu dist/)
# ---------------------------------------------------------------------------
step "Pre-build @understand-anything/core trong repo cache"
if [[ ! -d "$UA_REPO_DIR" ]]; then
  die "Không tìm thấy $UA_REPO_DIR — installer phải đã clone repo. Coi log phía trên."
fi
(
  cd "$UA_REPO_DIR"
  pnpm install --frozen-lockfile=false
)
ok "core đã build (packages/core/dist/)"

# ---------------------------------------------------------------------------
# 4. Hướng dẫn next-step
# ---------------------------------------------------------------------------
B=$'\033[1m'; G=$'\033[1;32m'; R=$'\033[0m'
cat <<EOF

${G}═══════════════════════════════════════════════════════════════${R}
${G}  Cài đặt hoàn tất ✓${R}
${G}═══════════════════════════════════════════════════════════════${R}

Bước tiếp theo:

  1. ${B}Quit hẳn VS Code và mở lại${R} (không phải reload window).
     Copilot chỉ scan ~/.copilot/skills/ khi khởi động.

  2. Đảm bảo VS Code ≥ 1.108 và Copilot extension đang bật.

  3. Mở repo bạn muốn phân tích → Copilot Chat (${B}Ctrl+Alt+I${R}) →
     gõ ${B}/understand${R}

  4. Sau khi pipeline xong → gõ ${B}/understand-dashboard${R}

Tự động hóa thêm:
  • Bật auto-update graph mỗi commit:  ${B}/understand --auto-update${R}
  • Update bản plugin sau này:          ${B}$UA_REPO_DIR/install.sh --update${R}
  • Gỡ:                                  ${B}$UA_REPO_DIR/install.sh --uninstall vscode${R}

EOF
