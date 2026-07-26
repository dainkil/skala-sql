-- #####################################################################
-- # lab4 / E-Commerce 분석 — 전체 쿼리 모음 (Q01 ~ Q11)
-- #   DB: skala_db4   Schema: ecom
-- #   각 문항을 [튜닝 전] / [튜닝 후] 두 버전으로 나란히 실행해
-- #   결과 일치 + 성능 개선을 한 파일에서 확인한다.
-- #   ※ Q01·Q07·Q11 은 튜닝이 곧 '컬럼/함수 정리'라 전/후 컬럼이 다르다(그 차이가 곧 개선점).
-- #
-- #   실행(psql)  : psql skala_db4 -v ON_ERROR_STOP=1 -f lab4/queries/ALL.sql
-- #   실행(DBeaver): 이 파일을 열고 "Execute SQL Script"(Alt+X)로 전체 실행.
-- #   ※ 구간 라벨은 psql 전용 \echo 대신 SELECT '...' 문으로 출력 → 두 도구 공용.
-- #   개별 문항·EXPLAIN 근거는 lab4/queries/Q##.sql, lab4/captures/ 참고.
-- #
-- # ── 공통 전제 ───────────────────────────────────────────────────────
-- #   · 매출 = SUM(order_items.line_total)  (주문 시점 스냅샷 가격)
-- #   · 매출 인정 상태 = paid / shipped / delivered  (cancelled/refunded/created 제외)
-- #   · 기간 필터는 orders.order_ts 에 함수를 씌우지 않음(범위 비교 → 인덱스 여지 유지)
-- #   · 분모 0 방지: ecom.safe_div(sql, 0/NULL→NULL) 또는 NULLIF
-- #
-- # ── [튜닝 전]/[튜닝 후] 요약 (Execution Time, 개선 근거는 captures/) ──
-- #   Q01  8.36 → 6.4ms   불필요 COUNT(DISTINCT) 제거(Sort 소멸)
-- #   Q02  12.16 → 2.07ms MV 롤업 + 부분 커버링 인덱스(Index-Only)
-- #   Q03  12.35 → 1.11ms 카테고리×일 사전집계 MV
-- #   Q04  10.76 → 0.55ms 제품 누적매출 MV
-- #   Q05  17.85 → 5.54ms 고객 R/F/M(최근성·빈도·금액) MV 사전집계
-- #   Q06  8.55 → 5.98ms  중복 스캔·self-join 제거(윈도우 1회 스캔)
-- #   Q07  0.385ms        불필요 컬럼(product_name·active) 제거 → 필요한 컬럼만; 인덱스/조인은 이미 최적
-- #   Q08  1.94 → 0.79ms  집계-후-조인(리뷰 먼저 축소)
-- #   Q09  16.0 → 6.95ms  매출/건수 분리(COUNT DISTINCT Sort 제거)
-- #   Q10  14.3 → 7.06ms  랭킹을 고객 MV(mv_customer_rev) 재사용
-- #   Q11  4.10 → 1.28ms  safe_div(sql, 인라인) 채택 / 필요한 컬럼만
-- #####################################################################

SET search_path = ecom, public;


-- #####################################################################
-- # 0) 튜닝 사전객체  — [튜닝 후] 쿼리가 의존하는 인덱스/MV
-- #    (배포 원본 00_schema.sql 미수정. 원본은 lab4/tuning/*.sql)
-- #    CREATE ... IF NOT EXISTS 라 재실행 안전. MV 는 생성 시 즉시 적재된다.
-- #    ※ 이 섹션을 건너뛰면 Q02·Q03·Q04·Q05·Q10 의 [튜닝 후] 가 실패한다.
-- #####################################################################
SELECT '### [0] 튜닝 사전객체 생성 (인덱스 + MV 3종) ###' AS "구분";

