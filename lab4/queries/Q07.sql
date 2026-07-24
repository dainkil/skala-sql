-- =====================================================================
-- Q07. 재고가 임계치보다 낮은 상품 (품절 위험 · reorder 필요)
--   - 조건: inventory.qty_on_hand < inventory.reorder_point
--   - 부족분(shortfall = reorder_point - qty_on_hand) 큰 순으로 정렬 → 재주문 우선순위
--   - products 와 조인해 sku / 상품명 / 활성여부 함께 표시
-- 실행: psql skala_db4 -v ON_ERROR_STOP=1 -f lab4/queries/Q07.sql
--
--   ※ 두 컬럼 비교라 WHERE 절에 함수를 씌우지 않음(인덱스/부분인덱스 여지 유지).
--
-- ---------------------------------------------------------------------
-- [튜닝 기록]  (근거: captures/Q07_before.txt, Q07_after.txt, Q07_joins.txt)
--
-- 진단: inventory Seq Scan(600행→필터 60행, 5 buffers) → products Hash Join → Sort(60행).
--   · Execution ≈ 0.385ms, Buffers 18 (전부 캐시). 팩트 테이블 없이 600×600이라 이미 최적.
--   · 필터 추정 rows=200 vs 실제 60 — 두 컬럼 비교(qty_on_hand < reorder_point)는
--     컬럼 통계로 못 잡아 기본 선택도(~33%) 사용. 여기선 leaf 라 무해(대형 조인 입력이면 주의).
--
-- 처방: 변경 없음 (이미 sub-ms). 아래 후보를 시험했으나 이득 없어 미적용.
--   · 부분 커버링 인덱스 idx_inventory_at_risk (product_id) INCLUDE(qty,reorder)
--       WHERE qty_on_hand < reorder_point
--     → 플래너가 거부(Seq 5 buffers < index+heap). 강제 사용 시 cost 12.5→16, buffers↑로 더 느림.
--     부분 인덱스는 '대형 테이블 + 저선택도'에서 의미. 600행에는 과함.
--   · 조인: HJ cost29.6/Buf12 < SMJ 59.9/14 < NLJ 115/Buf185(15배). 플래너 HJ 최적, 강제 전환 없음.
--     (NLJ는 캐시 wall 0.216ms로 빠르나 buffers 15배 → 규모 커지면 위험)
-- ⇒ '항상 인덱스/MV가 답은 아니다' — 최적 쿼리는 그대로 두는 것도 튜닝 판단.
-- ---------------------------------------------------------------------
SELECT
    i.product_id,
    p.sku,
    p.product_name,
    p.active,
    i.qty_on_hand,
    i.reorder_point,
    (i.reorder_point - i.qty_on_hand) AS shortfall
FROM ecom.inventory AS i
JOIN ecom.products AS p ON p.product_id = i.product_id
WHERE i.qty_on_hand < i.reorder_point
ORDER BY shortfall DESC, i.product_id;
