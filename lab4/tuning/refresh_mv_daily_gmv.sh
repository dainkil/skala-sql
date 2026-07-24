#!/usr/bin/env bash
# =====================================================================
# lab4/tuning/refresh_mv_daily_gmv.sh
#   리포트용 MV 무중단 갱신 스크립트 (스케줄러가 호출할 대상)
#   - 대상: mv_daily_gmv (Q02), mv_category_daily (Q03), mv_product_revenue (Q04), mv_customer_rev (Q05)
#   - REFRESH ... CONCURRENTLY (각 MV 의 UNIQUE 인덱스 필요)
#   - 갱신 전후 타임스탬프와 최신 day 를 로그로 남김
#
#   수동 실행 : bash lab4/tuning/refresh_mv_daily_gmv.sh
#   스케줄    : 매일 15:00 (launchd / cron) → 이 스크립트 실행. README 참고.
# =====================================================================
set -euo pipefail

DB="${SKALA_DB:-skala_db4}"

for mv in mv_daily_gmv mv_category_daily mv_product_revenue mv_customer_rev; do
    echo "[$(date '+%F %T')] REFRESH CONCURRENTLY ecom.${mv} 시작 (db=${DB})"
    psql -v ON_ERROR_STOP=1 "${DB}" \
        -c "REFRESH MATERIALIZED VIEW CONCURRENTLY ecom.${mv};"
    rows="$(psql -qAt "${DB}" -c "SELECT count(*) FROM ecom.${mv};")"
    echo "[$(date '+%F %T')] ${mv} 완료. rows = ${rows}"
done
