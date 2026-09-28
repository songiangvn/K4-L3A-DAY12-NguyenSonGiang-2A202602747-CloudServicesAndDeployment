# Phiếu Phản Ánh — K4 Level 3A, Ngày 12

> **Bài làm cá nhân.** Trả lời bằng lời của chính bạn, dựa trên những gì bạn
> quan sát được khi chạy code — không sao chép đáp án của người khác.
>
> Cách trả lời: thay dòng placeholder "Câu trả lời của bạn" bằng câu trả lời.
> `grade.py` đếm số câu đã trả lời (15 điểm cho 10 câu).
>
> Họ và tên: Nguyễn Sơn Giang  Mã học viên: 2A202602747

---

### Câu 1 — Fail fast (CP1)

Trong `Settings`, `agent_api_key` không có giá trị mặc định nên app chết ngay
khi khởi động nếu thiếu biến môi trường. Hãy mô tả một tình huống cụ thể mà
việc "chết sớm" này cứu bạn, so với việc để mặc định `"changeme"`.

Tình huống của chính bài này: khi deploy lên Render, `AGENT_API_KEY` được khai
báo `sync: false` nên Render bắt mình tự nhập giá trị trên dashboard. Giả sử mình
bấm Deploy mà quên nhập ô đó:

- **Không có mặc định:** `Settings()` ném `ValidationError: agent_api_key Field
  required` ngay lúc uvicorn khởi động → container thoát, health check `/health`
  không bao giờ xanh, Render báo deploy **failed** và giữ nguyên bản cũ. Mình
  thấy lỗi đỏ ngay trong tab Logs trong vòng 1–2 phút, lúc mình vẫn đang nhìn
  màn hình, sửa bằng cách nhập biến rồi deploy lại.
- **Mặc định `"changeme"`:** deploy "thành công", mọi thứ xanh, nhưng `/ask` giờ
  được bảo vệ bằng khóa `changeme` — chuỗi mà ai đọc repo công khai của mình
  (hoặc bot đoán mật khẩu phổ biến) đều biết. Service chạy bình thường nên không
  có gì báo động; mình chỉ phát hiện khi nhìn thấy log/hóa đơn LLM tăng bất
  thường, tức là khi đã mất tiền.

Fail fast biến một lỗ hổng bảo mật âm thầm thành một lỗi deploy ồn ào — loại lỗi
rẻ nhất để sửa.

---

### Câu 2 — Log cho máy đọc (CP1)

Chạy service và gọi `/ask` vài lần. Dán một dòng log JSON bạn thu được, rồi
nêu **hai** việc bạn làm được với dòng log đó mà `print("đã trả lời xong")`
không làm được.

Dòng log thật lấy từ `docker compose logs agent` khi chạy 3 container:

```json
{"event": "ask_completed", "level": "info", "timestamp": "2026-09-28T11:36:19.876328+00:00", "user_id": "sv01", "tokens_in": 1, "tokens_out": 40, "cost_usd": 2.415e-05}
```

Hai việc làm được mà `print("đã trả lời xong")` không làm được:

1. **Lọc và tổng hợp theo trường.** Vì mỗi dòng là một JSON object, mình có thể
   hỏi "user nào tiêu nhiều tiền nhất hôm nay" bằng cách lọc `event ==
   "ask_completed"` rồi group theo `user_id` và cộng `cost_usd` (bằng `jq`, hoặc
   query trong Datadog/Grafana Loki). Với `print` thì không có `user_id` hay
   `cost_usd` để group, chỉ có một câu tiếng Việt giống hệt nhau ở mọi dòng.
2. **Đặt cảnh báo và đo theo thời gian.** Có `level` và `timestamp` chuẩn ISO-8601
   (UTC) nên có thể tạo alert kiểu "số dòng `level=error` trong 5 phút > 10 thì
   báo", hoặc vẽ biểu đồ số request/phút, tokens/phút. Dòng `print` không có mức
   log, không có thời gian (hoặc giờ theo máy, lệch múi giờ), máy không phân biệt
   được dòng nào là lỗi.

Thêm một chi tiết mình để ý: log phải nằm trên **một dòng** — nếu dùng
`indent=2`, platform gom log theo dòng sẽ cắt một event thành 7–8 mảnh không
parse được.

---

### Câu 3 — Kích thước image (CP2)

Build cả hai phiên bản và ghi lại số đo thật:

```bash
docker build -f <Dockerfile-1-stage> -t agent:single .
docker build -t agent:multi .
docker images | grep agent
```

| Bản | Dung lượng |
|-----|-----------|
| 1 stage (bản đầu) | 1830 MB (1.83GB, `python:3.11`) |
| Multi-stage | 271 MB (`python:3.11-slim`) |

