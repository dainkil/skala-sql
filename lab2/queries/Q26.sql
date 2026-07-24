-- Q26. 집계·조인 성능 최적화 및 고급 집계 함수 종합
--   선행 : Q12(course_owner) · Q23(ix_student_major_gpa) 를 먼저 실행해 둘 것.
--          (5) LATERAL 과 (4) 조인 전략이 그 인덱스를 활용한다.
--
--   [25-1] GROUP BY 키 이외 컬럼 금지 (ONLY_FULL_GROUP_BY)
--   [25-2] OFFSET 페이지네이션의 함정 vs Keyset 방식
--   [25-3] FK 컬럼 인덱스 점검
--   [25-4] 조인 전략 — Nested Loop vs Hash, 카르테시안 곱 경고
--   [25-5] LATERAL JOIN — 행별 독립 서브쿼리
--   [25-6] 통계 테이블 전략 — Materialized View
--   [25-7] STRING_AGG / ARRAY_AGG / JSON_AGG 비교


-- =====================================================================
--  25-1. SELECT 에 GROUP BY 키 이외 컬럼 포함 금지
--
--  MySQL 은 ONLY_FULL_GROUP_BY 를 끄면 그룹 안 임의의 한 행 값을 조용히
--  반환한다. 어느 행이 뽑힐지 보장되지 않아 결과가 실행마다 달라질 수 있다.
--  PostgreSQL 은 이 규칙을 항상 강제하므로 위반하면 반드시 에러가 난다.
--
--  아래 쿼리는 에러가 나므로 주석 처리해 두었다. 주석을 풀면 확인할 수 있다.
--    SELECT major, name FROM lab.student GROUP BY major;
--    ERROR:  column "s.name" must appear in the GROUP BY clause
--            or be used in an aggregate function
--
--  해결은 둘 중 하나다.
--    ① GROUP BY 에 컬럼을 추가한다        → 그룹이 잘게 쪼개진다
--    ② 집계 함수로 감싼다(MAX/MIN/…)      → 어떤 값을 고를지 명시된다
-- =====================================================================
SELECT major                                           AS 학과,
       COUNT(*)                                        AS 인원,
       MAX(name)                                       AS 이름_사전순마지막,
       ROUND(AVG(gpa), 2)                              AS 평균GPA
  FROM lab.student
 GROUP BY major
 ORDER BY major;


-- =====================================================================
--  25-2. OFFSET 기반 페이지네이션의 함정
--
--  LIMIT 10 OFFSET 2990 은 DB 가 2,990건을 실제로 읽어서 버린 뒤
--  10건을 반환한다. 뒤쪽 페이지로 갈수록 읽는 양이 선형으로 늘어난다 — O(N).
--
--  Keyset(Cursor) 방식은 직전 페이지의 마지막 키를 조건으로 넘겨
--  인덱스에서 해당 위치로 바로 진입한다. 페이지 번호와 무관하게 일정하다.
--  단, 정렬 기준이 유일(unique)해야 하고 임의 페이지 점프는 불가능하다.
--
--  실행계획에서 볼 곳 : OFFSET 쪽 Index Scan 의 rows 와 actual rows 차이
-- =====================================================================

-- (1) OFFSET 방식 — 마지막 페이지
EXPLAIN (ANALYZE, COSTS OFF)
SELECT order_id, customer_id, amount
  FROM lab.orders
 ORDER BY order_id
 LIMIT 10 OFFSET 2990;

-- (2) Keyset 방식 — 직전 페이지 마지막 order_id 를 조건으로 전달
EXPLAIN (ANALYZE, COSTS OFF)
SELECT order_id, customer_id, amount
  FROM lab.orders
 WHERE order_id > 2990
 ORDER BY order_id
 LIMIT 10;

-- (3) 두 방식의 결과가 동일한지 확인
SELECT order_id, customer_id, amount
  FROM lab.orders
 WHERE order_id > 2990
 ORDER BY order_id
 LIMIT 5;


-- =====================================================================
--  25-3. FK 컬럼 인덱스 점검
--
--  PostgreSQL 은 FK 제약을 걸어도 참조하는 쪽 컬럼에 인덱스를 자동으로
--  만들지 않는다(PK/UNIQUE 는 자동 생성). 인덱스가 없으면
--    · 부모 행 DELETE/UPDATE 시 자식 테이블 전체 스캔
--    · ON DELETE CASCADE 에서 특히 치명적
--    · FK 기준 조인이 Seq Scan
--  아래 쿼리로 누락된 FK 인덱스를 한 번에 찾을 수 있다.
-- =====================================================================
SELECT c.conrelid::regclass         AS 테이블,
       a.attname                    AS FK컬럼,
       c.confrelid::regclass        AS 참조대상,
       EXISTS (SELECT 1
                 FROM pg_index i
                WHERE i.indrelid = c.conrelid
                  AND a.attnum   = i.indkey[0]) AS 선두컬럼인덱스존재
  FROM pg_constraint c
  JOIN unnest(c.conkey) AS k(attnum) ON TRUE
  JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = k.attnum
 WHERE c.contype = 'f'
   AND c.connamespace = 'lab'::regnamespace
 ORDER BY 1, 2;


