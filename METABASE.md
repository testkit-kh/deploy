# Дашборд (Metabase) — провижининг стенда

Код бэкенда и seed-скрипт уже готовы; здесь только то, что делает деплой.
Схема: `postgres` → вью `kpi.*` → роль `metabase_ro` → Metabase → signed iframe
в `/dashboard` фронта. Metabase отдаётся Caddy по пути `/metabase` того же
домена, поэтому iframe получается same-origin.

## 1. Переменные

Дописать в `.env` на сервере блок `--- Metabase ---` из `.env.example`.
`METABASE_EMBEDDING_SECRET_KEY` — общий секрет бэкенда и Metabase:

```bash
openssl rand -hex 32
```

## 2. Роль и app-БД

Если том `postgres_data` создаётся с нуля — `postgres/init/01-metabase.sh`
отработает сам. **На уже поднятом стенде init-скрипты не запускаются**, роли
надо создать руками:

```bash
docker compose exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" <<'SQL'
CREATE ROLE metabase_ro LOGIN PASSWORD 'СЮДА_METABASE_RO_PASSWORD';
CREATE ROLE metabase_app LOGIN PASSWORD 'СЮДА_METABASE_DB_PASSWORD';
CREATE DATABASE metabase_app OWNER metabase_app;
SQL
```

Гранты на схему `kpi` и отзыв `public` выдаёт миграция `0006`, но условно —
только если роль уже существует. Роль создана после миграции → прогнать
блок грантов ещё раз:

```bash
docker compose exec -T backend alembic downgrade 0005 && docker compose exec -T backend alembic upgrade head
```

Или, без переката вью, тот же GRANT-блок руками (см. `0006_kpi_views.py`).

## 3. Поднять Metabase

```bash
docker compose pull && docker compose up -d
```

Первый старт накатывает свои миграции в `metabase_app` — до трёх минут.
Дальше открыть `https://<домен>/metabase`, пройти онбординг и завести
админа: seed-скрипт логинится его почтой и паролем.

## 4. Провижининг карточек

С машины, где лежит backend (скрипту нужен `httpx`):

```bash
python backend/scripts/metabase_seed.py \
  --url https://<домен>/metabase \
  --email admin@example.ru --password '...' \
  --db-host postgres --db-name eco_project \
  --db-password "$METABASE_RO_PASSWORD"
```

Идемпотентен: повторный прогон обновляет карточки, а не плодит копии.
В конце печатает номера трёх дашбордов.

## 5. Замкнуть

Номера из шага 4 — в `.env` (`METABASE_DASHBOARD_FUNNEL`, `_OOPT`, `_IMPACT`),
затем `docker compose up -d backend`. Проверка:

```bash
curl -H "Authorization: Bearer <staff-токен>" https://<домен>/api/v1/analytics/embed/funnel
```

Должен вернуться `{url, expires_at}`. До провижининга та же ручка отдаёт 503 —
это штатно, остальное приложение от этого не зависит.

## Изоляция

`organization_id` зашит в подписанный токен как **locked**-параметр: ООПТ не
видит чужие цифры даже подменой query. `metabase_ro` читает только `kpi.*`;
`users`, `analytics_events`, `parental_consents` → `permission denied`.
