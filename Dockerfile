# ═══════════════════════════════════════════════════════════════════
# CP2 — Containerization (production-ready)
#
#   Stage 1 `builder`: cài dependency vào /install
#   Stage 2 `runtime`: chỉ copy /install + source code, chạy bằng user thường
#
# Build:  docker build -t day12-agent:prod .
# ═══════════════════════════════════════════════════════════════════

# ── Stage 1: builder ────────────────────────────────────────────────
FROM python:3.11-slim AS builder

WORKDIR /build

# Chỉ copy requirements.txt trước → layer pip install được cache,
# sửa code không phải cài lại thư viện
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# ── Stage 2: runtime ────────────────────────────────────────────────
FROM python:3.11-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=8000

# User thường, không có quyền root
RUN useradd --create-home --uid 10001 appuser

WORKDIR /app

# Chỉ lấy KẾT QUẢ cài đặt từ builder, không mang theo pip cache hay build tool
COPY --from=builder /install /usr/local

# Source code copy SAU cùng — thay đổi thường xuyên nhất
COPY --chown=appuser:appuser app ./app
COPY --chown=appuser:appuser utils ./utils

USER appuser

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import os, urllib.request; urllib.request.urlopen('http://127.0.0.1:%s/health' % os.environ.get('PORT', '8000'), timeout=3)" || exit 1

# `exec` để uvicorn thay thế sh làm PID 1 → nhận được SIGTERM trực tiếp
CMD ["sh", "-c", "exec uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}"]
