# Thông Tin Deploy — Checkpoint 5

> Điền file này sau khi deploy xong. `pytest tests/test_cp5.py` đọc file này
> để tìm địa chỉ service của bạn và gọi thử.
>
> **Chỉ ghi TÊN biến môi trường, tuyệt đối không dán giá trị API key vào đây.**
> Repo này công khai — dán khóa vào là mất khóa.

## Thông Tin Học Viên

| Mục | Nội dung |
|-----|----------|
| Họ và tên | Nguyễn Sơn Giang |
| Mã học viên | 2A202602747 |
| Repo | https://github.com/songiangvn/K4-L3A-DAY12-NguyenSonGiang-2A202602747-CloudServicesAndDeployment |

## Service

| Mục | Nội dung |
|-----|----------|
| Public URL | https://day12-agent-nbcr.onrender.com |
| Platform | Render (Blueprint từ `render.yaml`, runtime Docker, plan free) |
| Ngày deploy | 2026-09-28 |

## Biến Môi Trường Đã Set Trên Cloud

Ghi tên biến và **nguồn giá trị**, không ghi giá trị:

| Biến | Đã set | Ghi chú |
|------|--------|---------|
| `PORT` | ✅ | Render tự gán, Dockerfile đọc qua `${PORT:-8000}` |
| `AGENT_API_KEY` | ✅ | nhập tay trên dashboard Render (`sync: false`), không nằm trong repo; khác khóa dùng ở local |
| `REDIS_URL` | ✅ | Render Key Value `day12-redis`, nối tự động qua `fromService` (connectionString) |
| `RATE_LIMIT_PER_MINUTE` | ✅ | 10 (khai báo trong `render.yaml`) |
| `MONTHLY_BUDGET_USD` | ✅ | 10.0 (khai báo trong `render.yaml`) |
| `LOG_LEVEL` | ✅ | INFO (khai báo trong `render.yaml`) |

## Lệnh Kiểm Tra

```bash
URL=https://day12-agent-nbcr.onrender.com

# 1. Liveness — mong đợi 200 {"status":"ok"}
curl -i $URL/health

# 2. Readiness — mong đợi 200 {"status":"ready"} (đã nối được Redis)
curl -i $URL/ready

# 3. Không có API key — mong đợi 401
curl -i -X POST $URL/ask \
  -H "Content-Type: application/json" \
  -d '{"question":"Hello"}'

# 4. Có API key — mong đợi 200 kèm câu trả lời
curl -i -X POST $URL/ask \
  -H "Content-Type: application/json" \
  -H "X-API-Key: $AGENT_API_KEY" \
  -H "X-User-Id: sv-test" \
  -d '{"question":"Deploy là gì?"}'

# 5. Rate limit — gọi 15 lần, những lần cuối phải trả 429
for i in $(seq 1 15); do
  curl -s -o /dev/null -w "%{http_code} " -X POST $URL/ask \
    -H "Content-Type: application/json" \
    -H "X-API-Key: $AGENT_API_KEY" \
    -H "X-User-Id: sv-test" \
    -d '{"question":"test"}'
done; echo
```

## Kết Quả Chạy Thật

Chạy ngày 2026-09-28 (~11:50 UTC), header HTTP đã lược bớt:

```
# 1. /health
HTTP/1.1 200 OK
x-render-origin-server: uvicorn
{"status":"ok","service":"day12-agent","version":"1.0.0"}

# 2. /ready
HTTP/1.1 200 OK
{"status":"ready","redis":true}

# 3. /ask không có key
HTTP/1.1 401 Unauthorized
{"detail":"invalid or missing API key"}

# 4. /ask có key (X-User-Id: sv-demo)
HTTP 200
{"answer":"Câu hỏi hay. Deploy là gì thường được giải quyết bằng cách chuẩn hóa môi trường chạy: cùng một image chạy giống nhau ở laptop và trên cloud.","user_id":"sv-demo","history_length":0,"cost_usd":2.145e-05,"tokens":{"in":3,"out":35}}

# 5. Rate limit — 15 lần liên tiếp
200 200 200 200 200 200 200 200 200 200 429 429 429 429 429
```

## Ảnh Chụp Màn Hình

Đặt ảnh trong thư mục `screenshots/`:

- `screenshots/dashboard.png` — trang quản lý service trên Render
- `screenshots/health.png` — kết quả gọi `/health` từ trình duyệt
