-- Q22. 조직 계층 탐색 (WITH RECURSIVE) — CEO → 매니저 → 개발자 3단계
--   구조 : anchor(시작점) UNION ALL recursive(직전 결과와 조인) 형태.
--          직전 회차 결과가 비면 반복이 끝난다.
--   주의 : UNION ALL 이어야 한다. UNION 은 매 회차 중복 제거가 들어가 느려진다.
--          anchor 의 name 은 varchar 라 path 를 이어붙이려면 text 로 캐스팅한다.
--          순환 참조가 있는 데이터라면 무한 반복을 막는 depth 상한이 필요하다.
WITH RECURSIVE org AS (
    -- anchor : manager_id 가 NULL 인 최상위(CEO)
    SELECT e.emp_id,
           e.name,
           e.manager_id,
           0            AS depth,
           e.name::text AS path
      FROM lab.emp e
     WHERE e.manager_id IS NULL
    UNION ALL
    -- recursive : 직전 회차에서 찾은 사람의 부하 직원
    SELECT e.emp_id,
           e.name,
           e.manager_id,
           o.depth + 1,
           o.path || ' > ' || e.name
      FROM lab.emp e
      JOIN org     o ON o.emp_id = e.manager_id
)
SELECT emp_id,
       name,
       manager_id,
       depth,
       path
  FROM org
 ORDER BY path   -- depth 순으로 정렬하면 상위 몇 건에 CEO·매니저만 잡혀
                 -- 3단계 경로가 화면에 안 나온다. path 순은 트리를 따라
                 -- 내려가므로 depth 0·1·2 가 한 화면에 섞여 보인다.
 LIMIT 5;   -- 화면 캡처용 (전체 311명)

-- 참고 : 깊이별 인원 — CEO 1 / 매니저 10 / 개발자 300 으로 나뉘는지 확인
WITH RECURSIVE org AS (
    SELECT emp_id, manager_id, 0 AS depth FROM lab.emp WHERE manager_id IS NULL
    UNION ALL
    SELECT e.emp_id, e.manager_id, o.depth + 1
      FROM lab.emp e JOIN org o ON o.emp_id = e.manager_id
)
SELECT depth, COUNT(*) AS 인원 FROM org GROUP BY depth ORDER BY depth;

-- 매니저별 직속 부하 직원 수 (별도 쿼리)
--   셀프 조인 + 집계. 부하가 0명인 직원까지 세지 않도록 HAVING 으로 거른다.
SELECT m.emp_id,
       m.name            AS manager_name,
       COUNT(e.emp_id)   AS direct_reports
  FROM lab.emp m
  LEFT JOIN lab.emp e ON e.manager_id = m.emp_id
 GROUP BY m.emp_id, m.name
HAVING COUNT(e.emp_id) > 0
 ORDER BY direct_reports DESC, m.emp_id;

-- ============================================================
-- 실행계획 확인 (EXPLAIN ANALYZE)
-- ============================================================
-- 재귀 쿼리 실행계획.
--   읽는 법 : Recursive Union 아래 WorkTable Scan 의 loops 값 = 반복 횟수.
--             CEO(1) → 매니저(10) → 개발자(300) → 0건 이라 loops = 3 (3단계 계층).
--   포인트 : ① Recursive Union 의 예상 Rows(≈2821) 는 실제(311) 와 크게 다르다.
--               재귀 CTE 는 통계가 없어 planner 가 고정 배수로 추정 → 과대추정이 정상.
--            ② ix_emp_manager 인덱스가 안 쓰이고 Seq Scan + Hash Join 이 선택된다.
--               311행짜리 작은 테이블이라 전체 스캔이 인덱스 탐색보다 싸기 때문.
--               데이터가 커지면 재귀 항이 Index Scan(ix_emp_manager) 으로 바뀐다.
--            ③ 가장 비싼 노드는 ORDER BY path 의 Sort 지만 311행이라 4ms 안쪽.
EXPLAIN (ANALYZE, BUFFERS)
WITH RECURSIVE org AS (
    SELECT e.emp_id, e.name, e.manager_id, 0 AS depth, e.name::text AS path
      FROM lab.emp e WHERE e.manager_id IS NULL
    UNION ALL
    SELECT e.emp_id, e.name, e.manager_id, o.depth + 1, o.path || ' > ' || e.name
      FROM lab.emp e JOIN org o ON o.emp_id = e.manager_id
)
SELECT emp_id, name, manager_id, depth, path FROM org ORDER BY path;

-- 매니저별 직속 부하 수 실행계획.
--   셀프 조인이 Hash Join 으로 처리되고, HAVING 은 Aggregate 노드의 Filter 로 붙는다.
--   여기도 작은 테이블이라 양쪽 다 Seq Scan → Hash Join. 0.3ms 수준.
EXPLAIN (ANALYZE, BUFFERS)
SELECT m.emp_id,
       m.name            AS manager_name,
       COUNT(e.emp_id)   AS direct_reports
  FROM lab.emp m
  LEFT JOIN lab.emp e ON e.manager_id = m.emp_id
 GROUP BY m.emp_id, m.name
HAVING COUNT(e.emp_id) > 0
 ORDER BY direct_reports DESC, m.emp_id;
