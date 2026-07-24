-- =====================================================================
-- Q09. 쿠폰 사용 영향 — 쿠폰 쓴 주문 vs 안 쓴 주문의 평균 주문금액(AOV) 비교   [튜닝 후: 매출/건수 분리]
--   - 쿠폰 사용여부: orders.coupon_code IS NULL (NULL=미사용)
--   - AOV = 그룹 매출합 / 그룹 주문수, 매출 = SUM(order_items.line_total)
--   - 매출 인정 상태(paid/shipped/delivered)만 집계
-- 실행: psql skala_db4 -v ON_ERROR_STOP=1 -f lab4/queries/Q09.sql
--
--   ※ 쿠폰 사용여부 분기는 CASE WHEN ... IS NULL (= NULL 금지). AOV 분모는 NULLIF 로 0 방지.
--
-- ---------------------------------------------------------------------
-- [튜닝 기록]  (근거: captures/Q09_before.txt, Q09_after.txt, Q09_joins.txt)
--
-- 병목(튜닝 전): order_items(18,700) ⋈ orders Hash Join(14,522행) 위에
--   COUNT(DISTINCT order_id) 를 위한 Sort 14,522행(1030kB) 이 얹힘 → 이 Sort 가 ~9ms(지배적).
--   · 조인 자체는 ~6ms. 조인 3종: HJ join cost649/Buf260 < SMJ 1113/315 < NLJ 3019/Buf16176(62배).
--   · Execution Time ≈ 16.0ms
--
-- 처방(집계 최적화 — 매출/건수 분리, Q02 와 동일 패턴):
--   COUNT(DISTINCT) 는 조인이 주문을 품목 수만큼 fan-out 시키기 때문에 필요했던 것.
--   · 매출(rev): 조인 후 곧바로 쿠폰 2그룹으로 HashAggregate(SUM) → order_id 그룹핑·Sort 불필요
--   · 주문수(cnt): orders '단독' 집계(조인 없이 COUNT(*)) → DISTINCT 도 Sort 도 없음
--   · 2그룹 rev ⋈ 2그룹 cnt (초경량)
--   · Execution Time ≈ 6.95ms (약 57%↓), 결과 완전 일치(미사용 641.56 / 사용 1837.42)
--   · 전제 검증: 품목 없는 매출상태 주문 0건 → orders 단독 COUNT(*) == 조인 COUNT(DISTINCT)
--   · 인사이트: 쿠폰 사용 주문 AOV 가 미사용의 약 2.9배(큰 장바구니에 쿠폰 사용)
-- ---------------------------------------------------------------------
WITH rev AS (                   -- 매출: 조인 후 쿠폰 2그룹으로 바로 SUM (COUNT DISTINCT/Sort 없음)
    SELECT (o.coupon_code IS NULL) AS no_coupon,
           SUM(oi.line_total)      AS revenue
    FROM ecom.orders AS o
    JOIN ecom.order_items AS oi ON oi.order_id = o.order_id
    WHERE o.order_status IN ('paid', 'shipped', 'delivered')
    GROUP BY (o.coupon_code IS NULL)
),
cnt AS (                        -- 주문수: orders 단독 집계 (조인 불필요 → DISTINCT 불필요)
    SELECT (coupon_code IS NULL) AS no_coupon,
           COUNT(*)              AS order_count
    FROM ecom.orders
    WHERE order_status IN ('paid', 'shipped', 'delivered')
    GROUP BY (coupon_code IS NULL)
)
SELECT
    CASE WHEN r.no_coupon THEN '미사용' ELSE '사용' END AS coupon_used,
    c.order_count,
    r.revenue                                          AS total_revenue,
    ROUND(r.revenue / NULLIF(c.order_count, 0), 2)     AS aov
FROM rev AS r
JOIN cnt AS c ON c.no_coupon = r.no_coupon
ORDER BY coupon_used;

-- [튜닝 전 · 조인 후 COUNT(DISTINCT) 버전]
-- SELECT CASE WHEN o.coupon_code IS NULL THEN '미사용' ELSE '사용' END AS coupon_used,
--        COUNT(DISTINCT o.order_id) AS order_count, SUM(oi.line_total) AS total_revenue,
--        ROUND(SUM(oi.line_total)/NULLIF(COUNT(DISTINCT o.order_id),0),2) AS aov
-- FROM ecom.orders o JOIN ecom.order_items oi ON oi.order_id = o.order_id
-- WHERE o.order_status IN ('paid','shipped','delivered')
-- GROUP BY CASE WHEN o.coupon_code IS NULL THEN '미사용' ELSE '사용' END
-- ORDER BY coupon_used;
