-- =====================================================================
-- lab4/tuning/mv_category_daily.sql
--   카테고리×일 매출/수량 사전집계 MV (Q03 최근 N일 카테고리 Top-N 가속)
--   통계 테이블 전략: order_items(18,700행) 조인을 매번 하지 않도록 사전집계.
--   배포 원본(00_schema.sql) 미수정 — tuning 별도 파일.
--   실행: psql skala_db4 -v ON_ERROR_STOP=1 -f lab4/tuning/mv_category_daily.sql
-- =====================================================================

-- CREATE MATERIALIZED VIEW 는 즉시 적재된다(WITH NO DATA 아님).
CREATE MATERIALIZED VIEW IF NOT EXISTS ecom.mv_category_daily AS
SELECT date_trunc('day', o.order_ts) AS day,
       p.category_id,
       SUM(oi.line_total)            AS revenue,
       SUM(oi.qty)                   AS units
FROM ecom.orders o
JOIN ecom.order_items oi ON oi.order_id = o.order_id
JOIN ecom.products    p  ON p.product_id = oi.product_id
WHERE o.order_status IN ('paid', 'shipped', 'delivered')
GROUP BY 1, 2;

-- CONCURRENTLY 갱신 전제(UNIQUE) + day 범위 필터용 인덱스
CREATE UNIQUE INDEX IF NOT EXISTS ux_mv_category_daily
    ON ecom.mv_category_daily (day, category_id);
CREATE INDEX IF NOT EXISTS idx_mv_category_daily_day
    ON ecom.mv_category_daily (day);

\echo '### mv_category_daily 적재 확인 ###'
SELECT count(*) AS rows,
       count(DISTINCT category_id) AS categories,
       min(day) AS first_day, max(day) AS last_day
FROM ecom.mv_category_daily;