-- [Q02] orders 매출건수용 부분 커버링 인덱스 → Index Only Scan (Heap Fetches 0)
CREATE INDEX IF NOT EXISTS idx_orders_rev_ts
    ON ecom.orders (order_ts)
    WHERE order_status IN ('paid', 'shipped', 'delivered');

-- [Q03] 카테고리×일 매출/수량 사전집계 MV
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
CREATE UNIQUE INDEX IF NOT EXISTS ux_mv_category_daily
    ON ecom.mv_category_daily (day, category_id);
CREATE INDEX IF NOT EXISTS idx_mv_category_daily_day
    ON ecom.mv_category_daily (day);

-- [Q04] 제품별 누적매출 사전집계 MV
CREATE MATERIALIZED VIEW IF NOT EXISTS ecom.mv_product_revenue AS
SELECT oi.product_id,
       SUM(oi.line_total) AS revenue,
       SUM(oi.qty)        AS units
FROM ecom.orders o
JOIN ecom.order_items oi ON oi.order_id = o.order_id
WHERE o.order_status IN ('paid', 'shipped', 'delivered')
GROUP BY oi.product_id;
CREATE UNIQUE INDEX IF NOT EXISTS ux_mv_product_revenue
    ON ecom.mv_product_revenue (product_id);
CREATE INDEX IF NOT EXISTS idx_mv_product_revenue_rev
    ON ecom.mv_product_revenue (revenue DESC);

-- [Q05·Q10] 고객별 R/F/M 원지표 사전집계 MV (두 문항이 공유)
CREATE MATERIALIZED VIEW IF NOT EXISTS ecom.mv_customer_rev AS
SELECT o.customer_id,
       MAX(o.order_ts)            AS last_order_ts,
       COUNT(DISTINCT o.order_id) AS frequency,
       SUM(oi.line_total)         AS monetary
FROM ecom.orders o
JOIN ecom.order_items oi ON oi.order_id = o.order_id
WHERE o.order_status IN ('paid', 'shipped', 'delivered')
GROUP BY o.customer_id;
CREATE UNIQUE INDEX IF NOT EXISTS ux_mv_customer_rev
    ON ecom.mv_customer_rev (customer_id);

ANALYZE ecom.orders;
ANALYZE ecom.mv_category_daily;
ANALYZE ecom.mv_product_revenue;
ANALYZE ecom.mv_customer_rev;


-- #####################################################################
-- # Q01. 지난 한 달 실제 판매 총액 (GMV)
-- #   매출 인정 상태(paid/shipped/delivered)만, 매출=SUM(line_total),
-- #   최근 1개월(order_ts 기준), 0건이어도 COALESCE 로 0 반환.
-- #
-- #   [튜닝] 불필요한 COUNT(DISTINCT order_id) 제거
-- #     · 전: total_sales + COUNT(DISTINCT) → fan-out 중복제거용 Sort(219kB) 추가, 8.36ms
-- #     · 후: 요구(=총액)에 없는 order_count 제거 → Sort 소멸, Aggregate 만, 6.4ms
-- #   [조인] 플래너 Hash Join 이 정답(cost 최소·규모 안정). NLJ 는 캐시 덕에 wall-clock
-- #          빠르나 Buffers 252 vs 4363(17배) → 스케일 시 폭발. 강제 전환 안 함.
-- #####################################################################
-- 리포트용: 전/후를 둘 다 실행해 '무엇이 바뀌었는지' 눈으로 보여준다.
--   변화 = order_count 컬럼 제거 → Sort(219kB) 소멸. total_sales 값은 동일.
SELECT '=== Q01 [튜닝 전] 총액 + 불필요 COUNT(DISTINCT) → Sort 유발(8.36ms) ===' AS "구분";
SELECT
    COALESCE(SUM(oi.line_total), 0) AS total_sales,
    COUNT(DISTINCT o.order_id)      AS order_count   -- 요구에 없음 → Sort 유발(튜닝 대상)
