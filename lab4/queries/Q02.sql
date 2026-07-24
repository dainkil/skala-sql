-- =====================================================================
-- Q02. 월별 주문 건수 / 매출 / 주문당 평균금액(AOV)   [튜닝 후: MV 활용]
--   - 매출 인정 상태: paid / shipped / delivered
--   - 매출 = SUM(line_total), 건수 = 주문(order_id) 기준, AOV = 매출/건수
--   - AOV 분모 0 방지: ecom.safe_div (0/NULL → NULL)
-- 실행: psql skala_db4 -v ON_ERROR_STOP=1 -f lab4/queries/Q02.sql
--
-- ---------------------------------------------------------------------
-- [튜닝 기록]  (근거: captures/Q02_before.txt, Q02_after.txt, Q02_joins.txt)
--
-- 병목(튜닝 전, 단순 조인): orders ⋈ order_items → GROUP BY month + COUNT(DISTINCT)
--   · COUNT(DISTINCT) 위해 (month, order_id)로 14,522행 [Sort 952kB]
--   · order_items 18,700행 전체 조인 스캔
--   · Execution Time ≈ 12.16ms, Buffers 258
--
-- 처방1(MV): 매출은 mv_daily_gmv 롤업, 건수는 orders 단독 집계로 분리
--   · order_items 조인 제거(→ MV 124행만 읽음), COUNT(DISTINCT)용 대형 Sort 제거
--   · 사전확인: 매출상태 주문 중 order_items 없는 건 0 → 분리해도 결과 동일
--   · Execution Time ≈ 4.69ms, Buffers 72  (약 61%↓, 결과 완전 일치)
-- 처방2(인덱스): orders 카운트를 부분 커버링 인덱스로 Index-Only Scan 전환
--   · idx_orders_rev_ts = orders(order_ts) WHERE status IN(3)  (tuning/indexes.sql)
--   · Seq Scan → Index Only Scan (Heap Fetches 0) → Execution Time ≈ 2.07ms
--   · 최종: 12.16 → 4.69 → 2.07ms. 건수는 실시간 유지(stale 아님).
--
-- ⚠️ 트레이드오프: MV는 자동 갱신 안 됨(REFRESH 필요). 매출(MV·stale)과
--    건수(orders·실시간)를 섞으므로, 미갱신 시 두 값이 어긋날 수 있음.
--    일 단위 신선도를 허용하는 월간 리포트에 적합.
-- ---------------------------------------------------------------------
WITH rev AS (   -- 월별 매출: MV 일별 GMV를 월로 롤업 (order_items 조인 회피)
    SELECT date_trunc('month', day) AS month,
           SUM(gmv)                 AS revenue
    FROM ecom.mv_daily_gmv
    GROUP BY date_trunc('month', day)
),
cnt AS (        -- 월별 주문건수: orders 만 (조인·DISTINCT 불필요)
    SELECT date_trunc('month', order_ts) AS month,
           COUNT(*)                       AS order_count
    FROM ecom.orders
    WHERE order_status IN ('paid', 'shipped', 'delivered')
    GROUP BY date_trunc('month', order_ts)
)
SELECT
    c.month,
    c.order_count,
    r.revenue,
    ROUND(ecom.safe_div(r.revenue, c.order_count), 2) AS aov
FROM cnt AS c
JOIN rev AS r ON r.month = c.month
ORDER BY c.month;

-- [튜닝 전 · 단순 조인 버전 — 최신값이 필요할 때]
-- SELECT date_trunc('month', o.order_ts) AS month,
--        COUNT(DISTINCT o.order_id)      AS order_count,
--        SUM(oi.line_total)              AS revenue,
--        ROUND(ecom.safe_div(SUM(oi.line_total),
--                            COUNT(DISTINCT o.order_id)), 2) AS aov
-- FROM ecom.orders o JOIN ecom.order_items oi ON oi.order_id = o.order_id
-- WHERE o.order_status IN ('paid','shipped','delivered')
-- GROUP BY date_trunc('month', o.order_ts)
-- ORDER BY month;
