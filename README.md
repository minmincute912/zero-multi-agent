# Hermes Agent Platform

Trợ lý cá nhân chạy 24/7 với chi phí suy luận **$0**. Hermes Agent (Nous Research) chạy native trên VPS; mọi lệnh gọi LLM
đi qua một router LiteLLM trong Docker, gom các nguồn miễn phí: Cloudflare Workers AI, OpenRouter `:free`
và tùy chọn Ollama trên Google Colab.

```
                      ┌─ VPS Ubuntu 24.04 (3 vCPU / 6 GB) ──────────────────────────────────┐
Telegram/Slack ───►   │  Hermes Agent (native, systemd user unit hermes-gateway, ~330 MB)   │
                      │    ├─ stdio: filesystem, fetch (npx/uvx)                            │
                      │    └─ HTTP 127.0.0.1:4000 ─► inference-router (LiteLLM, Docker)     │
                      │          light ─► Cloudflare Workers AI (Llama 3B, Granite)        │
                      │          heavy, coder ─► OpenRouter ":free"                         │
                      │          fallback ─► heavy-backup: Cloudflare GLM/GPT-OSS/Gemma     │
                      └─────────────────────────────────────────────────────────────────────┘
```

## Cấu trúc

| Đường dẫn | Vai trò |
|---|---|
| `hermes-core/` | `config.yaml` (model, MCP, skills), `SOUL.md` (nhân cách), `skills/` (kỹ năng, theo dõi bằng Git) |
| `docker-services/docker-compose.yml` | 1 service (router), mạng `agent-net`, healthcheck, `mem_limit`/`cpus` cứng |
| `docker-services/inference-router/` | Cấu hình LiteLLM: nhóm `light`, `heavy`, `coder`, `heavy-backup`, fallback, cooldown khi 429 |
| `deploy/` | `setup-vps.sh`, `update-vps.sh`, `list-free-models.sh` |
| `.github/workflows/ci.yml` | Chỉ lint/test. Không build image, không deploy |
| `.claude/` | Cấu hình Claude Code cho việc phát triển repo này |

## Định tuyến suy luận

Hermes chỉ biết một endpoint (`http://127.0.0.1:4000/v1`, khóa là `LITELLM_MASTER_KEY`) và ba nhóm model:

- `light`: Cloudflare Workers AI (Llama 3.2 3B, Granite 4.0 micro). Phân loại, tóm tắt, parse JSON. Tác vụ phụ của Hermes (nén ngữ cảnh, đặt tiêu đề) cũng dùng nhóm này.
- `heavy`: các model OpenRouter `:free`, mặc định cho suy luận và tool-calling.
- `coder`: OpenRouter `:free`. Hiện OpenRouter không còn model free chuyên code (`cohere/north-mini-code:free` đã biến mất), nên nhóm này dùng model tổng quát lớn nhất.
- `heavy-backup` (chỉ dùng làm fallback, Hermes không gọi trực tiếp): các model Cloudflare lớn hơn (GLM-4.7-flash, GPT-OSS-20B, Gemma 4 26B) có hạn mức riêng, và tùy chọn Ollama trên Google Colab T4 (`COLAB_OLLAMA_BASE_URL` qua IP Tailscale, đang để comment trong `config.yaml`).

Nhiều deployment cùng nhóm được chia tải; deployment dính 429/lỗi bị cooldown 60 giây rồi request chuyển sang deployment khác.
Chuỗi fallback: `light` → `heavy` → `heavy-backup`; `heavy` → `heavy-backup`; `coder` → `heavy` → `heavy-backup`.
Chuỗi chỉ đi lên nhóm mạnh hơn, không bao giờ hạ xuống model 1-3B để trả lời việc khó.
Mọi model trong `config.yaml` đều là model free, nên cấu hình này không thể tính phí trừ khi bạn thêm model trả phí.

Danh sách model free thay đổi liên tục. Chạy `deploy/list-free-models.sh` rồi sửa `docker-services/inference-router/config.yaml` qua PR.
Tài liệu Cloudflare vẫn liệt kê model đã ngừng (trả `410`), nên phải gọi thử từng ID bằng khóa thật trước khi thêm. Nous Portal bị loại vì tạo key cần nạp tiền hoặc đăng ký gói.

## Chạy thử trên máy local

