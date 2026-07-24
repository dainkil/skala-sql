-- Q27. 인덱스 설계 — WHERE · JOIN 컬럼 복합 인덱스 (Q11 대상)
--   목적 : Q23 이 ORDER BY 축을 다뤘다면, 여기서는 WHERE + JOIN 조건을
--          한 인덱스로 동시에 처리하는 복합 인덱스를 설계한다.
--
--   대상 : Q11 의 상관 서브쿼리. 조건이 두 개다.
--            e.student_id = s.student_id   ← JOIN 컬럼 (바깥 행마다 값이 바뀜)
--            e.course     = 'DB'           ← WHERE 컬럼 (상수)
--          현재 lab.enroll 에는 ix_enroll_student (student_id) 하나뿐이라
--          course 조건은 인덱스로 좁히지 못하고 읽어온 뒤 버려진다.
--
--   결론 먼저 : 만들 인덱스는 (course, student_id) 다. 순서가 반대면 효과가 절반이다.
--               근거는 (5) 에서 두 순서를 직접 비교한다.
--
--   실행 순서 : (2) 전 → (3) 생성 → (4) 후. 인덱스가 없는 상태에서 시작해야
--               비교가 성립한다. 다시 캡처하려면 맨 아래 (9) 롤백을 먼저 실행할 것.
--
--   데이터 규모 : enroll 1,002행 / 144 kB, 그중 course='DB' 는 47행(4.7%).
--                 소형 데이터라 실행시간 차이는 0.1 ms 수준으로 묻힌다.
--                 그래서 시간이 아니라 BUFFERS(읽은 블록 수)와 실행계획의
--                 노드 구성을 근거로 삼는다. 이 두 지표는 규모와 무관하게 정직하다.


-- =====================================================================
--  (1) 현황 점검 — 시작 상태를 캡처로 남긴다
-- =====================================================================
SELECT indexname   AS 인덱스,
       indexdef    AS 정의
  FROM pg_indexes
 WHERE schemaname = 'lab' AND tablename = 'enroll'
 ORDER BY indexname;
-- 기대 : ix_enroll_student 한 건. (course 를 다루는 인덱스가 없다)


-- =====================================================================
--  (2) 인덱스 생성 전 실행계획
--
--  BUFFERS 를 켜는 이유 : 실행시간은 캐시 상태·서버 부하에 따라 실행할 때마다
--  흔들리지만, 읽은 블록 수는 같은 계획이면 항상 같다. 재현 가능한 근거다.
--
--  볼 곳 세 군데
--    ① enroll 접근 노드가 Seq Scan 인가
--    ② Rows Removed by Filter — 읽고 나서 버린 행 수
--    ③ Sort 노드가 있는가
-- =====================================================================
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT s.student_id,
       s.name,
       s.major,
       s.gpa
  FROM lab.student s
 WHERE NOT EXISTS (SELECT 1
                     FROM lab.enroll e
                    WHERE e.student_id = s.student_id
                      AND e.course     = 'DB')
 ORDER BY s.student_id;

-- 실측 결과 (PostgreSQL 17)
--   Merge Anti Join  rows=953   Buffers: shared hit=30
--     -> Index Scan using student_pkey on student   rows=1000   hit=12
--     -> Sort   rows=47   quicksort Memory: 25kB    hit=18      ← ③ 정렬 발생
--          -> Seq Scan on enroll                                ← ① 전체 스캔
--               Filter: (course = 'DB')
--               Rows Removed by Filter: 955                     ← ② 95%를 버림
--
--   1,002행을 다 읽어 955행을 버리고, 남은 47행을 student_id 로 정렬한다.
--   Merge Anti Join 은 양쪽이 정렬되어 있어야 하는데 Seq Scan 결과는
--   정렬되어 있지 않으므로 Sort 노드가 끼어든 것이다.


