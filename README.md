# Hermes Agent Platform

Hệ thống agent chạy 24/7 với chi phí suy luận **$0**: Hermes Agent (Nous Research) chạy native, mọi lệnh gọi LLM đi qua
một router LiteLLM gom các free-tier API, các dịch vụ nặng chạy trong Docker.

```
                      ┌──────────────── VPS Ubuntu 24.04 (4 vCPU / 8 GB) ────────────────┐
 Telegram/Slack ───►  │  Hermes Agent (native, systemd user unit hermes-gateway, ~330 MB)│
                      │    │ stdio: filesystem, fetch (npx/uvx)                          │
                      │    │ HTTP (127.0.0.1):                                           │
                      │    ├─► :4000 inference-router (LiteLLM)  ─► Cloudflare Workers AI│
                      │    │                                      ─► OpenRouter ":free"  │
                      │    │                                      ─► Nous Portal (free)  │
                      │    ├─► :8001 mcp-web-worker (Playwright + Xvfb + noVNC :6080)    │
                      │    └─► :8002 node-control-plane ─► satellite nodes (Tailscale)   │
                      └───────────────────────────────────────────────────────────────────┘
```

## Cấu trúc

| Đường dẫn | Vai trò |
|---|---|
| `hermes-core/` | `config.yaml` (model, MCP, skills), `SOUL.md` (nhân cách), `skills/` (kỹ năng, theo dõi bằng Git) |
| `docker-services/docker-compose.yml` | 3 service, mạng `agent-net`, healthcheck, `mem_limit`/`cpus` cứng |
| `docker-services/inference-router/` | Cấu hình LiteLLM: nhóm model `light`, `heavy`, `coder`, fallback, cooldown khi 429 |
| `docker-services/mcp-web-worker/` | Chromium có profile bền + noVNC để đăng nhập tay một lần (2FA/captcha) |
| `docker-services/node-control-plane/` | MCP server: health-check, đếm quota, đẩy job ký HMAC sang node vệ tinh |
| `mcp-plugins/_template/` | Copy thư mục này để tạo MCP microservice mới (xem README trong đó) |
| `deploy/` | `setup-vps.sh`, `update-vps.sh`, `list-free-models.sh` |
| `.github/workflows/gitops-deploy.yml` | Lint/test, build image lên GHCR, kích hoạt VPS đồng bộ |
| `.claude/` | Cấu hình Claude Code cho việc phát triển repo này |

## Định tuyến suy luận

Hermes chỉ biết một endpoint (`http://127.0.0.1:4000/v1`, khóa là `LITELLM_MASTER_KEY`) và ba nhóm model:

- `light`: Cloudflare Workers AI (phân loại, tóm tắt, parse JSON). Tác vụ phụ của Hermes (nén ngữ cảnh, đặt tiêu đề) cũng dùng nhóm này.
- `heavy`: các model OpenRouter `:free`, mặc định cho suy luận và tool-calling.
- `coder`: model code `:free`, fallback sang `heavy`.

Nhiều deployment cùng nhóm được chia tải; deployment dính 429/lỗi bị cooldown 60 giây rồi request chuyển sang deployment khác.
`light` và `coder` fallback sang `heavy`. `heavy` cố ý không có fallback để model 3B không âm thầm trả lời việc khó.
Mọi model trong `config.yaml` đều là model free, nên cấu hình này không thể tính phí trừ khi bạn thêm model trả phí.

Danh sách model free thay đổi liên tục. Chạy `deploy/list-free-models.sh` rồi sửa `docker-services/inference-router/config.yaml` qua PR.
Nous Portal đang để sẵn khối comment (chưa có ID model đã xác minh).

## Chạy thử trên máy local

```bash
cp .env.example .env     # điền LITELLM_MASTER_KEY, VNC_PASSWORD, OPENROUTER_API_KEY, CLOUDFLARE_*; HOST_UID/GID = id -u / id -g
mkdir -p docker-services/browser-profiles
docker compose --env-file .env -f docker-services/docker-compose.yml up -d --build
docker compose --env-file .env -f docker-services/docker-compose.yml ps    # chờ cả 3 healthy

curl -s -H "Authorization: Bearer $LITELLM_MASTER_KEY" http://127.0.0.1:4000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"heavy","messages":[{"role":"user","content":"ping"}],"max_tokens":8}'
```

Cổng chỉ bind `127.0.0.1`. Nếu chưa cài Hermes local, chỉ cần dùng được các endpoint MCP ở `:8001/mcp` và `:8002/mcp`.
Dịch vụ MCP dùng **Streamable HTTP** (đường dẫn `/mcp`), không dùng SSE: SDK MCP v2 coi SSE là legacy và Hermes mặc định dùng Streamable HTTP.

## Triển khai lên VPS

```bash
# trên VPS, quyền root
git clone <repo-url> /tmp/bootstrap && cd /tmp/bootstrap
sudo REPO_URL=<repo-url> TS_AUTHKEY=tskey-... ./deploy/setup-vps.sh
```