-- =====================================================================
--  25-4. 조인 전략 — Nested Loop vs Hash
--
--  작은 테이블 × 큰 테이블 + 인덱스  → Nested Loop
--  대형 × 대형(동등 조인)            → Hash Join
--  옵티마이저가 통계를 보고 고르므로 힌트가 아니라 조건·인덱스로 유도한다.
--
--  Hash Batches > 1 이면 work_mem 부족으로 디스크에 spill 된 것이다.
--  이 실습 데이터는 최대 3,000행이라 Batches 는 항상 1 로 나온다.
-- =====================================================================

-- (1) 대형 × 대형 전체 조인 → Hash Join (Batches 값을 확인할 것)
EXPLAIN (ANALYZE, COSTS OFF)
SELECT c.customer_name, SUM(o.amount) AS 총액
  FROM lab.customers c
  JOIN lab.orders    o ON o.customer_id = c.customer_id
 GROUP BY c.customer_name;

-- (2) 선택도 높은 조건 → Nested Loop + Index Scan
--     ix_orders_customer 인덱스를 타고 필요한 몇 건만 읽는다.
EXPLAIN (ANALYZE, COSTS OFF)
SELECT c.customer_name, o.order_id, o.amount
  FROM lab.customers c
  JOIN lab.orders    o ON o.customer_id = c.customer_id
 WHERE c.customer_id = 1;

-- (3) ON 조건 누락 시 발생할 카르테시안 곱 규모
--     실제로 실행하지 않고 곱셈으로만 확인한다.
--     500 × 3,000 = 1,500,000 행 — 정상 조인의 500배다.
SELECT (SELECT COUNT(*) FROM lab.customers)
     * (SELECT COUNT(*) FROM lab.orders)   AS 카르테시안_예상행수,
       (SELECT COUNT(*) FROM lab.orders)   AS 정상조인_행수,
       (SELECT COUNT(*) FROM lab.customers)
     * (SELECT COUNT(*) FROM lab.orders)
     / (SELECT COUNT(*) FROM lab.orders)   AS 배수;


-- =====================================================================
--  25-5. LATERAL JOIN — 행별 독립 서브쿼리
--
--  일반 서브쿼리는 FROM 절에서 바깥 테이블의 컬럼을 참조할 수 없다.
--  LATERAL 을 붙이면 왼쪽에서 나온 행마다 서브쿼리가 다시 실행되면서
--  그 행의 값을 참조할 수 있다. 사실상 "행별 for 문" 이다.
--
--  대표 용례가 그룹별 상위 N건(top-N-per-group)이다.
--  Q23 의 윈도우 함수 방식과 결과는 같지만 처리 방식이 다르다.
--    윈도우 : 전체 1,000행에 순위를 매긴 뒤 rn <= 3 으로 거른다
--    LATERAL: 학과마다 인덱스를 타고 상위 3건만 읽고 멈춘다
--  ix_student_major_gpa (Q23 에서 생성) 가 있으면 후자가 훨씬 적게 읽는다.
-- =====================================================================
SELECT m.major        AS 학과,
       t.student_id,
       t.name,
       t.gpa
  FROM (SELECT DISTINCT major FROM lab.student) m
 CROSS JOIN LATERAL (SELECT s.student_id,
                            s.name,
                            s.gpa
                       FROM lab.student s
                      WHERE s.major = m.major
                      ORDER BY s.gpa DESC, s.student_id
                      LIMIT 3) t
 ORDER BY m.major, t.gpa DESC, t.student_id;

-- LATERAL 실행계획 — 학과 6개에 대해 Limit 이 6번 실행(loops=6)된다
EXPLAIN (ANALYZE, COSTS OFF)
SELECT m.major, t.student_id, t.gpa
  FROM (SELECT DISTINCT major FROM lab.student) m
 CROSS JOIN LATERAL (SELECT s.student_id, s.gpa
                       FROM lab.student s
                      WHERE s.major = m.major
                      ORDER BY s.gpa DESC, s.student_id
                      LIMIT 3) t;