-- =====================================================================
--  (3) 인덱스 생성
--
--  컬럼 순서 (course, student_id) 의 근거
--    복합 인덱스는 선두 컬럼부터 왼쪽으로 연속해서만 탐색 범위를 좁힐 수 있다.
--    course = 'DB' 는 상수 등치 조건이라 인덱스 안의 한 구간을 바로 지목한다.
--    반면 student_id 는 바깥 행마다 값이 달라 범위를 미리 고정할 수 없다.
--    → 범위를 확정할 수 있는 상수 조건을 선두에 둔다.
--
--    두 번째 컬럼 student_id 를 넣는 이유는 두 가지다.
--      · 조인에 필요한 값이 인덱스 안에 다 있어 테이블(heap)을 안 읽어도 된다
--        → Index Only Scan
--      · course='DB' 구간 안에서 student_id 순으로 이미 정렬되어 있다
--        → Merge Anti Join 이 요구하는 정렬을 인덱스가 대신 제공, Sort 노드 소멸
--
--  ANALYZE 를 같이 실행하는 이유 : 옵티마이저는 통계를 보고 계획을 세운다.
--  인덱스를 만들어도 통계가 낡아 있으면 새 경로를 고려하지 않을 수 있다.
-- =====================================================================
CREATE INDEX IF NOT EXISTS ix_enroll_course_student
    ON lab.enroll (course, student_id);

ANALYZE lab.enroll;


-- =====================================================================
--  (4) 인덱스 생성 후 실행계획 — (2) 와 완전히 같은 쿼리
-- =====================================================================
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT s.student_id,
       s.name,
       s.major,
       s.gpa
  FROM lab.student s
 WHERE NOT EXISTS (SELECT 1
                     FROM lab.enroll e
                    WHERE e.student_id = s.student_id
                      AND e.course     = 'DB')
 ORDER BY s.student_id;

-- 실측 결과
--   Merge Anti Join  rows=953   Buffers: shared hit=13 read=2
--     -> Index Scan using student_pkey on student   rows=1000   hit=12
--     -> Index Only Scan using ix_enroll_course_student on enroll
--          Index Cond: (course = 'DB')
--          rows=47   Heap Fetches: 0   Buffers: hit=1 read=2
--                                                              ← Sort 노드 없음
--
--   전 / 후 비교 (enroll 접근 부분만)
--     ┌──────────────────────┬───────────────┬──────────────────────┐
--     │                      │ 인덱스 없음   │ (course, student_id) │
--     ├──────────────────────┼───────────────┼──────────────────────┤
--     │ 접근 방식            │ Seq Scan      │ Index Only Scan      │
--     │ 읽은 블록            │ 18            │ 3                    │
--     │ 읽고 버린 행         │ 955           │ 0                    │
--     │ 테이블(heap) 접근    │ 전부          │ 0 (Heap Fetches: 0)  │
--     │ Sort 노드            │ 있음          │ 없음                 │
--     └──────────────────────┴───────────────┴──────────────────────┘
--
--   결과 행 수는 953 으로 동일하다. 인덱스는 성능만 바꾸고 결과를 바꾸지 않는다.
--   이 확인을 빠뜨리면 안 된다. 결과가 달라졌다면 인덱스가 아니라 쿼리를 잘못 고친 것이다.
--
--   Heap Fetches: 0 의 의미
--     인덱스에 필요한 컬럼이 다 있어도 PostgreSQL 은 그 행이 현재 트랜잭션에서
--     보이는지 확인해야 하고, 그 정보는 원래 테이블에 있다. visibility map 이
--     "이 페이지는 전부 보인다" 고 표시된 페이지만 테이블 접근을 건너뛴다.
--     방금 ANALYZE(내부적으로 VACUUM 계열 갱신)를 돌렸기에 0 이 나왔다.
--     대량 INSERT 직후라면 이 값이 0 이 아닐 수 있다.