Script cài gói, Docker, Tailscale, user `hermes`, UFW (chặn inbound trừ Tailscale và SSH giới hạn tốc độ), Hermes native,
unit `hermes-gateway` (do chính `hermes gateway install` tạo, chạy ở chế độ user service + linger), và timer
`hermes-gitops.timer` (pull mỗi 5 phút). Script **không** khởi động agent. Làm tiếp theo hướng dẫn in ra ở cuối:
điền khóa API vào `/opt/hermes-platform/.env`, chạy `update-vps.sh --force`, `hermes gateway setup`, `hermes gateway start`.

`CLOSE_PUBLIC_SSH=1` đóng cổng SSH công khai, chỉ dùng sau khi chắc chắn đã vào được qua Tailscale.

### Đăng nhập web thủ công lần đầu

noVNC nghe ở `127.0.0.1:6080` trên VPS. Dùng tunnel: `ssh -L 6080:127.0.0.1:6080 hermes@<tên-tailnet>`, mở `http://127.0.0.1:6080`,
nhập `VNC_PASSWORD`, đăng nhập vào site và xử lý 2FA. Cookie nằm trong `docker-services/browser-profiles/` (bị `.gitignore` chặn) nên bền qua lần restart.

## Quy trình vận hành (GitOps)

1. Sửa cấu hình/code trên nhánh, mở PR. CI chạy lint, kiểm tra YAML/JSON/skill, shellcheck, `docker compose config`, smoke test MCP.
2. Merge vào `main`. CI chỉ build image khi `docker-services/` hoặc `mcp-plugins/` đổi, rồi đẩy lên `ghcr.io/<owner>/hermes-<tên>:latest` và `:sha-…`.
3. VPS đồng bộ qua timer (5 phút) hoặc ngay lập tức qua CI nếu bật deploy bằng Tailscale. Cả hai gọi `deploy/update-vps.sh`.

`update-vps.sh` không làm sập session đang chạy:
- Hermes chỉ restart khi `hermes-core/config.yaml` hoặc `SOUL.md` đổi, bằng `hermes gateway restart` (chờ các lượt đang xử lý xong).
- Container chỉ bị đụng khi `docker-services/` hoặc `mcp-plugins/` đổi; `compose up` chỉ tạo lại service có image/cấu hình đổi, và chờ healthy (tối đa 180 giây).
- Skill mới được đọc trực tiếp từ repo, không cần restart.
- Có khóa `flock` chống chạy chồng; không thể fast-forward thì dừng và báo lỗi, không ghi đè.

Bật deploy tức thời từ CI: tạo Tailscale OAuth client (tag `tag:ci`) và ACL cho phép SSH tới VPS; đặt secrets
`TS_OAUTH_CLIENT_ID`, `TS_OAUTH_SECRET` và variables `DEPLOY_VIA_TAILSCALE=true`, `VPS_HOST`, `VPS_USER`.
Nếu image GHCR là private, chạy `docker login ghcr.io` trên VPS bằng token chỉ có quyền `read:packages`; thiếu thì VPS tự build local.

Cấu hình trên VPS là bản sao của repo (file cũ được lưu `.bak`), nên mọi thay đổi phải đi qua Git.
Skill do Hermes tự tạo nằm trong `hermes-core/skills/` dưới dạng file chưa commit; hãy commit chúng từ máy phát triển hoặc dọn đi.

## Điền khóa API

| Biến | Lấy ở đâu | Ghi vào |
|---|---|---|
| `OPENROUTER_API_KEY` | openrouter.ai/keys | `.env` |
| `CLOUDFLARE_API_KEY`, `CLOUDFLARE_ACCOUNT_ID` | Cloudflare dashboard, Workers AI | `.env` |
| `NOUS_API_KEY` | Nous Portal (tùy chọn) | `.env` |
| `LITELLM_MASTER_KEY`, `VNC_PASSWORD` | `setup-vps.sh` tự sinh | `.env` và `~/.hermes/.env` |
| `TELEGRAM_BOT_TOKEN`, `TELEGRAM_ALLOWED_USERS` | BotFather và user id của bạn | `~/.hermes/.env` |
| `NODE_*_SECRET` | tự sinh, trùng với secret trên node vệ tinh | `.env` |

Không bao giờ commit `.env`, `*.sqlite`, `browser-profiles/`: `.gitignore`, hook của Claude Code và bước kiểm tra trong CI đều chặn.

## Giới hạn đã biết

- Phần `model`/`providers` trong `hermes-core/config.yaml` theo ví dụ trong tài liệu nhưng **chưa chạy thử với Hermes thật**. Sau khi cài, chạy `hermes config check` và `hermes doctor`.
- Chưa có Postgres cho LiteLLM nên chưa có virtual key và budget theo agent. Chặn tiền hiện dựa vào việc chỉ khai báo model free.
- `mcp-web-worker` chặn địa chỉ không công khai, nhưng chưa chặn redirect và DNS rebinding. Đừng cho agent duyệt site không tin cậy khi không giám sát.
- Image LiteLLM dùng tag trôi `main-stable`. Hãy pin digest sau khi kiểm chứng một phiên bản.
- Các quota free-tier thay đổi. Kiểm tra lại tại nhà cung cấp trước khi dựa vào.
