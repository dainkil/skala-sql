-- =====================================================================
-- Q01. 지난 한 달 실제 판매 총액 (GMV)   [튜닝 후]
--   - 매출 인정 상태: paid / shipped / delivered (cancelled/refunded/created 제외)
--   - 매출액 = SUM(order_items.line_total)  ← 주문 시점 스냅샷 가격
--   - 기간   = 최근 1개월 (orders.order_ts 기준, 컬럼에 함수 X → 인덱스 사용 가능)
--   - 0건이어도 NULL 대신 0 반환 (COALESCE)
-- 실행: psql skala_db4 -v ON_ERROR_STOP=1 -f lab4/queries/Q01.sql
--
-- ---------------------------------------------------------------------
-- [튜닝 기록]  (근거: captures/Q01_before.txt, Q01_joins.txt, Q01_after.txt)
--
-- 1) 쿼리 레벨 개선 — 불필요한 COUNT(DISTINCT) 제거
--    · 튜닝 전: total_sales + COUNT(DISTINCT o.order_id)
--        → 조인 fan-out 을 중복 제거하려고 [Sort (Sort Key: order_id, 219kB)] 노드 추가
--        → Execution Time ≈ 8.36ms
--    · 튜닝 후: 요구사항(=총액)에 없는 order_count 를 제거
--        → Sort 노드 소멸, Aggregate 만 남음
--        → Execution Time ≈ 6.4ms  (코딩 규칙: 불필요한 컬럼 선택 지양과도 일치)
--      ※ 주문 건수가 필요하면 조인 없이 orders 만으로 따로 세는 게 맞다(정렬 불필요).
--
-- 2) Join 전략 — Hash Join 이 정답 (플래너 자동 선택, 유지)
--        전략        cost   Exec(2회차)  Buffers   비고
--        Hash        651    6.4~7.1ms    252       양쪽 1회 스캔→해시 (선택됨)
--        Merge       1001   4.5~5.5ms    290       order_items 인덱스 정렬 이용
--        NestedLoop  1610   3.2~3.6ms    4363      orders 1423행마다 index probe
--      · 실측 wall-clock 은 NLJ 가 빠르지만, 이는 데이터가 작고 전부 캐시(hit)라
--        NLJ 의 4363 버퍼 접근이 전부 메모리 히트=거의 공짜이기 때문.
--      · Buffers(252 vs 4363, 17배)가 스케일의 진실 — 데이터↑/캐시미스 시 NLJ 폭발.
--        플래너는 cost 최소이자 규모 안정적인 Hash 를 고른 것이며 옳다. → 강제 안 함.
--
-- 3) Index — 부분 인덱스 후보(아래). 단 이 필터는 6,860행 중 ~1,424행(21%)을 남겨
--    소형 테이블(71 buffers)에서는 플래너가 여전히 Seq Scan 을 유지할 수 있다.
--    직접 생성 후 재측정해 "탔는지/안 탔는지"를 근거로 판단할 것.
--      CREATE INDEX idx_orders_rev_ts ON ecom.orders (order_ts)
--        WHERE order_status IN ('paid','shipped','delivered');
--      ANALYZE ecom.orders;
-- =====================================================================
SELECT
    COALESCE(SUM(oi.line_total), 0) AS total_sales   -- 지난 한 달 실판매액
FROM ecom.orders AS o
JOIN ecom.order_items AS oi
    ON oi.order_id = o.order_id
WHERE o.order_status IN ('paid', 'shipped', 'delivered')
  AND o.order_ts >= now() - interval '1 month';
