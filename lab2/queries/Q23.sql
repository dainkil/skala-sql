-- Q23. 학과별 GPA 순위 상위 3명 (Window Function · 서브쿼리/CTE 두 방식)
--   목적 : 순위 함수는 WHERE 절에서 쓸 수 없다. WHERE 가 SELECT 보다 먼저
--          평가되어 그 시점에는 순위가 아직 계산되지 않았기 때문이다.
--          그래서 한 단계 감싸서(서브쿼리 또는 CTE) 바깥에서 걸러야 한다.
--   순위 3종 차이 (GPA 4.5, 4.5, 4.2 일 때)
--     ROW_NUMBER  1, 2, 3  — 동점이어도 무조건 다른 번호
--     RANK        1, 1, 3  — 동점은 같은 순위, 다음은 건너뜀
--     DENSE_RANK  1, 1, 2  — 동점은 같은 순위, 다음은 안 건너뜀
--   설계 : ROW_NUMBER 는 student_id 2차 정렬로 순번을 확정하고,
--          RANK/DENSE_RANK 는 gpa 만으로 정렬해야 동점 처리 차이가 드러난다.

-- 방식 A : 인라인 뷰(서브쿼리)
SELECT t.major,
       t.rn        AS 순위,
       t.student_id,
       t.name,
       t.gpa,
       t.rnk       AS RANK값,
       t.dense_rnk AS DENSE_RANK값,
       t.total_in_major
  FROM (SELECT s.student_id,
               s.name,
               s.major,
               s.gpa,
               ROW_NUMBER() OVER (PARTITION BY s.major ORDER BY s.gpa DESC, s.student_id) AS rn,
               RANK()       OVER (PARTITION BY s.major ORDER BY s.gpa DESC)               AS rnk,
               DENSE_RANK() OVER (PARTITION BY s.major ORDER BY s.gpa DESC)               AS dense_rnk,
               COUNT(*)     OVER (PARTITION BY s.major)                                   AS total_in_major
          FROM lab.student s) t
 WHERE t.rn <= 3
 ORDER BY t.major, t.rn;

-- 방식 B : CTE (WITH) — 결과는 동일하고 가독성과 재사용성이 낫다
WITH ranked AS (
    SELECT s.student_id,
           s.name,
           s.major,
           s.gpa,
           ROW_NUMBER() OVER (PARTITION BY s.major ORDER BY s.gpa DESC, s.student_id) AS rn,
           RANK()       OVER (PARTITION BY s.major ORDER BY s.gpa DESC)               AS rnk,
           DENSE_RANK() OVER (PARTITION BY s.major ORDER BY s.gpa DESC)               AS dense_rnk,
           COUNT(*)     OVER (PARTITION BY s.major)                                   AS total_in_major
      FROM lab.student s
)
SELECT major,
       rn        AS 순위,
       student_id,
       name,
       gpa,
       rnk       AS RANK값,
       dense_rnk AS DENSE_RANK값,
       total_in_major
  FROM ranked
 WHERE rn <= 3
 ORDER BY major, rn;


-- =====================================================================
--  성능 : ORDER BY 를 인덱스로 대체해 Sort 노드 제거
--
--  윈도우 함수의 PARTITION BY / ORDER BY 는 정렬을 전제로 한다.
--  적절한 인덱스가 없으면 실행계획에 Sort 노드가 들어가고
--  행 수가 늘어날수록 정렬 비용이 지배적이 된다.
--
--  인덱스 컬럼 순서는 PARTITION BY 컬럼 → ORDER BY 컬럼 순이어야 한다.
--  정렬 방향(DESC)까지 맞춰야 역방향 스캔 없이 그대로 읽을 수 있다.
--  강의자료의 INDEX(dept_id, salary DESC) 와 같은 형태다.
-- =====================================================================

-- (1) 인덱스 없는 상태의 실행계획 — Sort 노드 확인
EXPLAIN (ANALYZE, COSTS OFF)
SELECT student_id, name, major, gpa,
       ROW_NUMBER() OVER (PARTITION BY major ORDER BY gpa DESC, student_id) AS rn
  FROM lab.student;

-- (2) 인덱스 생성
CREATE INDEX IF NOT EXISTS ix_student_major_gpa
    ON lab.student (major, gpa DESC, student_id);

ANALYZE lab.student;

-- (3) 인덱스 적용 후 실행계획 — Sort 가 사라지고 Index Scan 으로 바뀐다
EXPLAIN (ANALYZE, COSTS OFF)
SELECT student_id, name, major, gpa,
       ROW_NUMBER() OVER (PARTITION BY major ORDER BY gpa DESC, student_id) AS rn
  FROM lab.student;
