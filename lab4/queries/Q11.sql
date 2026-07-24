-- =====================================================================
-- Q11. 안전 나눗셈 함수로 평균 안전 계산 (0으로 나누기 방지)   [튜닝 후: safe_div(sql) 채택]
--   - 예시 평균: 상품별 '평균 평점' = 평점합 / 리뷰수 (수동 나눗셈)
--   - '리뷰 0건 상품'까지 포함(LEFT JOIN) → 리뷰수=0 이라 분모 0 (이 데이터엔 479/600개!)
--   - 순수 COALESCE(평점합,0) / COALESCE(리뷰수,0) 는 0/0 → 'division by zero' 에러 (실측 확인)
--     → 안전 나눗셈 함수로 방지. (내장 AVG()는 0행이면 NULL이지만 '합/개수' 수동계산은 에러)
-- 실행: psql skala_db4 -v ON_ERROR_STOP=1 -f lab4/queries/Q11.sql
--
-- ---------------------------------------------------------------------
-- [튜닝 기록]  (근거: captures/Q11_before.txt, Q11_after.txt, Q11_joins.txt)
--
-- 구조: reviews(2,031) 집계(121그룹) → products(600) LEFT JOIN → Sort 600.
--   이미 '집계-후-조인' 이라 조인/집계는 최적. 조인은 600×121 이라 HJ/NLJ/SMJ 모두 sub-0.15ms(무의미).
--   → Q11 의 실질 튜닝 포인트는 '어떤 안전함수를 쓰느냐'(옵티마이저 인라인).
--
-- 병목/발견(함수 선택 = 튜닝): 같은 쿼리에서 나눗셈 컬럼만 바꿔 측정
--   · 둘 다(f_safe_div + safe_div)      3.85ms
--   · safe_div(sql)만                   1.28ms   ← 채택
--   · f_safe_div(plpgsql)만             2.87ms   (~2.2배 느림)
--   · 인라인 NULLIF                     1.28ms   (safe_div 와 동일 = 완전 인라인 증거)
--
-- 처방: 리포트 평균은 ecom.safe_div(sql) 사용.
--   · SQL 함수는 플래너가 '인라인' → 순수 NULLIF 와 동일 속도(호출 오버헤드 0)
--   · plpgsql(f_safe_div)은 인라인 불가 → 행당 함수 호출 비용(600행에 ~1.6ms)
--   · Execution Time 4.10 → 1.28ms (약 69%↓)  (두 컬럼 계산 → 필요한 한 컬럼만)
--   · semantics: '리뷰 없음'은 0(평점 0)보다 NULL(평가 없음)이 맞음 → safe_div 가 의미도 정확
--   · f_safe_div(0 반환)은 '없으면 0으로 취급'할 지표(매출/건수)에 적합 — 용도별 선택
-- ---------------------------------------------------------------------
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

-- [튜닝 전 · 두 안전함수 대비 버전]  (0으로 나눌 때 f_safe_div→0, safe_div→NULL)
-- WITH prod_rev AS (SELECT product_id, SUM(rating) AS rating_sum, COUNT(*) AS review_count
--                   FROM ecom.reviews GROUP BY product_id)
-- SELECT p.product_id, p.sku, COALESCE(pr.review_count,0) AS review_count,
--        ROUND(ecom.f_safe_div(COALESCE(pr.rating_sum,0), COALESCE(pr.review_count,0)),2) AS avg_rating_zero, -- →0
--        ROUND(ecom.safe_div(COALESCE(pr.rating_sum,0), COALESCE(pr.review_count,0)),2)   AS avg_rating_null  -- →NULL
-- FROM ecom.products p LEFT JOIN prod_rev pr ON pr.product_id=p.product_id
-- ORDER BY review_count, p.product_id;
