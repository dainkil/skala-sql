-- =====================================================================
-- lab4/tuning/mv_customer_rev.sql
--   고객별 R/F/M 원지표 사전집계 MV (Q05 RFM 가속)
--   체크리스트의 user_stats(user_id, total_orders, last_order_date) 전략과 동일.
--   배포 원본(00_schema.sql) 미수정 — tuning 별도 파일.
--   실행: psql skala_db4 -v ON_ERROR_STOP=1 -f lab4/tuning/mv_customer_rev.sql
--
--   ※ Recency 는 last_order_ts(불변, 과거)만 저장. 경과일(recency_days)은
--     조회 시 CURRENT_DATE 로 계산 → 매일 자동으로 최신. NTILE 등급도 조회 시 부여.
--   ※ 대안: 트리거로 주문 발생 시 증분 갱신도 가능(여기선 MV + 15:00 REFRESH).
-- =====================================================================

CREATE MATERIALIZED VIEW IF NOT EXISTS ecom.mv_customer_rev AS
SELECT o.customer_id,
       MAX(o.order_ts)            AS last_order_ts,
       COUNT(DISTINCT o.order_id) AS frequency,
       SUM(oi.line_total)         AS monetary
FROM ecom.orders o
JOIN ecom.order_items oi ON oi.order_id = o.order_id
WHERE o.order_status IN ('paid', 'shipped', 'delivered')
GROUP BY o.customer_id;

-- CONCURRENTLY 갱신 전제(UNIQUE)
CREATE UNIQUE INDEX IF NOT EXISTS ux_mv_customer_rev
    ON ecom.mv_customer_rev (customer_id);

\echo '### mv_customer_rev 적재 확인 ###'
SELECT count(*) AS customers, max(monetary) AS top_monetary FROM ecom.mv_customer_rev;
