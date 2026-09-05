# ML-хост (ml.{DOMAIN})

Инференс крутится **на отдельной машине** (часто домашний GPU), не в
`docker-compose` стенда. Основной API ходит туда по HTTPS с общим ключом.

## На машине с моделью

```bash
cd ml
# heuristic без torch — для проверки контура; для защиты — segformer + GPU
pip install -r requirements-dev.txt   # или requirements-model.txt
set API_KEY=shared-secret             # PowerShell: $env:API_KEY=...
uvicorn app.main:app --host 0.0.0.0 --port 8001
```

Проброс порта на роутере → DNS A-запись `ml.your.domain` → этот IP.
TLS: локальный Caddy/`cloudflared` или аналог. Без ключа и TLS в интернет
не выставлять: ручка качает тайлы и принимает нагрузку.

## На стенде (backend)

В `.env` рядом с API (см. также `deploy/.env.example`):

```
ML_ENABLED=true
ML_BASE_URL=https://ml.your.domain
ML_API_KEY=shared-secret
ML_TIMEOUT_S=180
```

Миграция: `alembic upgrade head` (ревизия `0016` — таблицы `ml_scans` /
`ml_findings`, колонка `hypotheses.source`, view `kpi.autodetect_precision`).

Проверка:

```bash
curl -H "Authorization: Bearer $TOKEN" https://your.domain/api/v1/ml/health
```

UI: карта → «Сканировать участок»; вкладка «Находки».