Giải thích: phần dung lượng chênh lệch đó là những gì?

Chênh khoảng 1.56GB, gần như toàn bộ đến từ **base image**, không phải từ code
hay thư viện của mình:

- `python:3.11` bản đầy đủ dựa trên Debian đầy đủ, có sẵn bộ build tool (`gcc`,
  `make`, `binutils`), header dev (`libssl-dev`, `libffi-dev`...), `git`,
  `curl`, ImageMagick, thư viện database client... — thứ chỉ cần khi *biên dịch*
  package, không cần khi *chạy* app. `python:3.11-slim` bỏ hết những thứ này.
- Bản 1 stage còn chứa những thứ lẽ ra không được vào image: `COPY . .` chép cả
  thư mục `.git`, `tests/`, tài liệu, và **cả file `.env` chứa API key thật của
  mình** (vì lúc đó `.dockerignore` chưa loại `.env`). Pip cache cũng nằm lại do
  thiếu `--no-cache-dir`.
- Bản multi-stage: stage `builder` cài dependency vào `/install`, stage `runtime`
  chỉ `COPY --from=builder /install /usr/local` và copy đúng 2 thư mục `app/`,
  `utils/`. Mọi thứ còn lại ở stage builder bị vứt bỏ.

271MB còn lại chủ yếu là Python runtime (~150MB của slim) và các thư viện trong
`requirements.txt` (fastapi, uvicorn[standard], pydantic, redis — và cả
pytest/fakeredis vì file requirements đang gộp chung; tách
`requirements-dev.txt` sẽ nhỏ thêm được một chút).

---

### Câu 4 — Thứ tự lệnh trong Dockerfile (CP2)

Sửa một ký tự trong `app/main.py` rồi build lại. Với Dockerfile của bạn, những
layer nào được dùng lại từ cache, layer nào phải chạy lại? Nếu bạn đặt
`COPY . .` lên trước `RUN pip install` thì kết quả khác thế nào?

Mình thêm một dòng comment vào cuối `app/main.py` rồi build lại (có
`BUILDKIT_PROGRESS=plain` để xem từng bước):

- **Dùng lại từ cache (`CACHED`):** `WORKDIR /build`, `COPY requirements.txt`,
  `RUN pip install ...`, `RUN useradd ...`, `WORKDIR /app`,
  `COPY --from=builder /install /usr/local`.
- **Chạy lại:** chỉ `COPY app ./app` và `COPY utils ./utils` (layer sau layer
  đầu tiên bị thay đổi đều phải làm lại, nên `utils` cũng chạy lại dù không đổi).
- **Tổng thời gian build lại: 3.8 giây.**

Với Dockerfile gốc (1 stage, `COPY . .` đứng trước `RUN pip install`), làm đúng
thí nghiệm đó: layer `COPY . .` thay đổi vì `main.py` đổi, nên **mọi layer sau
nó mất cache** — `RUN pip install -r requirements.txt` chạy lại từ đầu (23.1 giây
riêng bước này), **tổng 32.3 giây**. Mỗi lần sửa một dấu phẩy là tải và cài lại
toàn bộ thư viện, dù `requirements.txt` không hề đổi.

Nguyên tắc: xếp layer từ thứ **ít thay đổi nhất** (base image, dependency) đến
thứ **thay đổi nhiều nhất** (source code).

---

### Câu 5 — Vì sao không chạy bằng root (CP2)

Container mặc định chạy bằng root. Mô tả chuỗi sự kiện dẫn từ "một lỗ hổng
trong code Python của bạn" tới "kẻ tấn công có quyền cao trên máy host", và
lệnh `USER` cắt đứt chuỗi đó ở chỗ nào.

Chuỗi sự kiện khi container chạy root:

1. App có một lỗ hổng cho phép chạy code tùy ý — ví dụ một thư viện bị lỗi
   deserialize, hoặc mình lỡ viết `eval`/`subprocess` với input của user.
2. Kẻ tấn công gửi request độc hại → có shell bên trong container, **với UID 0
   (root)**.
3. Là root trong container, họ đọc/sửa được mọi file trong container (đọc biến
   môi trường chứa `AGENT_API_KEY`, `REDIS_URL`; sửa code app để cài backdoor),
   cài thêm tool (`apt install`).
4. Root trong container **chính là UID 0 trên host** (khi không bật user
   namespace remapping). Chỉ cần thêm một cấu hình sai — mount volume từ host,
   mount `/var/run/docker.sock`, container `--privileged`, hoặc một lỗ hổng
   kernel/runtime kiểu CVE runc năm 2019 — là họ thoát ra ngoài và có quyền root
   trên máy host, từ đó chạm tới mọi container khác trên máy đó.

