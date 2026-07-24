-- =====================================================================
-- lab4/tuning/mv_product_revenue.sql
--   제품별 누적매출 사전집계 MV (Q04 제품 매출 RANK Top-N 가속)
--   통계 테이블 전략: order_items(18,700행) 조인+집계를 매번 하지 않도록 사전집계.
--   배포 원본(00_schema.sql) 미수정 — tuning 별도 파일.
--   실행: psql skala_db4 -v ON_ERROR_STOP=1 -f lab4/tuning/mv_product_revenue.sql
-- =====================================================================

CREATE MATERIALIZED VIEW IF NOT EXISTS ecom.mv_product_revenue AS
SELECT oi.product_id,
       SUM(oi.line_total) AS revenue,
       SUM(oi.qty)        AS units
FROM ecom.orders o
JOIN ecom.order_items oi ON oi.order_id = o.order_id
WHERE o.order_status IN ('paid', 'shipped', 'delivered')
GROUP BY oi.product_id;

-- CONCURRENTLY 갱신 전제(UNIQUE) + 순위 정렬용(revenue DESC) 인덱스
CREATE UNIQUE INDEX IF NOT EXISTS ux_mv_product_revenue
    ON ecom.mv_product_revenue (product_id);
CREATE INDEX IF NOT EXISTS idx_mv_product_revenue_rev
    ON ecom.mv_product_revenue (revenue DESC);

\echo '### mv_product_revenue 적재 확인 ###'
SELECT count(*) AS rows, max(revenue) AS top_revenue FROM ecom.mv_product_revenue;
