# Understand-Anything — Bộ tự động hóa (Tiếng Việt)

Bộ này gồm **4 thứ** để tự động hóa hết các bước thủ công:

| File | Tự động hóa cái gì |
|------|-------------------|
| `setup-vscode-copilot.sh` | Cài plugin VS Code + Copilot trên máy local (1 dòng) |
| `validate-graph.mjs` | Kiểm tra `knowledge-graph.json` hợp schema + còn fresh |
| `understand-anything.yml` | Workflow GitHub Actions cho repo dùng plugin |
| (đề xuất `environment.yaml`) | Bootstrap môi trường Devin cho plugin repo (đã gửi vào timeline) |

---

## 1. Cài plugin VS Code + Copilot — `setup-vscode-copilot.sh`

Đã verify chạy trên Linux/Ubuntu. **Idempotent** — chạy lại bao nhiêu lần cũng không sao.

### Cách dùng

```bash
# Tải về và chạy (sau khi bạn đã upload script lên Gist hoặc repo của bạn):
curl -fsSL <URL-tới-script> | bash

# Hoặc chạy local:
bash setup-vscode-copilot.sh
```

### Việc nó làm

1. Check Node ≥ 22, git có sẵn
2. Update corepack mới (fix lỗi signing keys cũ trên Node 22.12) → activate `pnpm@10.6.2`
3. Tải `install.sh` chính thức từ GitHub → chạy `install.sh vscode`:
   - Clone repo về `~/.understand-anything/repo`
   - Symlink 8 skill (`/understand`, `/understand-dashboard`, `/understand-chat`,
     `/understand-diff`, `/understand-explain`, `/understand-onboard`,
     `/understand-domain`, `/understand-knowledge`) vào `~/.copilot/skills/`
   - Tạo symlink universal `~/.understand-anything-plugin`
4. `pnpm install` ở repo cache → tự build `@understand-anything/core` (cần cho
   `extract-structure.mjs` chạy không lỗi)
5. In hướng dẫn restart VS Code

### Sau khi script chạy xong

1. **Quit hẳn VS Code** (không reload window) và mở lại.
2. Mở repo bất kỳ → Copilot Chat (`Ctrl+Alt+I`) → gõ `/understand`.

---

## 2. Auto-update graph mỗi commit — `/understand --auto-update`

Tính năng có sẵn trong plugin (file `understand-anything-plugin/hooks/hooks.json`).
Sau khi đã chạy `/understand` lần đầu để có baseline graph:

```bash
# Trong Copilot Chat:
/understand --auto-update
```

Lệnh này:
1. Ghi `autoUpdate: true` vào `.understand-anything/config.json`.
2. Đăng ký 2 hook trong Claude/Copilot:
   - **`PostToolUse` (matcher: `Bash`)**: khi nhận diện được lệnh
     `git commit|merge|cherry-pick|rebase`, agent sẽ tự đọc
     `auto-update-prompt.md` và update graph.
   - **`SessionStart`**: nếu graph bị stale (so sánh `gitCommitHash` trong
     `meta.json` với `git rev-parse HEAD`), tự update khi mở session mới.
3. Cách update **tiết kiệm token**:
   - **Phase 1 (zero LLM tokens)**: chạy script Node so sánh fingerprint.
     Phân loại từng file thành `NONE` (không đổi), `COSMETIC` (chỉ format /
     internal logic), `STRUCTURAL` (đổi function/class/import).
   - **Phase 2 (chỉ chạy nếu có file STRUCTURAL)**: re-analyze 5–10 file/batch.
   - Nếu >30 file đổi hoặc >50% graph: gợi ý `/understand --full` thay vì update.

Tắt: `/understand --no-auto-update`

> Đây là cách "tự động" tốt nhất nếu bạn chỉ muốn graph luôn đồng bộ với code.

---

## 3. CI/CD — `understand-anything.yml` + `validate-graph.mjs`

Cho repo **đang dùng** plugin (không phải plugin repo gốc). Đảm bảo:
- `knowledge-graph.json` hợp schema (chống commit graph hỏng).
- Graph không bị stale (so sánh `meta.gitCommitHash` với `HEAD`).
- (Optional) Build dashboard tĩnh upload làm artifact để reviewer xem.

### Cài đặt vào repo của bạn

```bash
# Trong repo bạn đang dùng plugin
mkdir -p .github/workflows scripts
cp understand-anything.yml  .github/workflows/
cp validate-graph.mjs       scripts/

# Cài core làm devDependency (cần cho schema validator)
npm i -D @understand-anything/core
# hoặc: pnpm add -D @understand-anything/core
# hoặc: yarn add -D @understand-anything/core

# Commit folder graph (trừ scratch local)
cat >> .gitignore <<'EOF'
.understand-anything/intermediate/
.understand-anything/diff-overlay.json
EOF
git add .understand-anything/ .github/workflows/understand-anything.yml scripts/validate-graph.mjs .gitignore
git commit -m "ci: validate Understand-Anything knowledge graph"
```

### Đã verify trên VM

```bash
$ node scripts/validate-graph.mjs
✓ Graph valid (200 nodes, 340 edges)
```

Exit codes của validator:
| Code | Ý nghĩa |
|------|---------|
| 0 | OK |
| 1 | Schema sai |
| 2 | Không tìm thấy graph |
| 3 | Graph stale (chỉ khi `--check-stale`) |

### Workflow logic

| Sự kiện | Behavior |
|---------|----------|
| Push `main` | Validate schema **+** check stale (fail nếu stale) |
| Pull request | Validate schema (fail) **+** check stale (warn, không fail) **+** build dashboard preview làm artifact |

Bạn có thể siết chặt hoặc nới lỏng tuỳ ý — chỉ cần đổi `if:` và `continue-on-error:`.

---

## 4. Bootstrap môi trường Devin — `environment.yaml`

Mình đã gửi 1 đề xuất `environment.yaml` cho repo `Lum1104/Understand-Anything`
qua **timeline** ở session này. Khi bạn approve, mọi Devin session sau cho repo
này sẽ tự:

```yaml
initialize: |
  npm install -g corepack@latest
  corepack enable
  corepack prepare pnpm@10.6.2 --activate

maintenance: |
  pnpm install
  pnpm --filter @understand-anything/skill build
  pnpm --filter @understand-anything/dashboard build

knowledge:
  - test:           pnpm test                # 764 tests
  - build:          pnpm build
  - dashboard-dev:  pnpm dev:dashboard
  - sample-graph:   node scripts/generate-large-graph.mjs 200
```

Cách approve: vào timeline session này, expand item **"Setup Understand-Anything
monorepo"** → click **Approve**.

---

## Tóm gọn — Tự động hóa nào dùng khi nào?

| Use case | Dùng cái này |
|----------|--------------|
| Mới hoàn toàn, muốn cài plugin lên máy mình | **`setup-vscode-copilot.sh`** |
| Đã cài rồi, muốn graph luôn đồng bộ với code | **`/understand --auto-update`** |
| Muốn enforce trong team qua PR / CI | **`understand-anything.yml` + `validate-graph.mjs`** |
| Đang sửa chính plugin repo này, muốn Devin session tự setup | **`environment.yaml` (đã gửi timeline)** |