FROM ecom.orders AS o
JOIN ecom.order_items AS oi ON oi.order_id = o.order_id
WHERE o.order_status IN ('paid', 'shipped', 'delivered')
  AND o.order_ts >= now() - interval '1 month';

SELECT '=== Q01 [튜닝 후] 불필요 컬럼 제거 → 총액만(Sort 소멸, 6.4ms) ===' AS "구분";
SELECT
    COALESCE(SUM(oi.line_total), 0) AS total_sales   -- 지난 한 달 실판매액
FROM ecom.orders AS o
JOIN ecom.order_items AS oi ON oi.order_id = o.order_id
WHERE o.order_status IN ('paid', 'shipped', 'delivered')
  AND o.order_ts >= now() - interval '1 month';


-- #####################################################################
-- # Q02. 월별 주문 건수 / 매출 / 주문당 평균금액(AOV)
-- #   AOV = 매출/건수, 분모 0 방지 ecom.safe_div.
-- #
-- #   [튜닝] 12.16 → 4.69(MV) → 2.07ms(+인덱스)
-- #     · 전: orders ⋈ order_items → GROUP BY month + COUNT(DISTINCT)
-- #           (month,order_id) 14,522행 Sort(952kB) + 18,700행 전체 조인
-- #     · 후: 매출은 mv_daily_gmv 월 롤업(조인 제거), 건수는 orders 단독 집계
-- #           + idx_orders_rev_ts 로 Index-Only Scan(Heap Fetches 0)
-- #   ⚠️ 트레이드오프: 매출(MV·stale) + 건수(실시간) 혼합 → 미REFRESH 시 어긋날 수 있음.
-- #      일 단위 신선도 허용하는 월간 리포트에 적합.
-- #####################################################################
SELECT '=== Q02 [튜닝 전] 단순 조인 + COUNT(DISTINCT) ===' AS "구분";
SELECT date_trunc('month', o.order_ts) AS month,
       COUNT(DISTINCT o.order_id)      AS order_count,
       SUM(oi.line_total)              AS revenue,
       ROUND(ecom.safe_div(SUM(oi.line_total),
                           COUNT(DISTINCT o.order_id)), 2) AS aov
FROM ecom.orders o
JOIN ecom.order_items oi ON oi.order_id = o.order_id
WHERE o.order_status IN ('paid', 'shipped', 'delivered')
GROUP BY date_trunc('month', o.order_ts)
ORDER BY month;