-- =====================================================================
--  (5) 컬럼 순서를 반대로 했다면 — (student_id, course)
--
--  둘 다 "인덱스를 탄다". 실행계획만 보면 똑같이 Index Only Scan 이라
--  성공한 것처럼 보인다. 차이는 읽은 블록 수에서만 드러난다.
--
--  실측 (같은 Q11 쿼리, (student_id, course) 인덱스만 있는 상태)
--    -> Index Only Scan using ix_enroll_student_course
--         Index Cond: (course = 'DB')
--         rows=47   Heap Fetches: 0   Buffers: hit=4 read=2   ← 6블록
--
--    (course, student_id) 는 3블록, (student_id, course) 는 6블록.
--    인덱스 크기가 48 kB = 6페이지이므로 후자는 인덱스를 통째로 읽은 것이다.
--    선두 컬럼이 student_id 라 course='DB' 로는 시작 지점을 정할 수 없고,
--    모든 엔트리를 훑으며 두 번째 컬럼을 대조하는 수밖에 없다.
--
--  즉 "Index Only Scan 이 떴다" 는 성공의 증거가 아니다. Index Cond 가
--  탐색 범위를 실제로 좁혔는지는 읽은 블록 수로만 확인할 수 있다.
--
--  직접 확인하려면 아래 세 줄을 순서대로 실행한다.
--    CREATE INDEX ix_tmp_reverse ON lab.enroll (student_id, course);
--    -- (2) 의 EXPLAIN 을 다시 실행 → 어느 인덱스를 고르는지, 블록 수는 몇인지
--    DROP INDEX lab.ix_tmp_reverse;
-- =====================================================================


-- =====================================================================
--  (6) 기존 ix_enroll_student 는 중복인가 — 아니다
--
--  복합 인덱스를 만들면 기존 단일 인덱스가 흡수되는 경우가 있다.
--  판정 기준은 하나다. 기존 인덱스의 컬럼이 새 인덱스의 왼쪽 접두사인가.
--
--    ix_enroll_student (student_id)
--    ix_enroll_course_student (course, student_id)   ← 선두가 course
--
--  student_id 는 선두가 아니므로 접두사가 아니다. 따라서 흡수되지 않는다.
--  만약 (5) 처럼 (student_id, course) 를 만들었다면 그때는 ix_enroll_student
--  가 완전한 중복이 되어 지울 수 있었다.
--
--  아래 쿼리로 확인한다 — student_id 단독 조회는 여전히 기존 인덱스를 쓴다.
-- =====================================================================
EXPLAIN (COSTS OFF)
SELECT student_id, course
  FROM lab.enroll
 WHERE student_id = 500;
-- 실측 : Index Scan using ix_enroll_student   Index Cond: (student_id = 500)
--
--   두 인덱스는 서로 다른 접근 경로를 담당한다.
--     ix_enroll_student        → 학생 기준 조인 (Q01·Q02·Q05·Q06·Q10·Q24)
--     ix_enroll_course_student → 과목 조건 조회 (Q11)

-- 실제로 쓰이는지 사용 횟수로 점검 — idx_scan 이 0 인 인덱스는 제거 후보다.
--   주의 ① 통계는 서버 재시작이나 pg_stat_reset() 이후 누적분이다.
--           쌓인 기간이 짧으면 0 이어도 "안 쓰는 인덱스" 라고 단정할 수 없다.
--   주의 ② 방금 만든 ix_enroll_course_student 는 (4) 에서 분명히 쓰였는데도
--           여기서 0 으로 보인다. 통계는 즉시 기록되지 않고 주기적으로
--           반영되기 때문이다. 잠시 후 다시 조회하면 값이 올라간다.
--           "안 쓰이네" 라고 판단하기 전에 이 지연을 감안해야 한다.
SELECT indexrelname                                AS 인덱스,
       idx_scan                                    AS 사용횟수,
       pg_size_pretty(pg_relation_size(indexrelid)) AS 크기
  FROM pg_stat_user_indexes
 WHERE schemaname = 'lab' AND relname = 'enroll'
 ORDER BY idx_scan DESC;


