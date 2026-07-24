-- =====================================================================
-- lab4/tuning/indexes.sql
--   튜닝으로 추가/개선한 인덱스 모음 (배포 원본 00_schema.sql 미수정)
--   실행: psql skala_db4 -v ON_ERROR_STOP=1 -f lab4/tuning/indexes.sql
-- =====================================================================

-- [Q02] 월별 주문건수: orders 를 매출상태로 부분 + order_ts 커버.
--   목적: SELECT date_trunc('month',order_ts), COUNT(*) ... WHERE status IN(3)
--         → Index Only Scan (Heap Fetches 0) 로 Seq Scan 대체.
--   효과: Q02 튜닝후 4.69ms → 2.28ms (~51%↓). 건수를 실시간으로 유지(stale 아님).
--   주의: Index-Only 이득은 VACUUM(Visibility Map) 최신에 의존.
--   참고: Q01 은 line_total(order_items 조인)이 필요해 이 인덱스로 커버 불가 → 미적용.
CREATE INDEX IF NOT EXISTS idx_orders_rev_ts
    ON ecom.orders (order_ts)
    WHERE order_status IN ('paid', 'shipped', 'delivered');

ANALYZE ecom.orders;
