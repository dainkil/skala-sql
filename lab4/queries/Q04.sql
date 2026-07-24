-- =====================================================================
-- Q04. 제품별 누적매출 RANK() Top20   [튜닝 후: 제품 매출 MV]
--   - 누적매출 = 제품별 SUM(line_total) (매출 인정 상태 전체 기간)
--   - RANK() OVER (ORDER BY 매출 DESC), 상위 20위 (동점 시 복수 행 가능)
-- 실행: psql skala_db4 -v ON_ERROR_STOP=1 -f lab4/queries/Q04.sql
--
-- ---------------------------------------------------------------------
-- [튜닝 기록]  (근거: captures/Q04_before.txt, Q04_after.txt, Q04_joins.txt)
--
-- 병목(튜닝 전): order_items(18,700행) ⋈ orders → HashAggregate(600제품)까지가 대부분.
--   · 날짜 필터 없음(누적) → orders 필터 78% 통과 → 인덱스 무의미.
--   · 윈도우/RANK/최종조인은 600행이라 저렴.
--   · 조인 3종: HJ cost795 < SMJ 1311 < NLJ 3363 → 플래너 HJ 선택(스케일 안정).
--   · Execution Time ≈ 10.76ms
--
-- 처방(통계 테이블 전략): 제품 누적매출 사전집계 MV 사용
--   · mv_product_revenue (product_id, revenue, units) 600행 — tuning/mv_product_revenue.sql
--   · order_items 18,700행 조인 → MV 600행 읽기로 대체 후 RANK
--   · Execution Time ≈ 0.55ms (약 95%↓), 결과 완전 일치(mismatch 0)
--   · 참고: mv에 revenue DESC 인덱스 있으나 600행이라 플래너가 Seq Scan+Sort 유지
--     (ORDER BY 인덱스 이득은 규모 의존 — 제품 수가 커지면 Sort 제거에 기여)
-- ⚠️ 트레이드오프: MV는 REFRESH 전까지 stale. 갱신은 refresh_mv_daily_gmv.sh(15:00).
-- ---------------------------------------------------------------------
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

-- [튜닝 전 · 원본 조인 버전]
-- WITH product_sales AS (
--     SELECT oi.product_id, SUM(oi.line_total) AS revenue
--     FROM ecom.order_items oi JOIN ecom.orders o ON o.order_id = oi.order_id
--     WHERE o.order_status IN ('paid','shipped','delivered')
--     GROUP BY oi.product_id),
-- ranked AS (SELECT product_id, revenue, RANK() OVER (ORDER BY revenue DESC) AS revenue_rank
--            FROM product_sales)
-- SELECT r.revenue_rank, r.product_id, p.sku, p.product_name, r.revenue
-- FROM ranked r JOIN ecom.products p ON p.product_id = r.product_id
-- WHERE r.revenue_rank <= 20 ORDER BY r.revenue_rank, r.product_id;
