-- ============================================================
--  SKALA SQL 종합실습 2 — 배경(요구사항) 기준 데이터 보정
--  대상 : PostgreSQL 17 / skala_db / 스키마 lab
--  실행 : psql skala_db -v ON_ERROR_STOP=1 -f 00_data_fix.sql
--
--  배포된 적재 스크립트가 배경 문서의 규칙과 달라 두 곳을 보정한다.
--    (1) enroll : 학생당 수강 건수 규칙을 student_id % 3 기준으로 재적재
--    (2) emp    : 직원(Dev)의 manager_id 가 CEO(1)를 포함하는 오류 교정
--  customers / orders(고객당 6건), 고아 수강 2건, 인원 구성은 이미 충족하므로
--  손대지 않는다.
-- ============================================================

SET search_path TO lab, public;

BEGIN;

-- ─────────────────────────────────────────────
-- (1) enroll 재적재 — 배경: 규칙상 수강은 학생당 0~2건
--       student_id % 3 = 0 → 0건 (333명)
--                      = 1 → 1건 (334명)
--                      = 2 → 2건 (333명)
--     course / grade 파생 규칙은 원본 스크립트와 동일하게 유지하여
--     'DB' 과목 등 JOIN 실습용 데이터 특성을 보존한다.
-- ─────────────────────────────────────────────

-- 기존 수강 데이터 전체 제거 (고아 2건 포함 — 아래에서 다시 넣는다)
DELETE FROM lab.enroll
 WHERE student_id IS NOT NULL;

INSERT INTO lab.enroll (student_id, course, grade)
SELECT s.student_id,
       CASE WHEN ((s.student_id + k) % 21) = 0 THEN 'DB'
            ELSE 'Course_' || (((s.student_id + k) % 20) + 1)
       END,
       (ARRAY['A','B','C','D'])[((s.student_id + k) % 4) + 1]
  FROM lab.student s
  JOIN LATERAL generate_series(
         1,
         CASE WHEN (s.student_id % 3) = 0 THEN 0    -- 수강 없음
              WHEN (s.student_id % 3) = 1 THEN 1
              ELSE 2 END
       ) AS g(k) ON TRUE;

-- 배경: 고아 수강(enroll 에만 존재) 2건 — 학생 1001, 1010
INSERT INTO lab.enroll (student_id, course, grade)
VALUES (1001, 'AI', 'A'),
       (1010, 'ML', 'B');

-- ─────────────────────────────────────────────
-- (2) emp 매니저 배정 교정 — 배경: 각 직원은 매니저 10명 중 1명에게 배정
--     원본은 manager_id = 1+((gs-1)%10) 로 1~10 을 만들어
--     CEO(emp_id=1)에게 30명이 붙고 Mgr_11(emp_id=11)은 부하가 0명이 된다.
--     매니저의 실제 emp_id 범위는 2~11 이므로 1씩 올려 2~11 로 맞춘다.
-- ─────────────────────────────────────────────
UPDATE lab.emp
   SET manager_id = manager_id + 1
 WHERE emp_id BETWEEN 12 AND 311      -- 직원(Dev_*) 300명만 대상
   AND manager_id BETWEEN 1 AND 10;   -- 이미 교정된 경우 재실행돼도 안전

COMMIT;

-- ============================================================
--  검증
-- ============================================================

-- 검증 1: 학생당 수강 건수 분포가 student_id % 3 규칙과 일치하는지
SELECT s.student_id % 3            AS "student_id%3",
       e.cnt                       AS "수강건수",
       COUNT(*)                    AS "학생수"
  FROM lab.student s
  JOIN LATERAL (SELECT COUNT(*) AS cnt
                  FROM lab.enroll x
                 WHERE x.student_id = s.student_id) e ON TRUE
 GROUP BY 1, 2
 ORDER BY 1, 2;

-- 검증 2: 고아 수강(student 에 없는 학생) 목록
SELECT e.student_id, e.course, e.grade
  FROM lab.enroll e
  LEFT JOIN lab.student s ON s.student_id = e.student_id
 WHERE s.student_id IS NULL
 ORDER BY e.student_id;

-- 검증 3: 고객 1명당 주문 건수 분포 (전원 6건이어야 함)
SELECT t.cnt AS "고객당 주문건수", COUNT(*) AS "고객수"
  FROM (SELECT c.customer_id, COUNT(o.order_id) AS cnt
          FROM lab.customers c
          LEFT JOIN lab.orders o ON o.customer_id = c.customer_id
         GROUP BY c.customer_id) t
 GROUP BY t.cnt
 ORDER BY t.cnt;

-- 검증 4: 조직도 계층별 인원 (CEO 1 / 매니저 10 / 직원 300)
SELECT CASE WHEN emp_id = 1                 THEN '1. CEO'
            WHEN emp_id BETWEEN 2  AND 11   THEN '2. 매니저'
            ELSE                                 '3. 직원'
       END      AS "계층",
       COUNT(*) AS "인원"
  FROM lab.emp
 GROUP BY 1
 ORDER BY 1;

-- 검증 5: 매니저별 부하 직원 수 (매니저 10명이 각 30명씩, CEO 직속 직원 없음)
SELECT m.emp_id AS "상사 id", m.name AS "상사", COUNT(*) AS "부하 직원수"
  FROM lab.emp d
  JOIN lab.emp m ON m.emp_id = d.manager_id
 WHERE d.emp_id BETWEEN 12 AND 311
 GROUP BY m.emp_id, m.name
 ORDER BY m.emp_id;

-- 검증 6: 테이블별 총 건수
SELECT 'student'   AS "테이블", COUNT(*) AS "건수" FROM lab.student
UNION ALL SELECT 'enroll',    COUNT(*) FROM lab.enroll
UNION ALL SELECT 'customers', COUNT(*) FROM lab.customers
UNION ALL SELECT 'orders',    COUNT(*) FROM lab.orders
UNION ALL SELECT 'emp',       COUNT(*) FROM lab.emp
ORDER BY 1;