-- =====================================================================
--  (7) 인덱스가 듣지 않는 경우 — 만들기 전에 알아야 할 것
--
--  ① 옵티마이저가 상관 서브쿼리를 해시로 바꿔버린 경우 (Q13)
--     Q13 은 CROSS JOIN 1,000명 × 23과목 = 23,000행 각각에 EXISTS 가 붙는다.
--     23,000번 탐색할 것 같지만 실행계획을 보면 그렇지 않다.
--       SubPlan 2
--         -> Seq Scan on enroll   rows=1002   loops=1     ← loops 가 1이다
--     PostgreSQL 이 서브쿼리를 해시 테이블로 한 번만 만들어 두고 23,000번
--     조회한다. 이미 스캔이 1회뿐이라 인덱스로 줄일 여지가 없다.
--     loops 값을 확인하지 않으면 "인덱스로 23,000번을 줄였다" 는
--     사실이 아닌 결론을 내리게 된다.
--
--  ② 테이블이 작아 Seq Scan 이 실제로 더 싼 경우
--     아래 DISTINCT 조회는 (course, student_id) 인덱스가 있어도 Seq Scan 이다.
--     1,002행이 18블록에 다 들어 있어 순차로 읽는 편이 빠르다.
--     옵티마이저의 판단이 옳다. 인덱스를 만들었는데 안 쓰인다면 먼저
--     "정말 쓸 필요가 있는 쿼리인가" 를 의심해야 한다.
--
--  ③ 이 밖에 인덱스를 못 타는 대표 패턴
--     · LIKE '%DB'      — 앞이 열려 있으면 시작 지점을 못 정한다
--     · UPPER(course) = 'DB' — 컬럼에 함수를 씌우면 원본 값 기준 인덱스는 무용.
--                              필요하면 표현식 인덱스를 따로 만든다
--     · 선두 컬럼 조건 누락 — (5) 에서 본 그대로
-- =====================================================================
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT DISTINCT course
  FROM lab.enroll
 WHERE course IS NOT NULL;
-- 실측 : HashAggregate -> Seq Scan on enroll  Buffers: shared hit=18
--        (인덱스가 있어도 선택되지 않는다)


-- =====================================================================
--  (8) 인덱스의 대가 — 공짜가 아니다
--
--  · 저장공간 : 인덱스는 별도 자료구조라 디스크를 추가로 쓴다.
--  · 쓰기비용 : INSERT/UPDATE/DELETE 마다 해당 테이블의 모든 인덱스를 갱신한다.
--               인덱스 5개면 INSERT 한 건에 쓰기가 6번 일어난다.
--               조회는 빨라지고 쓰기는 느려지는 교환이다.
--  · 그래서 "일단 다 걸어두자" 는 설계가 아니다. 실제 조회 패턴에
--    대응하는 인덱스만 만들고, (6) 처럼 사용 횟수로 주기적으로 점검한다.
-- =====================================================================
SELECT pg_size_pretty(pg_relation_size('lab.enroll'))                AS 테이블,
       pg_size_pretty(pg_indexes_size('lab.enroll'))                 AS 인덱스합계,
       ROUND(100.0 * pg_indexes_size('lab.enroll')
                   / NULLIF(pg_relation_size('lab.enroll'), 0), 1)   AS 인덱스비율_퍼센트;
-- 실측 : 테이블 144 kB / 인덱스 합계는 생성 후 약 144 kB (100% 수준)
--   ix_enroll_student 96 kB 가 (course, student_id) 48 kB 의 두 배인 점에 주의.
--   컬럼이 하나 더 적은데 크기는 두 배다. 04_lab_data_fix.sql 에서 enroll 을
--   전량 DELETE 후 재적재하면서 기존 인덱스에 빈 공간(bloat)이 남았기 때문이다.
--   REINDEX INDEX lab.ix_enroll_student; 로 회수할 수 있다.


-- =====================================================================
--  (9) 롤백 — 전/후 비교를 다시 캡처할 때 먼저 실행한다
--
--  Q23 의 ix_student_major_gpa 와 같은 방식이다. 실습 도중 실수로 실행되지
--  않도록 주석으로 둔다. 필요할 때 주석을 풀어 실행할 것.
-- =====================================================================
--
-- DROP INDEX IF EXISTS lab.ix_enroll_course_student;
-- ANALYZE lab.enroll;