`USER appuser` (UID 10001) cắt chuỗi ở **bước 2**: shell kẻ tấn công lấy được chỉ
là một user thường. User đó không cài được package, không ghi được vào thư mục
hệ thống, và nếu có thoát ra host thì cũng chỉ là UID 10001 — một user không có
quyền gì trên host. Mình đã kiểm tra bằng `docker compose exec agent whoami` →
`appuser`.

---

### Câu 6 — Cửa sổ trượt (CP3)

Rate limit của bạn dùng sliding window 60 giây. Nếu thay bằng cách đếm theo
phút đồng hồ (reset lúc giây 00), một người dùng có thể gửi tối đa bao nhiêu
request trong 2 giây liên tiếp khi hạn mức là 10/phút? Giải thích cách đạt được
con số đó.

**Tối đa 20 request trong 2 giây** — gấp đôi hạn mức.

Cách làm: gửi 10 request lúc 10:00:59 (vẫn thuộc "phút 10:00", bộ đếm 0 → 10,
đều được cho qua). Đến 10:01:00 bộ đếm reset về 0 vì sang phút mới. Gửi thêm 10
request lúc 10:01:00–10:01:01 → lại được cho qua hết. Tổng 20 request trong
khoảng 2 giây mà vẫn "đúng luật" theo từng phút.

Sliding window không có kẽ hở này vì nó luôn đếm 60 giây **tính ngược từ thời
điểm hiện tại**: lúc 10:01:01, 10 request gửi lúc 10:00:59 vẫn nằm trong cửa sổ
(chúng chỉ bị `zremrangebyscore` loại đi sau 10:01:59), nên request thứ 11 bị
chặn ngay. Khi test thật trên bản deploy Render, 15 request liên tiếp cho kết
quả `200` × 10 rồi `429` × 5 — đúng 10 request trong mọi khoảng 60 giây.

---

### Câu 7 — Rate limit và cost guard (CP3)

Hai cơ chế này khác nhau ở điểm nào? Cho một tình huống mà rate limit cho qua
nhưng cost guard phải chặn, và một tình huống ngược lại.

Khác nhau ở **đơn vị đo** và **khung thời gian**:

| | Rate limit | Cost guard |
|---|---|---|
| Đếm cái gì | số request | số tiền (USD) |
| Cửa sổ | 60 giây trượt | cả tháng (`cost:<user>:<YYYY-MM>`) |
| Bảo vệ khỏi | spam, bot, vòng lặp lỗi làm quá tải service | hóa đơn LLM vượt ngân sách |
| Mã lỗi | 429 (thử lại sau `Retry-After`) | 402 (đợi tháng sau / nạp thêm) |

**Rate limit cho qua nhưng cost guard chặn:** một user gửi đều đặn 8 request/phút
(dưới hạn mức 10), nhưng mỗi request là một câu hỏi dài kèm lịch sử hội thoại
20 message → mỗi lượt tốn nhiều token. Không lượt nào "quá nhanh", nhưng chạy
như vậy vài ngày liền thì tổng chi phí tháng vượt `MONTHLY_BUDGET_USD=10` → cost
guard trả 402.

**Cost guard cho qua nhưng rate limit chặn:** một script bị lỗi retry vòng lặp
gửi 50 request "hi" trong 5 giây. Mỗi request chỉ tốn ~0.00002 USD (như số đo
thật: `cost_usd: 2.415e-05`), tổng vẫn cách rất xa ngân sách 10 USD, nhưng từ
request thứ 11 trở đi rate limit trả 429 để bảo vệ service và Redis khỏi bị
dội.

Vì vậy cần cả hai — và cả hai đều phải chặn **trước** khi gọi LLM.

---

### Câu 8 — /health khác /ready (CP4)

Nếu gộp hai endpoint làm một và cho nó kiểm tra Redis, chuyện gì xảy ra với cụm
3 container khi Redis mất kết nối 30 giây? Trả lời theo đúng thứ tự sự kiện.

1. **Giây 0:** Redis mất kết nối (restart, mạng chập chờn).
2. **Giây 0–10:** cả 3 container gọi Redis trong health check đều lỗi → health
   check trả 503 ở **cả 3** cùng lúc (chúng cùng phụ thuộc một Redis).
3. **Sau vài lần fail liên tiếp** (ví dụ `retries: 3`, `interval: 10s`):
   orchestrator coi cả 3 container là **chết** (liveness fail) → kill và restart
   cả 3 cùng lúc. Mọi request đang xử lý dở bị cắt → user thấy 502.
4. Container mới khởi động, health check lại gọi Redis — nếu Redis chưa về thì
   lại fail → **restart loop**. Trong lúc này không có instance nào phục vụ được,
   kể cả các request không cần Redis.
