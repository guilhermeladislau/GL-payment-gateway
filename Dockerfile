FROM python:3.12-slim AS base
WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

FROM base AS production
WORKDIR /app
COPY src/ ./src/

USER nobody
EXPOSE 3000

HEALTHCHECK --interval=10s --timeout=3s --start-period=15s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:3000/health/live')"

CMD ["uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "3000"]
