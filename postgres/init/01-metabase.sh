#!/bin/bash
# Провижининг BI-части кластера: read-only роль для Metabase и отдельная
# app-БД под сам Metabase.
#
# ВАЖНО: docker-entrypoint-initdb.d выполняется только при инициализации
# ПУСТОГО тома postgres_data. На уже поднятом стенде выполнить руками —
# см. deploy/METABASE.md.
set -euo pipefail

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-SQL
	-- Роль, которой Metabase ходит в данные. Гранты на схему kpi выдаёт
	-- миграция 0006 (она же отзывает доступ к public).
	DO \$\$
	BEGIN
	    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'metabase_ro') THEN
	        CREATE ROLE metabase_ro LOGIN PASSWORD '${METABASE_RO_PASSWORD}';
	    ELSE
	        ALTER ROLE metabase_ro LOGIN PASSWORD '${METABASE_RO_PASSWORD}';
	    END IF;
	END
	\$\$;

	-- Хозяйственная БД самого Metabase (вопросы, дашборды, пользователи).
	-- Отдельный владелец: в данные проекта он не ходит.
	DO \$\$
	BEGIN
	    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '${METABASE_DB_USER}') THEN
	        CREATE ROLE ${METABASE_DB_USER} LOGIN PASSWORD '${METABASE_DB_PASSWORD}';
	    END IF;
	END
	\$\$;
SQL

# CREATE DATABASE вне транзакции, поэтому отдельным вызовом и с проверкой.
if ! psql -tAc "SELECT 1 FROM pg_database WHERE datname = '${METABASE_DB_NAME}'" \
	--username "$POSTGRES_USER" --dbname "$POSTGRES_DB" | grep -q 1; then
	psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
		-c "CREATE DATABASE ${METABASE_DB_NAME} OWNER ${METABASE_DB_USER}"
fi