-- =====================================================================
--  25-6. 통계 테이블 전략 — Materialized View
--
--  자주 쓰는 집계값을 매번 계산하지 않고 미리 저장해 둔다.
--  일반 뷰(VIEW)는 조회할 때마다 원본을 다시 집계하지만,
--  Materialized View 는 결과를 물리적으로 저장한다.
--
--  대가 : 원본이 바뀌어도 자동 갱신되지 않는다. REFRESH 를 걸어야 한다.
--         갱신 주기만큼 데이터가 낡는다(stale). 실시간성이 필요하면
--         트리거로 증분 갱신하는 통계 테이블 방식을 쓴다.
--
--  UNIQUE 인덱스가 있어야 REFRESH ... CONCURRENTLY 를 쓸 수 있다.
--  CONCURRENTLY 는 갱신 중에도 조회를 막지 않는다.
--
--  참고 : 강의자료 예시의 last_order_date 는 orders 에 날짜 컬럼이 없어
--         만들 수 없으므로 최근 주문번호(MAX(order_id))로 대체했다.
-- =====================================================================
CREATE MATERIALIZED VIEW IF NOT EXISTS lab.mv_customer_stats AS
SELECT c.customer_id,
       c.customer_name,
       COUNT(o.order_id)               AS total_orders,
       COALESCE(SUM(o.amount), 0)      AS total_amount,
       MAX(o.order_id)                 AS last_order_id
  FROM lab.customers c
  LEFT JOIN lab.orders o ON o.customer_id = c.customer_id
 GROUP BY c.customer_id, c.customer_name;

CREATE UNIQUE INDEX IF NOT EXISTS ux_mv_customer_stats
    ON lab.mv_customer_stats (customer_id);

REFRESH MATERIALIZED VIEW lab.mv_customer_stats;

-- 조회 — 원본 집계 없이 저장된 결과를 그대로 읽는다
SELECT customer_id,
       customer_name,
       total_orders,
       total_amount,
       last_order_id
  FROM lab.mv_customer_stats
 ORDER BY total_amount DESC
 LIMIT 5;

-- 원본 집계와 실행계획 비교 — MV 쪽에 HashAggregate 가 없다
EXPLAIN (ANALYZE, COSTS OFF)
SELECT customer_id, total_amount FROM lab.mv_customer_stats ORDER BY total_amount DESC LIMIT 5;

EXPLAIN (ANALYZE, COSTS OFF)
SELECT c.customer_id, COALESCE(SUM(o.amount), 0) AS total_amount
  FROM lab.customers c
  LEFT JOIN lab.orders o ON o.customer_id = c.customer_id
 GROUP BY c.customer_id
 ORDER BY total_amount DESC
 LIMIT 5;


-- =====================================================================
--  25-7. STRING_AGG / ARRAY_AGG / JSON_AGG 비교
--
--  셋 다 그룹 안의 여러 행을 값 하나로 합치는 집계 함수다. 차이는 반환 타입이다.
--    STRING_AGG : text   — 사람이 읽는 리포트용. 구분자 지정 필수.
--    ARRAY_AGG  : 배열   — 첨자 접근·길이·ANY 조건 등 후속 연산 가능.
--    JSON_AGG   : json   — 여러 컬럼을 객체로 묶어 API 응답 형태로 전달.
--
--  공통 주의
--    · 집계 함수 안에 ORDER BY 를 넣어야 순서가 고정된다.
--    · NULL 은 건너뛴다. 모두 NULL 인 그룹은 결과 자체가 NULL 이 된다.
--    · DISTINCT 를 안에 쓸 수 있다 — STRING_AGG(DISTINCT course, ', ')
-- =====================================================================
SELECT s.student_id,
       s.name,
       STRING_AGG(e.course, ', ' ORDER BY e.course)            AS 과목_문자열,
       ARRAY_AGG(e.course ORDER BY e.course)                   AS 과목_배열,
       JSON_AGG(JSON_BUILD_OBJECT('course', e.course,
                                  'grade',  e.grade)
                ORDER BY e.course)                             AS 과목_JSON
  FROM lab.student s
  JOIN lab.enroll  e ON e.student_id = s.student_id
 GROUP BY s.student_id, s.name
 ORDER BY s.student_id
 LIMIT 5;

-- ARRAY_AGG 만 가능한 후속 연산 — 첨자 접근·길이·포함 여부 판정
--   문자열이었다면 LIKE 로 부분 일치를 봐야 해서 'Course_1' 이
--   'Course_10' 에도 걸리는 오탐이 생긴다. 배열은 원소 단위로 정확히 비교한다.
SELECT s.student_id,
       s.name,
       ARRAY_AGG(e.course ORDER BY e.course)          AS 과목_배열,
       (ARRAY_AGG(e.course ORDER BY e.course))[1]     AS 첫과목,
       ARRAY_LENGTH(ARRAY_AGG(e.course), 1)           AS 과목수
  FROM lab.student s
  JOIN lab.enroll  e ON e.student_id = s.student_id
 GROUP BY s.student_id, s.name
HAVING 'DB' = ANY (ARRAY_AGG(e.course))
 ORDER BY s.student_id
 LIMIT 5;