5. **Giây 30:** Redis quay lại. Nhưng cả 3 container đang ở giữa vòng restart,
   phải đợi khởi động xong + qua health check → service down thêm vài chục giây
   nữa. Sự cố 30 giây của Redis thành sự cố toàn hệ thống lâu hơn nhiều.

Khi tách đúng: `/health` không chạm Redis → vẫn 200 → **không container nào bị
restart**. `/ready` trả 503 (`{"status":"not ready","redis":false}`) → load
balancer chỉ **tạm ngừng gửi traffic** vào. Redis về ở giây 30 → `/ready` lại 200
→ traffic chảy lại ngay, không mất thời gian khởi động lại.

---

### Câu 9 — Stateless (CP4)

Chạy `docker compose up --scale agent=3` rồi gọi `/ask` nhiều lần với cùng một
`X-User-Id`. Quan sát `history_length` trong response. Nếu lịch sử được lưu
trong một dict Python thay vì Redis, bạn sẽ thấy con số đó thay đổi thế nào?

Mình chạy 3 container `agent` sau Nginx (round-robin, cổng 8080) và gọi `/ask`
5 lần với `X-User-Id: sv01`. Kết quả thật, kèm container xử lý (đọc từ
`docker compose logs agent`):

| Lượt | Container | `history_length` |
|---|---|---|
| 1 | agent-1 | 0 |
| 2 | agent-1 | 2 |
| 3 | agent-3 | 4 |
| 4 | agent-3 | 6 |
| 5 | agent-2 | 8 |

Request rơi vào cả 3 container khác nhau nhưng `history_length` tăng đều +2 mỗi
lượt (1 message user + 1 message assistant), vì cả 3 cùng đọc/ghi list
`history:sv01` trong một Redis.

Nếu lưu trong dict Python, mỗi container có một dict riêng trong RAM của nó.
Con số sẽ phụ thuộc container nào nhận request, không theo thứ tự lượt hỏi. Với
đúng thứ tự phân phối ở trên, nó sẽ là **0, 2, 0, 2, 0**:
agent-1 thấy 0 rồi 2; agent-3 lần đầu gặp sv01 nên lại là 0, rồi 2; agent-2
cũng lần đầu → 0. Agent "mất trí nhớ" ngẫu nhiên. Tệ hơn, restart hay deploy lại
là mất sạch lịch sử của mọi user.

---

### Câu 10 — Deploy thật (CP5)

Ghi lại **một** lỗi bạn gặp khi deploy lên cloud (build fail, health check
timeout, sai REDIS_URL, app không đọc `$PORT`...): thông báo lỗi là gì, bạn
tìm ra nguyên nhân bằng cách nào, và sửa ra sao?

**Lỗi:** mình định deploy lên Railway bằng CLI. `railway init --name day12-agent`
báo trước tiên:

```
--workspace required in non-interactive mode (multiple workspaces available)
```

Mình chạy `railway whoami --json` thì thấy tài khoản có 2 workspace (một của
team, một cá nhân), nên truyền thêm `--workspace <id cá nhân>`. Lần này lỗi
khác:

```
Your trial has expired. Please select a plan to continue using Railway.
No linked project found. Run railway link to connect to a project
```

**Nguyên nhân:** workspace cá nhân của mình đã dùng hết $5 credit dùng thử từ
trước, nên Railway không cho tạo project mới. Không phải lỗi code, nhưng chặn
hoàn toàn đường deploy đó.

**Cách sửa:** mình không muốn trả phí Hobby hay dùng workspace của team cho bài
cá nhân, nên chuyển sang **Render** (free tier có cả web service lẫn Key Value).
Trước khi deploy mình kiểm tra lại `render.yaml` và đổi service Redis từ
`type: redis` sang `type: keyvalue` (tên mới của Render), cả ở chỗ `fromService`
để `REDIS_URL` được nối tự động. Sau đó tạo Blueprint từ repo GitHub, nhập
`AGENT_API_KEY` trên dashboard. Kết quả: `/health` 200, `/ready` 200
(`"redis": true`) — chứng tỏ `REDIS_URL` từ Key Value đã nối đúng.

Trong lúc chuẩn bị Railway mình cũng sửa một lỗi tiềm ẩn: `railway.toml` có
`startCommand = "uvicorn ... --port $PORT"` sẽ ghi đè `CMD` của Dockerfile.
Lệnh này không có `exec` (uvicorn không phải PID 1 → không nhận SIGTERM trực
tiếp, mất graceful shutdown), và nếu platform chạy nó không qua shell thì `$PORT`
không được thay giá trị. Mình bỏ `startCommand` để dùng
`CMD ["sh", "-c", "exec uvicorn ... --port ${PORT:-8000}"]` của Dockerfile.
