-- =====================================================================
-- lab4/tuning/mv_daily_gmv.sql
--   Materialized View 활용 & 무중단 갱신 준비 (mv_daily_gmv)
--   ※ 배포 원본(00_schema.sql)은 수정하지 않고, 여기서 보강한다.
--   실행: psql skala_db4 -v ON_ERROR_STOP=1 -f lab4/tuning/mv_daily_gmv.sql
--
--   MV 는 조회 시 재계산하지 않는다(저장 스냅샷 읽기). REFRESH 할 때만 재계산.
--   '오후 3시 갱신'은 조회가 아니라 스케줄러가 하루 1회 REFRESH 하는 것.
--   (스케줄 설계는 refresh_mv_daily_gmv.sh + README 참고)
-- =====================================================================

-- ---------------------------------------------------------------------
-- [1] 가속 실증 : 원본 조인 집계 vs MV 조회
--     (아래 두 EXPLAIN 의 Execution Time / Buffers 를 비교)
-- ---------------------------------------------------------------------
\echo '### [before] 원본 조인 집계 (orders JOIN order_items + SUM) ###'
EXPLAIN (ANALYZE, BUFFERS)
SELECT date_trunc('day', o.order_ts) AS day, sum(oi.line_total) AS gmv
FROM ecom.orders o
JOIN ecom.order_items oi ON oi.order_id = o.order_id
WHERE o.order_status IN ('paid','shipped','delivered')
GROUP BY 1;

\echo '### [after] MV 조회 (사전집계 읽기) ###'
EXPLAIN (ANALYZE, BUFFERS)
SELECT day, gmv FROM ecom.mv_daily_gmv;

-- ---------------------------------------------------------------------
-- [2] 무중단 갱신(CONCURRENTLY) 준비 : UNIQUE 인덱스 필수
--     - 00_schema.sql 에 주석으로만 있던 ux_mv_daily_gmv_day 를 여기서 실현
--     - 이게 없으면 REFRESH ... CONCURRENTLY 는 에러
-- ---------------------------------------------------------------------
CREATE UNIQUE INDEX IF NOT EXISTS ux_mv_daily_gmv_day
    ON ecom.mv_daily_gmv (day);

-- ---------------------------------------------------------------------
-- [3] 갱신 실행 예시 (무중단)
--     주의: REFRESH ... CONCURRENTLY 는 트랜잭션 블록 안에서 실행 불가.
--           psql -f 는 기본 autocommit 이라 최상위 문장으로는 정상 동작.
--     운영 스케줄에서는 refresh_mv_daily_gmv.sh 가 이 문장을 호출.
-- ---------------------------------------------------------------------
REFRESH MATERIALIZED VIEW CONCURRENTLY ecom.mv_daily_gmv;

-- 신선도 확인
\echo '### 갱신 후 신선도 ###'
SELECT count(*) AS rows, max(day) AS latest_day FROM ecom.mv_daily_gmv;
