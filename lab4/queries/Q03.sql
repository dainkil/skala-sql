-- =====================================================================
-- Q03. 최근 90일 카테고리 Top10 (매출 기준)   [튜닝 후: 카테고리 MV]
--   - 매출 인정 상태: paid / shipped / delivered
--   - 카테고리 경로는 재귀 CTE 뷰(v_category_path)로 표시
--   - 최근 90일 = date_trunc('day', now()) - interval '90 days' (전체 날짜 기준)
-- 실행: psql skala_db4 -v ON_ERROR_STOP=1 -f lab4/queries/Q03.sql
--
-- ---------------------------------------------------------------------
-- [튜닝 기록]  (근거: captures/Q03_before.txt, Q03_after.txt, Q03_joins.txt)
--
-- 병목(튜닝 전): order_items(18,700행) → orders → products → categories 조인 + 집계
--   · order_items 전체 Seq Scan + Hash Join(11,416행)이 시간 대부분
--   · order_ts 필터가 61% 통과(저선택도) → idx_orders_rev_ts 있어도 Seq Scan 유지
--     (조인 위해 order_id 힙 접근 필요 → 인덱스 커버 불가 → 인덱스가 답 아님)
--   · 조인 3종: HJ cost903 < SMJ 2172 < NLJ 4417 → 플래너 HJ 선택이 최적
--   · Execution Time ≈ 12.35ms
--
-- 처방(통계 테이블 전략 = Materialized 집계): 카테고리×일 사전집계 MV 사용
--   · mv_category_daily (day, category_id, revenue, units) — tuning/mv_category_daily.sql
--   · order_items 18,700행 조인 → MV ~890행 읽기로 대체
--   · Execution Time ≈ 1.11ms (약 91%↓), 결과 완전 일치
--
-- ⚠️ 경계 주의: MV는 day 단위라 '최근 90일'을 date_trunc('day', now()) 기준으로
--    맞춰야 원본과 일치한다. now()-interval '90 days'(한낮 경계)로 두면 MV가
--    경계일 오후 주문을 통째로 누락해 결과가 어긋난다. → 양쪽 day 정렬 필수.
-- ⚠️ 트레이드오프: MV는 REFRESH 전까지 stale. 갱신 전략은 README 참고.
-- ---------------------------------------------------------------------
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

-- [튜닝 전 · 원본 조인 버전 — day 정렬 경계]
-- SELECT c.category_id, vp.path AS category_path,
--        SUM(oi.line_total) AS revenue, SUM(oi.qty) AS units
-- FROM ecom.order_items oi
-- JOIN ecom.orders o ON o.order_id = oi.order_id
-- JOIN ecom.products p ON p.product_id = oi.product_id
-- JOIN ecom.categories c ON c.category_id = p.category_id
-- JOIN ecom.v_category_path vp ON vp.category_id = c.category_id
-- WHERE o.order_status IN ('paid','shipped','delivered')
--   AND o.order_ts >= date_trunc('day', now()) - interval '90 days'
-- GROUP BY c.category_id, vp.path
-- ORDER BY revenue DESC LIMIT 10;