```bash
cp .env.example .env     # điền LITELLM_MASTER_KEY, OPENROUTER_API_KEY, CLOUDFLARE_*
docker compose --env-file .env -f docker-services/docker-compose.yml up -d --build
docker compose --env-file .env -f docker-services/docker-compose.yml ps    # chờ healthy

curl -s -H "Authorization: Bearer $LITELLM_MASTER_KEY" http://127.0.0.1:4000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"heavy","messages":[{"role":"user","content":"ping"}],"max_tokens":8}'
```

Cổng chỉ bind `127.0.0.1`. Chưa cài Hermes ở local thì chỉ cần thử router bằng lệnh `curl` ở trên.

## Triển khai lên VPS

```bash
# trên VPS, quyền root
git clone <repo-url> /tmp/bootstrap && cd /tmp/bootstrap
sudo REPO_URL=<repo-url> TS_AUTHKEY=tskey-... ./deploy/setup-vps.sh
```

Script cài gói, swap 2 GB (nếu máy chưa có swap), Docker, Tailscale, user `hermes`, UFW (chặn inbound; qua Tailscale chỉ mở cổng 22 và 4000; SSH công khai giới hạn tốc độ), Hermes native,
unit `hermes-gateway` (do chính `hermes gateway install` tạo, chạy ở chế độ user service + linger), và timer
`hermes-gitops.timer` (pull mỗi 5 phút). Script **không** khởi động agent. Làm tiếp theo hướng dẫn in ra ở cuối:
điền khóa API vào `/opt/hermes-platform/.env`, chạy `update-vps.sh --force`, `hermes gateway setup`, `hermes gateway start`.

`CLOSE_PUBLIC_SSH=1` đóng cổng SSH công khai, chỉ dùng sau khi chắc chắn đã vào được qua Tailscale.

## Quy trình vận hành

1. Sửa cấu hình/code trên nhánh, mở PR. CI chạy lint, kiểm tra YAML/JSON/skill, shellcheck, `docker compose config`.
2. Merge vào `main`. Không có bước build hay deploy từ CI.
3. VPS tự đồng bộ bằng `hermes-gitops.timer` (5 phút), hoặc chạy tay `deploy/update-vps.sh`.

`update-vps.sh` không làm sập session đang chạy:
- Hermes chỉ restart khi `hermes-core/config.yaml` hoặc `SOUL.md` đổi, bằng `hermes gateway restart` (chờ các lượt đang xử lý xong).
- Container chỉ bị đụng khi `docker-services/` đổi; `compose up --build` chỉ tạo lại service có cấu hình đổi, và chờ healthy (tối đa 180 giây).
- Skill mới được đọc trực tiếp từ repo, không cần restart.
- Có khóa `flock` chống chạy chồng; không thể fast-forward thì dừng và báo lỗi, không ghi đè.

Cấu hình trên VPS là bản sao của repo (file cũ được lưu `.bak`), nên mọi thay đổi phải đi qua Git.
Skill do Hermes tự tạo nằm trong `hermes-core/skills/` dưới dạng file chưa commit; hãy commit chúng từ máy phát triển hoặc dọn đi.

## Điền khóa API

| Biến | Lấy ở đâu | Ghi vào |
|---|---|---|
| `OPENROUTER_API_KEY` | openrouter.ai/keys | `.env` |
| `CLOUDFLARE_API_KEY`, `CLOUDFLARE_ACCOUNT_ID` | Cloudflare dashboard, Workers AI | `.env` |
| `COLAB_OLLAMA_BASE_URL` | IP Tailscale của Colab Ollama (tùy chọn) | `.env` |
| `LITELLM_MASTER_KEY` | `setup-vps.sh` tự sinh | `.env` và `~/.hermes/.env` |
| `TELEGRAM_BOT_TOKEN`, `TELEGRAM_ALLOWED_USERS` | BotFather và user id của bạn | `~/.hermes/.env` |

Không bao giờ commit `.env`, `*.sqlite`, `browser-profiles/`: `.gitignore`, hook của Claude Code và bước kiểm tra trong CI đều chặn.

## Giới hạn đã biết

- Phần `model`/`providers` trong `hermes-core/config.yaml` theo ví dụ trong tài liệu nhưng **chưa chạy thử với Hermes thật**. Sau khi cài, chạy `hermes config check` và `hermes doctor`.
- Chưa có Postgres cho LiteLLM nên chưa có virtual key và budget theo agent. Chặn tiền hiện dựa vào việc chỉ khai báo model free.
- Image LiteLLM dùng tag trôi `main-stable`. Hãy pin digest sau khi kiểm chứng một phiên bản.
- Các quota free-tier thay đổi. Kiểm tra lại tại nhà cung cấp trước khi dựa vào.
