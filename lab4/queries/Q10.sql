-- =====================================================================
-- Q10. 상위 1% 고객의 최근 60일 매출   [튜닝 후: 랭킹을 고객 MV 로 대체]
--   - 상위 1% 판별: 고객별 '전체 기간' 누적매출 기준 PERCENT_RANK() >= 0.99 (우량고객)
--   - 조회: 그 고객들의 '최근 60일' 매출(revenue_60d) — 최근 주문 없으면 0
--   - 매출 = SUM(order_items.line_total), 매출 인정 상태(paid/shipped/delivered)
-- 실행: psql skala_db4 -v ON_ERROR_STOP=1 -f lab4/queries/Q10.sql
--
--   ※ 가정: '상위 1%'는 누적매출 기준(핵심 고객). 최근 60일 매출은 그들의 최근 활동 지표.
--   ※ 기간 필터는 order_ts 에 함수를 씌우지 않음(now() - interval '60 days' 범위 비교).
--   ※ 최근 주문 없는 우량고객도 보이도록 LEFT JOIN + COALESCE 0.
--
-- ---------------------------------------------------------------------
-- [튜닝 기록]  (근거: captures/Q10_before.txt, Q10_after.txt, Q10_joins.txt)
--
-- 병목(튜닝 전): customer_total 이 order_items(18,700) ⋈ orders 를 '전부' 집계해
--   2,246 고객 누적매출을 만든 뒤(~9.7ms) Sort+PERCENT_RANK 로 상위 1%(23명)를 뽑음.
--   상위 1% 판별을 위해 전 고객 대전집계가 필요했던 게 핵심 비용.
--   · 조인 3종: HJ join cost649/Buf252 < SMJ 1113/310 < NLJ 3019/Buf16168(62배).
--   · Execution Time ≈ 14.3ms, Buffers 517
--
-- 처방(통계 테이블 재사용 — Q05 의 mv_customer_rev 를 그대로 활용):
--   mv_customer_rev.monetary = 고객 누적매출 = customer_total.total_revenue 와 동일.
--   · 랭킹을 MV(2,246행) 읽기로 대체 → order_items ⋈ orders 대전집계가 통째로 사라짐
--   · PERCENT_RANK 는 MV 2,246행에만 적용, 상위 1%(23명) 산출
--   · revenue_60d 만 실데이터(orders 60일 ⋈ order_items) 조인 → 항상 최신
--   · Execution Time ≈ 7.06ms (약 51%↓), Buffers 517→282, 결과 완전 일치(mismatch 0)
--   · 남은 비용 = revenue_60d 의 order_items 스캔(line_total 필요라 불가피, 하한)
-- ⚠️ 신선도: 랭킹 기준(누적매출)은 MV 스냅샷(REFRESH 15:00) 기준. 최근 60일 매출은
--    실데이터라 항상 최신 → '누구를 우량으로 보나'는 하루 단위, '얼마 썼나'는 실시간.
--    하나의 MV(mv_customer_rev)가 Q05(RFM)와 Q10(상위1%) 두 문항을 함께 가속.
-- ---------------------------------------------------------------------
WITH ranked AS (                -- 고객 MV 의 누적매출로 백분위 순위
    SELECT customer_id,
           monetary AS total_revenue,
           PERCENT_RANK() OVER (ORDER BY monetary) AS pr
    FROM ecom.mv_customer_rev	
),
top1 AS (                       -- 누적매출 상위 1%
    SELECT customer_id, total_revenue
    FROM ranked
    WHERE pr >= 0.99
)
SELECT
    t.customer_id,
    t.total_revenue,
    COALESCE(SUM(oi.line_total), 0) AS revenue_60d
FROM top1 AS t
LEFT JOIN ecom.orders AS o
       ON o.customer_id = t.customer_id
      AND o.order_status IN ('paid', 'shipped', 'delivered')
      AND o.order_ts >= now() - interval '60 days'
LEFT JOIN ecom.order_items AS oi ON oi.order_id = o.order_id
GROUP BY t.customer_id, t.total_revenue
ORDER BY t.total_revenue DESC;

-- [튜닝 전 · customer_total 대전집계 버전]
-- WITH customer_total AS (
--     SELECT o.customer_id, SUM(oi.line_total) AS total_revenue
--     FROM ecom.orders o JOIN ecom.order_items oi ON oi.order_id=o.order_id
--     WHERE o.order_status IN ('paid','shipped','delivered') GROUP BY o.customer_id),
-- ranked AS (SELECT customer_id, total_revenue,
--            PERCENT_RANK() OVER (ORDER BY total_revenue) AS pr FROM customer_total),
-- top1 AS (SELECT customer_id, total_revenue FROM ranked WHERE pr >= 0.99)
-- SELECT t.customer_id, t.total_revenue, COALESCE(SUM(oi.line_total),0) AS revenue_60d
-- FROM top1 t
-- LEFT JOIN ecom.orders o ON o.customer_id=t.customer_id
--    AND o.order_status IN ('paid','shipped','delivered') AND o.order_ts >= now() - interval '60 days'
-- LEFT JOIN ecom.order_items oi ON oi.order_id=o.order_id
-- GROUP BY t.customer_id, t.total_revenue ORDER BY t.total_revenue DESC;
