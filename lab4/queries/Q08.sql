-- =====================================================================
-- Q08. 효자상품 — 리뷰 많고(50건↑) 평점 좋은(평균 4.5↑) 상품   [튜닝 후: 집계-후-조인]
--   - 집계: 상품별 리뷰 수 count(*), 평균 평점 avg(rating)
--   - 선별: HAVING count(*) >= 50 AND avg(rating) >= 4.5
--   - products 와 조인해 sku / 상품명 함께 표시, 평점·리뷰수 내림차순
-- 실행: psql skala_db4 -v ON_ERROR_STOP=1 -f lab4/queries/Q08.sql
--
--   ※ 개별 상품 필터가 아니라 '그룹 조건'이므로 WHERE 아닌 HAVING 사용.
--
-- ---------------------------------------------------------------------
-- [튜닝 기록]  (근거: captures/Q08_before.txt, Q08_after.txt, Q08_joins.txt)
--
-- 병목(튜닝 전): reviews(2,031) ⋈ products(600) Hash Join 을 '먼저' 수행
--   · 조인 결과 2,031행에 sku/product_name 을 실어 GROUP BY(3컬럼) → HAVING 으로 12개만 남김
--     (121그룹 중 109개 버림). 12개만 필요한 상품정보를 2,031행에 대해 조인·운반 = 낭비.
--   · 조인 3종: HJ cost67/Buf28 < NLJ+Memoize 130/Buf384(13.7배) < SMJ 219/Buf31(2031행 Sort).
--   · Execution Time ≈ 1.94ms
--
-- 처방(집계 최적화 — 집계-후-조인, MV 없이 쿼리 재작성):
--   · reviews 를 '먼저' 상품별 집계(단일 컬럼 GROUP BY product_id)하고 HAVING 으로 12개로 축소
--   · 그 12개만 products 와 조인 → 2,031행 조인·운반이 사라짐. GROUP BY 도 3컬럼→1컬럼.
--   · Execution Time ≈ 0.79ms (약 59%↓), 결과 완전 일치(효자상품 12개)
--   · 커버링 인덱스 reviews(product_id) INCLUDE(rating) 시험 → 2,031행이라 Seq Scan 에 밀려
--     플래너가 미사용(Q07 과 동일: 소규모+전건 스캔이면 인덱스 이득 없음) → 미적용.
--   · 이점: 새 객체·갱신 부담 없음, 항상 최신.
-- ---------------------------------------------------------------------
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
ORDER BY a.avg_rating DESC, a.review_count DESC;


-- [튜닝 전 · 조인-후-집계 버전]
-- SELECT r.product_id, p.sku, p.product_name,
--        count(*) AS review_count, ROUND(avg(r.rating),2) AS avg_rating
-- FROM ecom.reviews r JOIN ecom.products p ON p.product_id = r.product_id
-- GROUP BY r.product_id, p.sku, p.product_name
-- HAVING count(*) >= 50 AND avg(r.rating) >= 4.5
-- ORDER BY avg_rating DESC, review_count DESC;