SELECT '=== Q02 [튜닝 후] MV 롤업(매출) + orders 단독(건수) ===' AS "구분";
WITH rev AS (   -- 월별 매출: MV 일별 GMV를 월로 롤업 (order_items 조인 회피)
    SELECT date_trunc('month', day) AS month,
           SUM(gmv)                 AS revenue
    FROM ecom.mv_daily_gmv
    GROUP BY date_trunc('month', day)
),
cnt AS (        -- 월별 주문건수: orders 만 (조인·DISTINCT 불필요 → Index-Only)
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


-- #####################################################################
-- # Q03. 최근 90일 카테고리 Top10 (매출 기준)
-- #   카테고리 경로는 재귀 CTE 뷰 v_category_path 로 표시.
-- #
-- #   [튜닝] 12.35 → 1.11ms  카테고리×일 사전집계 MV(mv_category_daily)
-- #     · 전: order_items(18,700) → orders → products → categories 조인+집계
-- #     · 후: MV(~890행) 읽기로 조인 대체
-- #   ⚠️ 경계: MV는 day 단위 → '최근 90일' 을 date_trunc('day', now()) 기준으로 맞춰야
-- #      원본과 일치(now()-interval 한낮 경계로 두면 경계일 오후 주문 누락).
-- #####################################################################
SELECT '=== Q03 [튜닝 전] 원본 4중 조인 + 집계 ===' AS "구분";
SELECT c.category_id, vp.path AS category_path,
       SUM(oi.line_total) AS revenue, SUM(oi.qty) AS units
FROM ecom.order_items oi
JOIN ecom.orders o ON o.order_id = oi.order_id
JOIN ecom.products p ON p.product_id = oi.product_id
JOIN ecom.categories c ON c.category_id = p.category_id
JOIN ecom.v_category_path vp ON vp.category_id = c.category_id
WHERE o.order_status IN ('paid', 'shipped', 'delivered')
  AND o.order_ts >= date_trunc('day', now()) - interval '90 days'
GROUP BY c.category_id, vp.path
ORDER BY revenue DESC
LIMIT 10;

SELECT '=== Q03 [튜닝 후] 카테고리×일 MV ===' AS "구분";
SELECT
    m.category_id,
    vp.path                 AS category_path,   -- 재귀 CTE 로 전개한 상위 경로
    SUM(m.revenue)          AS revenue,
    SUM(m.units)            AS units
FROM ecom.mv_category_daily AS m
JOIN ecom.v_category_path AS vp ON vp.category_id = m.category_id
WHERE m.day >= date_trunc('day', now()) - interval '90 days'
GROUP BY m.category_id, vp.path
ORDER BY revenue DESC
LIMIT 10;


-- #####################################################################
-- # Q04. 제품별 누적매출 RANK() Top20
-- #   RANK() OVER (ORDER BY 매출 DESC), 상위 20위(동점 시 복수 행 가능).
-- #
-- #   [튜닝] 10.76 → 0.55ms  제품 누적매출 MV(mv_product_revenue, 600행)
-- #     · 전: order_items(18,700) ⋈ orders → HashAggregate(600제품) → RANK
-- #     · 후: MV 600행 읽기로 대체 후 RANK. 날짜필터 없음(누적)이라 인덱스 무의미.
-- #####################################################################
SELECT '=== Q04 [튜닝 전] 원본 조인 집계 + RANK ===' AS "구분";
WITH product_sales AS (
    SELECT oi.product_id, SUM(oi.line_total) AS revenue
    FROM ecom.order_items oi
    JOIN ecom.orders o ON o.order_id = oi.order_id
    WHERE o.order_status IN ('paid', 'shipped', 'delivered')
    GROUP BY oi.product_id
),
ranked AS (
    SELECT product_id, revenue, RANK() OVER (ORDER BY revenue DESC) AS revenue_rank
    FROM product_sales
)
SELECT r.revenue_rank, r.product_id, p.sku, p.product_name, r.revenue
FROM ranked r
JOIN ecom.products p ON p.product_id = r.product_id
WHERE r.revenue_rank <= 20
ORDER BY r.revenue_rank, r.product_id;

SELECT '=== Q04 [튜닝 후] 제품 매출 MV + RANK ===' AS "구분";
WITH ranked AS (          -- 사전집계 MV에 매출 내림차순 순위
    SELECT product_id,
           revenue,
           units,
           RANK() OVER (ORDER BY revenue DESC) AS revenue_rank
    FROM ecom.mv_product_revenue
)
SELECT
    r.revenue_rank,
    r.product_id,
    p.sku,
    p.product_name,
    r.revenue
FROM ranked AS r
JOIN ecom.products AS p ON p.product_id = r.product_id
WHERE r.revenue_rank <= 20
ORDER BY r.revenue_rank, r.product_id;


-- #####################################################################
-- # Q05. 고객 RFM 분석 — 최근성(Recency) / 빈도(Frequency) / 금액(Monetary)
-- #   고객별로 세 지표만 표시: recency_days=마지막주문 경과일, frequency=주문수, monetary=누적매출.
-- #   ※ 등급화(NTILE)는 요구에서 빼고, 원지표 세 값만 조회한다.
-- #
-- #   [튜닝] 17.85 → 5.54ms  고객 R/F/M MV(mv_customer_rev, 2,246행)
-- #     · 전: order_items ⋈ orders → 고객집계, COUNT(DISTINCT)용 Sort(1065kB) 최대비용
-- #     · 후: MV 로 R/F/M 원지표 사전집계 → 조인·대형 Sort 제거.
-- #           Recency 경과일은 last_order_ts 에서 CURRENT_DATE 로 조회 시 계산 → 매일 최신.
-- #####################################################################
SELECT '=== Q05 [튜닝 전] 원본 조인 집계 (고객별 R/F/M) ===' AS "구분";
SELECT o.customer_id,
       (CURRENT_DATE - MAX(o.order_ts)::date) AS recency_days,   -- 최근성
       COUNT(DISTINCT o.order_id)             AS frequency,      -- 빈도
       SUM(oi.line_total)                     AS monetary        -- 금액
FROM ecom.orders o
JOIN ecom.order_items oi ON oi.order_id = o.order_id
WHERE o.order_status IN ('paid', 'shipped', 'delivered')
GROUP BY o.customer_id
ORDER BY monetary DESC, o.customer_id;

SELECT '=== Q05 [튜닝 후] 고객 MV 조회 (고객별 R/F/M) ===' AS "구분";
SELECT customer_id,
       (CURRENT_DATE - last_order_ts::date) AS recency_days,     -- 최근성
       frequency,                                                -- 빈도
       monetary                                                  -- 금액
FROM ecom.mv_customer_rev
ORDER BY monetary DESC, customer_id;


-- #####################################################################
-- # Q06. 첫 구매 후 30일 내 재구매율
-- #   첫 구매 = 고객별 최초 주문(매출 인정 상태). 재구매 = 첫주문 초과 ~ +30일 이내 다른 주문.
-- #   경계: order_ts > first AND order_ts <= first + 30d (첫 주문 자신은 제외).
-- #
-- #   [튜닝] 8.55 → 5.98ms  중복 스캔·self-join 제거(MV 없이 재작성)
-- #     · 전: orders 를 두 번 Seq Scan + self-join(30일 window 는 Join Filter 사후제거)
-- #     · 후: MIN(order_ts) OVER (PARTITION BY customer_id) 로 첫주문일 부여 → orders 1회 스캔,
-- #           고객별 GROUP BY + bool_or 로 30일 내 재구매 판정. Buffers 142→74.
-- #     · order_items 조인이 없어 원래 가벼운 문항 → MV보다 재작성이 본질적 개선(항상 최신).
-- #####################################################################
SELECT '=== Q06 [튜닝 전] self-join 버전(orders 2회 스캔) ===' AS "구분";
WITH first_order AS (
    SELECT o.customer_id, MIN(o.order_ts) AS first_order_ts
    FROM ecom.orders o
    WHERE o.order_status IN ('paid', 'shipped', 'delivered')
    GROUP BY o.customer_id
),
repurchase AS (
    SELECT DISTINCT f.customer_id
    FROM first_order f
    JOIN ecom.orders o2 ON o2.customer_id = f.customer_id
     AND o2.order_status IN ('paid', 'shipped', 'delivered')
     AND o2.order_ts >  f.first_order_ts
     AND o2.order_ts <= f.first_order_ts + interval '30 days'
)
SELECT (SELECT count(*) FROM first_order) AS first_time_customers,
       (SELECT count(*) FROM repurchase)  AS repurchased_customers,
       ROUND(100.0 * (SELECT count(*) FROM repurchase)
                   / NULLIF((SELECT count(*) FROM first_order), 0), 2) AS repurchase_rate_pct;

SELECT '=== Q06 [튜닝 후] 윈도우 1회 스캔 + bool_or ===' AS "구분";
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


-- #####################################################################
-- # Q07. 재고가 임계치보다 낮은 상품 (곧 품절될 위험이 있는 상품)
-- #   조건: qty_on_hand < reorder_point, 부족분(shortfall) 큰 순으로 재주문 우선순위.
-- #
-- #   [튜닝] 불필요한 컬럼 제거 → 필요한 컬럼만 (코딩 규칙: 불필요 컬럼 선택 지양)
-- #     · 전: product_name·active 까지 다 뽑음 — 품절 위험 판단엔 쓰지 않는 값.
-- #     · 후: 식별자(product_id·sku) + 재고 근거(qty_on_hand·reorder_point) + 부족분(shortfall)만.
-- #   ※ 인덱스/조인은 이미 최적(≈0.385ms, 600×600). 부분 인덱스는 소규모라 기각,
-- #     조인도 플래너 HJ 가 최적이라 변경 없음 → 이 문항의 개선점은 '컬럼 정리'다.
-- #####################################################################
SELECT '=== Q07 [튜닝 전] 불필요 컬럼(product_name·active) 포함 ===' AS "구분";
SELECT
    i.product_id,
    p.sku,
    i.qty_on_hand,
    i.reorder_point,
    (i.reorder_point - i.qty_on_hand) AS shortfall
FROM ecom.inventory AS i
JOIN ecom.products AS p ON p.product_id = i.product_id
WHERE i.qty_on_hand < i.reorder_point
ORDER BY shortfall DESC, i.product_id;

SELECT '=== Q07 [튜닝 후] 필요한 컬럼만 (식별자 + 재고근거 + 부족분) ===' AS "구분";
SELECT
    i.product_id,
    p.sku,
    i.qty_on_hand,                                   -- 현재고
    i.reorder_point,                                 -- 재주문 임계치
    (i.reorder_point - i.qty_on_hand) AS shortfall   -- 부족분(우선순위)
FROM ecom.inventory AS i
JOIN ecom.products AS p ON p.product_id = i.product_id
WHERE i.qty_on_hand < i.reorder_point
ORDER BY shortfall DESC, i.product_id;


-- #####################################################################
-- # Q08. 효자상품 — 리뷰 50건↑ & 평균 평점 4.5↑
-- #   그룹 조건이므로 WHERE 아닌 HAVING.
-- #
-- #   [튜닝] 1.94 → 0.79ms  집계-후-조인(MV 없이 재작성)
-- #     · 전: reviews(2,031) ⋈ products 먼저 → 2,031행에 상품정보 실어 GROUP BY(3컬럼)
-- #           → HAVING 으로 12개만 남김(낭비: 12개용 정보를 2,031행에 조인)
-- #     · 후: reviews 를 먼저 상품별 집계(GROUP BY product_id) + HAVING 으로 12개 축소
-- #           → 그 12개만 products 조인. GROUP BY 3컬럼→1컬럼.
-- #####################################################################
SELECT '=== Q08 [튜닝 전] 조인-후-집계 ===' AS "구분";
SELECT r.product_id, p.sku, p.product_name,
       count(*) AS review_count, ROUND(avg(r.rating), 2) AS avg_rating
FROM ecom.reviews r
JOIN ecom.products p ON p.product_id = r.product_id
GROUP BY r.product_id, p.sku, p.product_name
HAVING count(*) >= 50 AND avg(r.rating) >= 4.5
ORDER BY avg(r.rating) DESC, count(*) DESC, r.product_id;  -- 원본 평점 기준 + 결정적 tie-break

SELECT '=== Q08 [튜닝 후] 집계-후-조인 ===' AS "구분";
WITH agg AS (               -- reviews 를 먼저 상품별 집계 + 그룹 조건으로 축소
    SELECT product_id,
           count(*)     AS review_count,
           avg(rating)  AS avg_rating
    FROM ecom.reviews
    GROUP BY product_id
    HAVING count(*) >= 50 AND avg(rating) >= 4.5
)
SELECT
    a.product_id,
    p.sku,
    p.product_name,
    a.review_count,
    ROUND(a.avg_rating, 2) AS avg_rating
FROM agg AS a
JOIN ecom.products AS p ON p.product_id = a.product_id
ORDER BY a.avg_rating DESC, a.review_count DESC, a.product_id;  -- 전/후 정렬 일치(결정적)


-- #####################################################################
-- # Q09. 쿠폰 사용 vs 미사용 주문의 평균 주문금액(AOV) 비교
-- #   쿠폰 사용여부: coupon_code IS NULL(=미사용). 분기는 CASE WHEN ... IS NULL.
-- #
-- #   [튜닝] 16.0 → 6.95ms  매출/건수 분리(Q02 와 동일 패턴)
-- #     · 전: order_items ⋈ orders → COUNT(DISTINCT)용 Sort(14,522행,1030kB) 가 지배적(~9ms)
-- #     · 후: 매출(rev)은 조인 후 쿠폰 2그룹 SUM, 주문수(cnt)는 orders 단독 COUNT(*)
-- #           → DISTINCT/Sort 소멸. (전제검증: 품목 없는 매출상태 주문 0건)
-- #     · 인사이트: 쿠폰 사용 주문 AOV 가 미사용의 약 2.9배(큰 장바구니에 쿠폰).
-- #####################################################################
SELECT '=== Q09 [튜닝 전] 조인 후 COUNT(DISTINCT) ===' AS "구분";
SELECT CASE WHEN o.coupon_code IS NULL THEN '미사용' ELSE '사용' END AS coupon_used,
       COUNT(DISTINCT o.order_id) AS order_count,
       SUM(oi.line_total) AS total_revenue,
       ROUND(SUM(oi.line_total) / NULLIF(COUNT(DISTINCT o.order_id), 0), 2) AS aov
FROM ecom.orders o
JOIN ecom.order_items oi ON oi.order_id = o.order_id
WHERE o.order_status IN ('paid', 'shipped', 'delivered')
GROUP BY CASE WHEN o.coupon_code IS NULL THEN '미사용' ELSE '사용' END
ORDER BY coupon_used;

SELECT '=== Q09 [튜닝 후] 매출/건수 분리 ===' AS "구분";
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


-- #####################################################################
-- # Q10. 상위 1% 고객의 최근 60일 매출
-- #   상위 1% = 고객 '전체 기간' 누적매출 PERCENT_RANK() >= 0.99. 조회는 그들의 최근 60일 매출.
-- #   최근 주문 없는 우량고객도 보이도록 LEFT JOIN + COALESCE 0.
-- #
-- #   [튜닝] 14.3 → 7.06ms  랭킹을 고객 MV(mv_customer_rev) 재사용
-- #     · 전: customer_total 이 order_items ⋈ orders 를 전부 집계(~9.7ms) 후 상위 1% 산출
-- #     · 후: mv_customer_rev.monetary(=누적매출) 로 랭킹 → 대전집계 소멸.
-- #           revenue_60d 만 실데이터 조인 → 항상 최신. Buffers 517→282.
-- #     · 하나의 MV 가 Q05(RFM)와 Q10(상위1%) 두 문항을 함께 가속.
-- #####################################################################
SELECT '=== Q10 [튜닝 전] customer_total 대전집계 + PERCENT_RANK ===' AS "구분";
WITH customer_total AS (
    SELECT o.customer_id, SUM(oi.line_total) AS total_revenue
    FROM ecom.orders o
    JOIN ecom.order_items oi ON oi.order_id = o.order_id
    WHERE o.order_status IN ('paid', 'shipped', 'delivered')
    GROUP BY o.customer_id
),
ranked AS (
    SELECT customer_id, total_revenue,
           PERCENT_RANK() OVER (ORDER BY total_revenue) AS pr
    FROM customer_total
),
top1 AS (
    SELECT customer_id, total_revenue FROM ranked WHERE pr >= 0.99
)
SELECT t.customer_id, t.total_revenue, COALESCE(SUM(oi.line_total), 0) AS revenue_60d
FROM top1 t
LEFT JOIN ecom.orders o ON o.customer_id = t.customer_id
   AND o.order_status IN ('paid', 'shipped', 'delivered')
   AND o.order_ts >= now() - interval '60 days'
LEFT JOIN ecom.order_items oi ON oi.order_id = o.order_id
GROUP BY t.customer_id, t.total_revenue
ORDER BY t.total_revenue DESC;

SELECT '=== Q10 [튜닝 후] 고객 MV 랭킹 + 최근 60일 실데이터 ===' AS "구분";
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


-- #####################################################################
-- # Q11. 안전 나눗셈 함수로 평균 안전 계산 (0으로 나누기 방지)
-- #   상품별 평균 평점 = 평점합/리뷰수(수동). 리뷰 0건 상품 포함(LEFT JOIN) → 분모 0.
-- #   순수 COALESCE(합,0)/COALESCE(개수,0) 는 0/0 → 'division by zero' 에러 → 안전함수로 방지.
-- #
-- #   [튜닝] 4.10 → 1.28ms  함수 선택 = 튜닝 (safe_div(sql) 채택)
-- #     · safe_div(sql) 는 플래너가 인라인 → 순수 NULLIF 와 동일 속도(호출 오버헤드 0)
-- #     · f_safe_div(plpgsql) 는 인라인 불가 → 행당 호출 비용(~2.2배 느림)
-- #     · semantics: '리뷰 없음'은 0 보다 NULL(평가 없음)이 맞음 → safe_div 가 의미도 정확
-- #####################################################################
-- 리포트용: 전/후를 둘 다 실행해 '무엇이 바뀌었는지' 눈으로 보여준다.
--   변화 = 두 함수 대비 2컬럼(f_safe_div→0 / safe_div→NULL) → safe_div 단일 컬럼.
--   리뷰 0건 상품에서 f_safe_div 는 0, safe_div 는 NULL(평가 없음) — 의미도 후자가 정확.
SELECT '=== Q11 [튜닝 전] 두 함수 대비: f_safe_div→0 / safe_div→NULL (4.10ms) ===' AS "구분";
WITH prod_rev AS (
    SELECT product_id, SUM(rating) AS rating_sum, COUNT(*) AS review_count
    FROM ecom.reviews GROUP BY product_id
)
SELECT p.product_id, p.sku, COALESCE(pr.review_count, 0) AS review_count,
       ROUND(ecom.f_safe_div(COALESCE(pr.rating_sum, 0), COALESCE(pr.review_count, 0)), 2) AS avg_rating_zero, -- 리뷰0 → 0
       ROUND(ecom.safe_div  (COALESCE(pr.rating_sum, 0), COALESCE(pr.review_count, 0)), 2) AS avg_rating_null  -- 리뷰0 → NULL
FROM ecom.products p
LEFT JOIN prod_rev pr ON pr.product_id = p.product_id
ORDER BY review_count, p.product_id;

SELECT '=== Q11 [튜닝 후] safe_div(sql, 인라인) 단일 컬럼 (1.28ms) ===' AS "구분";
WITH prod_rev AS (              -- 상품별 평점합·리뷰수
    SELECT product_id,
           SUM(rating) AS rating_sum,
           COUNT(*)    AS review_count
    FROM ecom.reviews
    GROUP BY product_id
)
SELECT
    p.product_id,
    p.sku,
    COALESCE(pr.review_count, 0) AS review_count,
    -- 분모 0(리뷰 0건) 위험을 sql 안전함수로 방지. 리뷰 없으면 NULL(평가 없음).
    ROUND(ecom.safe_div(COALESCE(pr.rating_sum, 0), COALESCE(pr.review_count, 0)), 2) AS avg_rating
FROM ecom.products AS p
LEFT JOIN prod_rev AS pr ON pr.product_id = p.product_id
ORDER BY review_count, p.product_id;   -- 리뷰 0건(분모 0) 상품이 맨 위에 보이도록

SELECT '### ALL.sql 완료 — Q01~Q11 [튜닝 전]/[튜닝 후] 실행 끝 ###' AS "구분";
