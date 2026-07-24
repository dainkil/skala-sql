-- =====================================================================
-- Q06. 첫 구매 후 30일 내 재구매율 (repurchase rate within 30 days)   [튜닝 후: 단일 스캔 재작성]
--   - 첫 구매 = 고객별 최초 주문(매출 인정 상태 paid/shipped/delivered)
--   - 재구매 = 같은 고객이 첫 주문 이후 ~ 첫 주문 + 30일 이내에 낸 '다른' 주문
--   - 재구매율 = 재구매 고객수 / 첫구매 고객수
-- 실행: psql skala_db4 -v ON_ERROR_STOP=1 -f lab4/queries/Q06.sql
--
--   ※ '구매'는 매출 인정 상태 3종만 집계(cancelled/refunded 제외).
--   ※ 경계: 첫 주문 '초과'(> first) ~ '30일 이하'(<= first+30d). 첫 주문 자신은 제외.
--
-- ---------------------------------------------------------------------
-- [튜닝 기록]  (근거: captures/Q06_before.txt, Q06_after.txt, Q06_joins.txt)
--
-- 병목(튜닝 전): orders 를 '두 번' Seq Scan + self-join
--   · ① first_order(고객별 MIN) 집계용 스캔, ② repurchase 의 o2 용 스캔 (각 71 buffers)
--   · 30일 window 가 인덱스 조건이 아니라 Hash Join 의 Join Filter → customer_id 매치 후
--     3,975행 사후 제거. idx_orders_status 는 상태 3종 78% 통과(저선택도)라 미사용.
--   · 조인 3종: HJ cost442/Buf142 < SMJ 1019/Buf142 < NLJ 1607/Buf5919(41배!) → 플래너 HJ.
--   · Execution Time ≈ 8.55ms, Buffers 142
--
-- 처방(집계 최적화 — MV 없이 쿼리 재작성): 이 문항은 order_items 조인이 없어 원래 가벼움.
--   MV(통계 테이블)보다 '중복 스캔·self-join 제거'가 본질적 개선.
--   · MIN(order_ts) OVER (PARTITION BY customer_id) 로 첫주문일을 각 행에 부여 → orders '한 번'만 스캔
--   · self-join/Hash Join 소멸, 고객별 GROUP BY + bool_or 로 30일 내 재구매 판정
--   · Execution Time ≈ 5.98ms (약 30%↓), Buffers 142→74(스캔 2회→1회), 결과 완전 일치(49.91%)
--   · 남은 비용 = PARTITION BY 용 Sort(5,336행, 359kB quicksort) — 새 병목이자 하한
--   · 이점: 새 객체·갱신 부담 없음, '항상 최신'(MV stale 문제 없음)
--   · (참고) 고객별 (첫·둘째주문) MV 로는 0.99ms(~88%)까지 가능하나, 이미 <10ms 리포트에
--     5번째 MV+갱신을 더할 만큼의 이득은 아니라 재작성 채택. → MV 를 '항상 쓰지는 않는' 판단 사례.
-- ---------------------------------------------------------------------
WITH orders_flagged AS (        -- orders 1회 스캔: 각 주문에 그 고객의 첫 주문일을 부여
    SELECT o.customer_id,
           o.order_ts,
           MIN(o.order_ts) OVER (PARTITION BY o.customer_id) AS first_order_ts
    FROM ecom.orders o
    WHERE o.order_status IN ('paid', 'shipped', 'delivered')
),
per_customer AS (               -- 고객별: 첫 주문 후 30일 내 '다른' 주문 존재 여부
    SELECT customer_id,
           bool_or(order_ts >  first_order_ts
               AND order_ts <= first_order_ts + interval '30 days') AS repurchased_30d
    FROM orders_flagged
    GROUP BY customer_id
)
SELECT
    count(*)                                            AS first_time_customers,
    count(*) FILTER (WHERE repurchased_30d)             AS repurchased_customers,
    ROUND(100.0 * count(*) FILTER (WHERE repurchased_30d)
                / NULLIF(count(*), 0), 2)               AS repurchase_rate_pct
FROM per_customer;

-- [튜닝 전 · 원본 self-join 버전]
-- WITH first_order AS (
--     SELECT o.customer_id, MIN(o.order_ts) AS first_order_ts
--     FROM ecom.orders o WHERE o.order_status IN ('paid','shipped','delivered')
--     GROUP BY o.customer_id),
-- repurchase AS (
--     SELECT DISTINCT f.customer_id
--     FROM first_order f
--     JOIN ecom.orders o2 ON o2.customer_id = f.customer_id
--      AND o2.order_status IN ('paid','shipped','delivered')
--      AND o2.order_ts >  f.first_order_ts
--      AND o2.order_ts <= f.first_order_ts + interval '30 days')
-- SELECT (SELECT count(*) FROM first_order) AS first_time_customers,
--        (SELECT count(*) FROM repurchase)  AS repurchased_customers,
--        ROUND(100.0*(SELECT count(*) FROM repurchase)
--                   /NULLIF((SELECT count(*) FROM first_order),0),2) AS repurchase_rate_pct;
