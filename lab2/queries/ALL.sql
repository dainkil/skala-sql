-- =====================================================================
--  ALL.sql — SKALA SQL 종합실습 2 · 전체 문항 합본 (Q01 ~ Q26)
--
--  대상 : PostgreSQL 17 / skala_db / 스키마 lab
--  용도 : DBeaver 에서 연결을 한 번만 지정하고 문항별로 실행·캡처한다.
--
--  DBeaver 실행 방법
--    ⌘ + ↩  커서가 놓인 문장 하나만 실행 — 문항별 캡처는 이것만 쓰면 된다.
--    ⌥ + X (Execute script) 는 macOS 에서 특수문자 입력으로 가로채여
--    선택 영역이 지워질 수 있다. 쓰지 말고 우클릭 → Execute → Execute SQL Script
--    를 쓰거나, 문장을 순서대로 ⌘↩ 로 하나씩 실행한다.
--
--    · 실행 전 툴바에서 연결을 skala_db, 스키마를 lab 으로 지정할 것
--    · 설정에서 "Blank line is statement delimiter" 를 꺼두면
--      빈 줄에서 문장이 잘려 UNION 문법 에러가 나는 일을 막을 수 있다.
--
--  여러 문장을 순서대로 실행해야 하는 문항
--    · Q12    CREATE TABLE → CREATE INDEX → INSERT ON CONFLICT → SELECT
--    · Q26-6  CREATE MATERIALIZED VIEW → CREATE INDEX → REFRESH → SELECT
--    · Q27    EXPLAIN(전) → CREATE INDEX → EXPLAIN(후)
--      모두 IF NOT EXISTS / ON CONFLICT 라 ⌘↩ 로 위에서부터 눌러도 된다.
--
--  실행 순서 의존성
--    · Q12 → course_owner 테이블 + ix_course_owner_manager 생성
--    · Q23 → ix_student_major_gpa 생성
--    · Q26 은 위 둘을 전제로 한다.
--    · Q27 → ix_enroll_course_student 생성 (다른 문항이 전제하지는 않는다)
--    · Q23·Q27 의 EXPLAIN 전/후 비교는 인덱스가 없는 상태에서 시작해야 의미가 있다.
--      다시 캡처하려면 먼저
--        DROP INDEX IF EXISTS lab.ix_student_major_gpa;
--        DROP INDEX IF EXISTS lab.ix_enroll_course_student;
--
--  결과 건수
--    · 캡처 가독성을 위해 대부분 LIMIT 를 걸었다.
--    · Q08(상위 10명) · Q13(샘플 100건) 은 문항이 건수를 지정해 그대로 둔다.
--    · Q04 는 LIMIT 대신 구분별 ROW_NUMBER 로 2건씩 뽑아 6행을 만든다.
--      그냥 LIMIT 을 걸면 '양쪽매칭' 이 한 행도 안 나오기 때문이다.
--    · 집계·순위 문항(Q10 분포 · Q12 · Q21 · Q22 부하수 · Q23 · Q26)은
--      결과 전체가 답이므로 LIMIT 를 걸지 않는다.
-- =====================================================================


-- ###################################################################
-- #  Q01
-- ###################################################################
-- Q01. 학생·수강 INNER JOIN — 수강 기록이 있는 학생의 과목/성적 조회
--   목적 : INNER JOIN 은 양쪽 테이블에 짝이 모두 있는 행만 남긴다.
--          수강하지 않은 학생, 학생에 없는 수강행은 결과에서 사라진다.
SELECT s.student_id,
       s.name,
       s.major,
       e.course,
       e.grade
  FROM lab.student s
  JOIN lab.enroll  e ON e.student_id = s.student_id
 ORDER BY s.student_id, e.course
 LIMIT 5;   -- 화면 캡처용 (전체 1,000건)


-- ###################################################################
-- #  Q02
-- ###################################################################
-- Q02. LEFT JOIN — 모든 학생을 기준으로 수강 내역 붙이기 (없으면 NULL)
--   목적 : 왼쪽(student) 은 전부 남기고 오른쪽(enroll) 은 짝이 있을 때만 채운다.
--          수강 기록이 없는 학생은 course/grade 가 NULL 로 나온다.
--   정렬 : student_id 순으로 둔다.
--          course NULLS FIRST 로 정렬하면 미수강 학생 333명이 앞을 다 차지해
--          캡처에 NULL 행만 잡히고 조인이 실패한 것처럼 보인다.
--          student_id 순이면 매칭된 행과 NULL 행이 섞여 나와
--          "모든 학생을 남기되 짝이 없으면 NULL" 이라는 동작이 한눈에 보인다.
SELECT s.student_id,
       s.name,
       s.major,
       e.course,
       e.grade
  FROM lab.student s
  LEFT JOIN lab.enroll e ON e.student_id = s.student_id
 ORDER BY s.student_id, e.course
 LIMIT 20;   -- 화면 캡처용 (전체 1,333건 = 매칭 1,000 + 미수강 333)


-- ###################################################################
-- #  Q03
-- ###################################################################
-- Q03. RIGHT JOIN — 수강 기준, 학생 정보가 없으면 NULL
--   목적 : 오른쪽(enroll) 을 전부 남긴다. student 에 없는 student_id 를 가진
--          수강행(고아행) 이 드러나므로 참조무결성 점검에 쓸 수 있다.
--   참고 : enroll.student_id 에는 FK 제약이 없어 실제로 고아행 2건이 존재한다.
--   정렬 : 학생 정보가 비어 있는 행을 맨 위로 올려 캡처에 보이게 한다.
SELECT s.student_id,
       s.name,
       s.major,
       e.student_id AS enroll_student_id,
       e.course,
       e.grade
  FROM lab.student s
 RIGHT JOIN lab.enroll e ON e.student_id = s.student_id
 ORDER BY s.student_id NULLS FIRST, e.course
 LIMIT 5;   -- 화면 캡처용 (전체 1,002건 · 고아행 2건이 최상단)


-- ###################################################################
-- #  Q04
-- ###################################################################
-- Q04. FULL OUTER JOIN — 학생과 수강을 모두 포함
--   목적 : 어느 한쪽에만 있는 행까지 전부 남긴다.
--          '수강없음'(학생만 존재) 과 '학생없음'(고아 수강행) 이 동시에 보인다.
--   정렬 : 라벨 문자열이 아니라 숫자 정렬키로 정렬해야 순서가 안정적이다.
--   캡처 : 그냥 정렬 후 LIMIT 을 걸면 안 된다. 세 구분이 뭉쳐 있고
--          학생없음 2건 → 수강없음 333건 → 양쪽매칭 1,000건 순이라
--          앞 몇 건만 잘라오면 '양쪽매칭' 이 한 행도 안 나온다.
--          구분마다 ROW_NUMBER 를 매겨 2건씩 뽑으면 세 경우가 다 보인다.
SELECT 구분,
       student_id,
       name,
       enroll_student_id,
       course,
       grade
  FROM (SELECT CASE WHEN e.student_id IS NULL THEN '수강없음'
                    WHEN s.student_id IS NULL THEN '학생없음'
                    ELSE '양쪽매칭'
               END AS 구분,
               CASE WHEN s.student_id IS NULL THEN 1
                    WHEN e.student_id IS NULL THEN 2
                    ELSE 3
               END AS 정렬키,
               s.student_id,
               s.name,
               e.student_id AS enroll_student_id,
               e.course,
               e.grade,
               ROW_NUMBER() OVER (
                   PARTITION BY CASE WHEN s.student_id IS NULL THEN 1
                                     WHEN e.student_id IS NULL THEN 2
                                     ELSE 3 END
                   ORDER BY COALESCE(s.student_id, e.student_id), e.course) AS rn
          FROM lab.student s
          FULL JOIN lab.enroll e ON e.student_id = s.student_id) t
 WHERE rn <= 2   -- 구분별 2건씩 = 총 6행
 ORDER BY 정렬키, rn;


-- ###################################################################
-- #  Q05
-- ###################################################################
-- Q05. 한 번도 수강하지 않은 학생 목록
--   목적 : LEFT JOIN 후 오른쪽이 NULL 인 행만 남기는 anti-join 패턴.
--          짝을 찾지 못한 행은 오른쪽 컬럼이 전부 NULL 이 되므로
--          "짝이 없다" 는 조건을 IS NULL 로 표현할 수 있다.
--   주의 : NULL 판별이므로 e.student_id = NULL 이 아니라 IS NULL 을 쓴다.
SELECT s.student_id,
       s.name,
       s.major,
       s.gpa
  FROM lab.student s
  LEFT JOIN lab.enroll e ON e.student_id = s.student_id
 WHERE e.student_id IS NULL
 ORDER BY s.student_id
 LIMIT 5;   -- 화면 캡처용


-- ###################################################################
-- #  Q06
-- ###################################################################
-- Q06. 한 과목 이상 수강한 학생 목록 (중복 제거)
--   목적 : 조인 결과는 학생당 수강 건수만큼 행이 늘어난다.
--          학생 목록만 필요하므로 DISTINCT 로 중복을 제거한다.
SELECT DISTINCT s.student_id,
       s.name,
       s.major
  FROM lab.student s
  JOIN lab.enroll  e ON e.student_id = s.student_id
 ORDER BY s.student_id
 LIMIT 5;   -- 화면 캡처용


-- ###################################################################
-- #  Q07
-- ###################################################################
-- Q07. 고객별 주문 건수와 총 주문금액
--   목적 : LEFT JOIN + GROUP BY 집계. 주문이 없는 고객도 0 으로 표시한다.
--   주의 : COUNT(*) 는 조인 후 행 수라 주문 없는 고객도 1 이 된다.
--          COUNT(o.order_id) 는 NULL 을 세지 않으므로 정확히 0 이 나온다.
--          SUM 은 대상이 없으면 NULL 이므로 COALESCE 로 0 을 채운다.
SELECT c.customer_id,
       c.customer_name,
       COUNT(o.order_id)          AS 주문건수,
       COALESCE(SUM(o.amount), 0) AS 총주문금액
  FROM lab.customers c
  LEFT JOIN lab.orders o ON o.customer_id = c.customer_id
 GROUP BY c.customer_id, c.customer_name
 ORDER BY 총주문금액 DESC, c.customer_id
 LIMIT 20;   -- 화면 캡처용 (전체 500명)


-- ###################################################################
-- #  Q08
-- ###################################################################
-- Q08. 총 주문금액 상위 10명과 그 금액
--   목적 : 집계 결과를 정렬해 상위 N 건만 추출한다.
--   참고 : 주문이 없는 고객은 상위권에 올 수 없으므로 INNER JOIN 으로 충분하다.
SELECT c.customer_id,
       c.customer_name,
       COUNT(o.order_id) AS 주문건수,
       SUM(o.amount)     AS 총주문금액,
       ROUND(AVG(o.amount), 2) AS 평균주문금액
  FROM lab.customers c
  JOIN lab.orders    o ON o.customer_id = c.customer_id
 GROUP BY c.customer_id, c.customer_name
 ORDER BY 총주문금액 DESC
 LIMIT 10;


-- ###################################################################
-- #  Q09
-- ###################################################################
-- Q09. 모든 직원과 그 매니저 이름 (셀프 조인)
--   목적 : 같은 테이블을 두 번 참조해 계층 관계를 펼친다. 별칭이 반드시 필요하다.
--   주의 : CEO 는 manager_id 가 NULL 이라 INNER JOIN 이면 사라진다.
--          "모든 직원" 이므로 LEFT JOIN 을 쓰고 COALESCE 로 표시를 채운다.
SELECT e.emp_id,
       e.name                            AS 직원명,
       e.manager_id,
       COALESCE(m.name, '(없음 · 최상위)') AS 매니저명
  FROM lab.emp e
  LEFT JOIN lab.emp m ON m.emp_id = e.manager_id
 ORDER BY e.emp_id
 LIMIT 5;   -- 화면 캡처용 (전체 311명)


-- ###################################################################
-- #  Q10
-- ###################################################################
-- Q10. 모든 학생 기준 수강 과목 분포 (LEFT JOIN + 집계)
--   목적 : 학생 전원을 모집단으로 두고 수강 과목 수를 센다.
--          INNER JOIN 으로 집계하면 미수강 학생이 모집단에서 빠져
--          "0과목" 이라는 정보 자체가 사라진다.
--   주의 : COUNT(*) 가 아니라 COUNT(e.course) 를 써야 한다.
--          LEFT JOIN 으로 붙은 빈 행도 COUNT(*) 는 1로 세기 때문이다.

-- (1) 수강 과목 수별 학생 수 분포 — 0과목 구간이 나오는지 확인
SELECT 수강과목수,
       COUNT(*) AS 학생수
  FROM (SELECT s.student_id,
               COUNT(e.course) AS 수강과목수
          FROM lab.student s
          LEFT JOIN lab.enroll e ON e.student_id = s.student_id
         GROUP BY s.student_id) t
 GROUP BY 수강과목수
 ORDER BY 수강과목수;

-- (2) 학생별 수강 과목 수 + 과목 목록 (STRING_AGG)
--   STRING_AGG(값, 구분자) 로 그룹 안의 여러 행을 문자열 하나로 합친다.
--   "몇 과목인지" 뿐 아니라 "어떤 과목인지" 까지 한 행에 담긴다.
--   ORDER BY 를 집계 함수 안에 넣어야 이어붙는 순서가 고정된다.
--   COUNT 와 마찬가지로 STRING_AGG 도 NULL 은 건너뛰므로,
--   미수강 학생은 빈 문자열이 아니라 NULL 이 되어 COALESCE 로 표시를 채운다.
SELECT s.student_id,
       s.name,
       s.major,
       COUNT(e.course) AS 수강과목수,
       COALESCE(STRING_AGG(e.course, ', ' ORDER BY e.course), '(수강 없음)') AS 수강과목목록
  FROM lab.student s
  LEFT JOIN lab.enroll e ON e.student_id = s.student_id
 GROUP BY s.student_id, s.name, s.major
 ORDER BY 수강과목수 DESC, s.student_id
 LIMIT 5;   -- 화면 캡처용 (전체 1,000명)


-- ###################################################################
-- #  Q11
-- ###################################################################
-- Q11. DB 과목을 듣지 않은 모든 학생 나열
--   목적 : NOT EXISTS 를 이용한 anti-join.
--   주의 : NOT IN (SELECT student_id FROM lab.enroll WHERE course='DB') 로도
--          쓸 수 있지만, 서브쿼리 결과에 NULL 이 하나라도 섞이면
--          NOT IN 은 전체가 unknown 이 되어 결과가 0건이 된다.
--          enroll.student_id 는 NULL 허용 컬럼이므로 NOT EXISTS 가 안전하다.
SELECT s.student_id,
       s.name,
       s.major,
       s.gpa
  FROM lab.student s
 WHERE NOT EXISTS (SELECT 1
                     FROM lab.enroll e
                    WHERE e.student_id = s.student_id
                      AND e.course     = 'DB')
 ORDER BY s.student_id
 LIMIT 5;   -- 화면 캡처용

-- 검증 : 전체 학생 수 − DB 수강 학생 수 = 위 결과 건수
SELECT (SELECT COUNT(*) FROM lab.student)                              AS 전체학생,
       (SELECT COUNT(DISTINCT student_id) FROM lab.enroll
         WHERE course = 'DB')                                          AS DB수강자,
       (SELECT COUNT(*) FROM lab.student s
         WHERE NOT EXISTS (SELECT 1 FROM lab.enroll e
                            WHERE e.student_id = s.student_id
                              AND e.course = 'DB'))                    AS DB미수강자;


-- ###################################################################
-- #  Q12
-- ###################################################################
-- Q12. (가정) 과목별 운영 책임 매니저 매핑 테이블 생성 후 리포트
--   가정 : 각 과목은 매니저('Mgr_' 로 시작하는 직원) 한 명이 운영을 책임진다.
--   방법 : 과목과 매니저에 각각 순번을 매기고 나머지연산(%) 으로 균등 배분한다.
--          RANDOM() 을 쓰면 실행할 때마다 결과가 달라져 재현이 안 되므로 쓰지 않는다.
--   주의 : LIKE 에서 '_' 는 한 글자 와일드카드다. 문자 그대로의 밑줄을 찾으려면
--          'Mgr\_%' 처럼 이스케이프해야 한다.
--   주의 : SELECT DISTINCT course, ROW_NUMBER() OVER (...) 로 쓰면 안 된다.
--          윈도우 함수는 DISTINCT 보다 먼저 평가되므로 수강행 1,002건마다
--          서로 다른 순번이 붙고, 그 결과 DISTINCT 가 한 행도 제거하지 못한다.
--          중복 제거를 끝낸 뒤에 순번을 매기도록 서브쿼리로 한 단계 분리한다.

-- ---------------------------------------------------------------------
-- (1) 매핑 테이블 생성
--   DROP TABLE 대신 CREATE TABLE IF NOT EXISTS 를 쓴다.
--   DROP 은 기존 데이터를 통째로 버리는 파괴적 연산이라, 실습 도중 잘못
--   실행하면 되돌릴 수 없다. 아래 UPSERT 와 짝을 이루면 DROP 없이도
--   몇 번을 다시 실행하든 같은 상태로 수렴한다(멱등).
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS lab.course_owner (
    course     VARCHAR(50) PRIMARY KEY,
    manager_id INTEGER     NOT NULL REFERENCES lab.emp(emp_id)
);

-- FK 컬럼에는 반드시 인덱스를 만든다.
--   PostgreSQL 은 FK 를 걸어도 참조하는 쪽 컬럼에 인덱스를 자동 생성하지 않는다.
--   인덱스가 없으면 부모 행(emp) 삭제·갱신 시 자식 테이블 전체를 스캔하고,
--   매니저 기준 조인에서도 Seq Scan 이 된다.
CREATE INDEX IF NOT EXISTS ix_course_owner_manager
    ON lab.course_owner (manager_id);

-- ---------------------------------------------------------------------
-- (2) UPSERT — INSERT ... ON CONFLICT
--   같은 course 가 이미 있으면 INSERT 대신 UPDATE 로 넘어간다.
--   EXCLUDED 는 "삽입하려다 충돌한 그 행" 을 가리키는 가상 테이블이다.
--   충돌 판정 기준(course) 은 PK 나 UNIQUE 제약이 있어야 지정할 수 있다.
--   DO NOTHING 을 쓰면 기존 값을 그대로 두고 조용히 건너뛴다.
-- ---------------------------------------------------------------------
INSERT INTO lab.course_owner (course, manager_id)
SELECT c.course,
       m.emp_id
  FROM (SELECT course,
               ROW_NUMBER() OVER (ORDER BY course) AS rn
          FROM (SELECT DISTINCT course
                  FROM lab.enroll
                 WHERE course IS NOT NULL) d) c
  JOIN (SELECT emp_id,
               ROW_NUMBER() OVER (ORDER BY emp_id) AS rn
          FROM lab.emp
         WHERE name LIKE 'Mgr\_%') m
    ON m.rn = ((c.rn - 1) % (SELECT COUNT(*) FROM lab.emp WHERE name LIKE 'Mgr\_%')) + 1
    ON CONFLICT (course) DO UPDATE
       SET manager_id = EXCLUDED.manager_id;

-- ---------------------------------------------------------------------
-- (3) 리포트 : 과목별 수강 인원 + 책임 매니저 이름
-- ---------------------------------------------------------------------
SELECT co.course        AS 과목,
       e.name           AS 책임매니저,
       COUNT(en.student_id) AS 수강인원
  FROM lab.course_owner co
  JOIN lab.emp          e  ON e.emp_id  = co.manager_id
  LEFT JOIN lab.enroll  en ON en.course = co.course
 GROUP BY co.course, e.name
 ORDER BY 수강인원 DESC, co.course;

-- ---------------------------------------------------------------------
-- (4) 리포트 : 매니저별 담당 과목 목록 (STRING_AGG)
--   STRING_AGG(값, 구분자) 는 그룹 안의 여러 행을 문자열 하나로 이어붙인다.
--   집계 함수이므로 GROUP BY 로 묶인 그룹마다 한 값이 나온다.
--   ORDER BY 를 집계 함수 안에 넣어야 이어붙는 순서가 고정된다.
--   넣지 않으면 실행할 때마다 순서가 달라질 수 있다.
--   효과 : (3) 은 과목 기준 23행, (4) 는 매니저 기준 10행으로 압축된다.
-- ---------------------------------------------------------------------
SELECT e.name                                          AS 책임매니저,
       COUNT(*)                                        AS 담당과목수,
       STRING_AGG(co.course, ', ' ORDER BY co.course)  AS 담당과목목록
  FROM lab.course_owner co
  JOIN lab.emp e ON e.emp_id = co.manager_id
 GROUP BY e.emp_id, e.name
 ORDER BY 담당과목수 DESC, e.emp_id;


-- ###################################################################
-- #  Q13
-- ###################################################################
-- Q13. 학생 × 과목 전체 조합으로 과목 추천 후보 생성 (CROSS JOIN)
--   목적 : CROSS JOIN 은 조인 조건이 없어 두 집합의 데카르트 곱을 만든다.
--          학생 1,000명 × 과목 23개 = 23,000 조합이 생성된다.
--   주의 : 조인 조건을 빠뜨린 실수도 같은 결과를 내므로, 의도한 경우에만
--          CROSS JOIN 을 명시적으로 써서 실수와 구분되게 한다.
--   출력 : 이미 수강한 조합인지 표시하고 샘플 100건만 조회한다.
SELECT s.student_id,
       s.name,
       s.major,
       c.course,
       CASE WHEN EXISTS (SELECT 1
                           FROM lab.enroll e
                          WHERE e.student_id = s.student_id
                            AND e.course     = c.course)
            THEN '수강완료' ELSE '추천후보'
       END AS 상태
  FROM lab.student s
 CROSS JOIN (SELECT DISTINCT course FROM lab.enroll WHERE course IS NOT NULL) c
 ORDER BY s.student_id, c.course
 LIMIT 100;   -- 문항 요구: 샘플 100건

-- 참고 : 전체 조합 수 확인
SELECT (SELECT COUNT(*) FROM lab.student)                        AS 학생수,
       (SELECT COUNT(DISTINCT course) FROM lab.enroll)           AS 과목수,
       (SELECT COUNT(*) FROM lab.student)
     * (SELECT COUNT(DISTINCT course) FROM lab.enroll)           AS 전체조합수;


-- ###################################################################
-- #  Q14
-- ###################################################################
-- Q14. 스칼라 서브쿼리(SELECT 절) — 학생에 소속 학과명 붙이기
--   목적 : SELECT 절의 서브쿼리는 행마다 실행되어 값 하나(1행 1열)를 반환한다.
--          2행 이상을 반환하면 실행 시점에 에러가 난다.
--   참고 : student.major 는 코드값(CS, EE …)만 갖고 학과 테이블이 없으므로
--          VALUES 목록을 인라인 매핑표로 사용한다.
--   비교 : 학과명은 비상관 매핑, 학과평균GPA 는 바깥 행의 major 를 참조하는
--          상관(correlated) 스칼라 서브쿼리다.
SELECT s.student_id,
       s.name,
       s.major,
       (SELECT m.major_name
          FROM (VALUES ('CS',  '컴퓨터공학과'),
                       ('EE',  '전자공학과'),
                       ('ME',  '기계공학과'),
                       ('CE',  '건설환경공학과'),
                       ('BIO', '생명과학과'),
                       ('HR',  '인적자원학과')
               ) AS m(code, major_name)
         WHERE m.code = s.major)                    AS 학과명,
       s.gpa,
       (SELECT ROUND(AVG(x.gpa), 2)
          FROM lab.student x
         WHERE x.major = s.major)                   AS 학과평균GPA
  FROM lab.student s
 ORDER BY s.student_id
 LIMIT 5;   -- 화면 캡처용


-- ###################################################################
-- #  Q15
-- ###################################################################
-- Q15. 전체 평균 GPA 보다 높은 학생 (WHERE 절 서브쿼리)
--   목적 : 비상관(uncorrelated) 서브쿼리. 바깥 행을 참조하지 않으므로
--          한 번만 실행되고 그 결과값이 모든 행 비교에 재사용된다.
--   주의 : WHERE 절에서는 SELECT 의 별칭을 쓸 수 없다.
--          별칭은 SELECT 목록이 계산된 뒤 확정되고 WHERE 는 그 전에 평가된다.
SELECT s.student_id,
       s.name,
       s.major,
       s.gpa
  FROM lab.student s
 WHERE s.gpa > (SELECT AVG(gpa) FROM lab.student)
 ORDER BY s.gpa DESC, s.student_id
 LIMIT 5;   -- 화면 캡처용

-- 참고 : 기준값과 대상 인원 확인
SELECT ROUND((SELECT AVG(gpa) FROM lab.student), 3) AS 전체평균GPA,
       (SELECT COUNT(*) FROM lab.student
         WHERE gpa > (SELECT AVG(gpa) FROM lab.student)) AS 평균초과인원;


-- ###################################################################
-- #  Q16
-- ###################################################################
-- Q16. 자신의 학과 평균 GPA 보다 높은 학생 (상관 서브쿼리)
--   목적 : 서브쿼리가 바깥 행의 s.major 를 참조한다(correlated).
--          비교 기준이 행마다 달라지므로 Q15 처럼 한 번만 계산할 수 없다.
--   비교 : Q15 는 기준이 하나(전체 평균), Q16 은 기준이 학과마다 다르다.
SELECT s.student_id,
       s.name,
       s.major,
       s.gpa,
       (SELECT ROUND(AVG(x.gpa), 2)
          FROM lab.student x
         WHERE x.major = s.major) AS 학과평균GPA
  FROM lab.student s
 WHERE s.gpa > (SELECT AVG(x.gpa)
                  FROM lab.student x
                 WHERE x.major = s.major)
 ORDER BY s.major, s.gpa DESC
 LIMIT 5;   -- 화면 캡처용

-- 참고 : 학과별 평균과 초과 인원
SELECT s.major,
       COUNT(*)                                AS 학과인원,
       ROUND(AVG(s.gpa), 3)                    AS 학과평균GPA,
       COUNT(*) FILTER (WHERE s.gpa > a.avg_gpa) AS 평균초과인원
  FROM lab.student s
  JOIN (SELECT major, AVG(gpa) AS avg_gpa
          FROM lab.student GROUP BY major) a ON a.major = s.major
 GROUP BY s.major
 ORDER BY s.major;


-- ###################################################################
-- #  Q17
-- ###################################################################
-- Q17. 수강(enroll) 기록이 있는 학생만 조회 (EXISTS)
--   목적 : EXISTS 는 짝이 하나라도 있으면 참이고 즉시 탐색을 멈춘다.
--          JOIN 과 달리 행이 늘어나지 않으므로 DISTINCT 가 필요 없다.
--   참고 : SELECT 1 을 쓰는 이유 — EXISTS 는 서브쿼리가 행을 반환하는지만
--          보고 그 값은 쓰지 않는다. 컬럼을 나열해도 의미가 없다.
SELECT s.student_id,
       s.name,
       s.major,
       s.gpa
  FROM lab.student s
 WHERE EXISTS (SELECT 1
                 FROM lab.enroll e
                WHERE e.student_id = s.student_id)
 ORDER BY s.student_id
 LIMIT 5;   -- 화면 캡처용

-- 참고 : EXISTS 결과 건수 = Q06 의 DISTINCT JOIN 결과 건수
SELECT COUNT(*) AS 수강기록보유학생
  FROM lab.student s
 WHERE EXISTS (SELECT 1 FROM lab.enroll e WHERE e.student_id = s.student_id);


-- ###################################################################
-- #  Q18
-- ###################################################################
-- Q18. 한 번도 수강하지 않은 학생 (NOT EXISTS)
--   목적 : Q05 의 LEFT JOIN + IS NULL 과 같은 결과를 NOT EXISTS 로 표현한다.
--          두 방식은 결과가 같고 PostgreSQL 은 대개 같은 anti-join 계획을 만든다.
--   주의 : NOT IN 은 서브쿼리 결과에 NULL 이 섞이면 항상 0건이 된다.
--          NOT EXISTS 는 NULL 의 영향을 받지 않으므로 기본 선택지로 삼는다.
SELECT s.student_id,
       s.name,
       s.major,
       s.gpa
  FROM lab.student s
 WHERE NOT EXISTS (SELECT 1
                     FROM lab.enroll e
                    WHERE e.student_id = s.student_id)
 ORDER BY s.student_id
 LIMIT 5;   -- 화면 캡처용

-- 참고 : Q05(LEFT JOIN + IS NULL) 과 건수가 일치하는지 확인
SELECT (SELECT COUNT(*) FROM lab.student s
         WHERE NOT EXISTS (SELECT 1 FROM lab.enroll e
                            WHERE e.student_id = s.student_id))  AS NOT_EXISTS_건수,
       (SELECT COUNT(*) FROM lab.student s
          LEFT JOIN lab.enroll e ON e.student_id = s.student_id
         WHERE e.student_id IS NULL)                             AS LEFT_JOIN_건수;


-- ###################################################################
-- #  Q19
-- ###################################################################
-- Q19. HR 학과 학생들과의 비교 데모 (ANY / ALL)
--   목적 : 다중행 서브쿼리를 비교연산자와 함께 쓰는 두 방식을 대조한다.
--          > ANY (집합)  →  집합의 최솟값보다 크면 참 ("일부보다 높다")
--          > ALL (집합)  →  집합의 최댓값보다 크면 참 ("전원보다 높다")
--   주의 : 서브쿼리가 2행 이상을 반환하는데 ANY/ALL 없이 > 만 쓰면 에러가 난다.

-- (1) HR 학과 학생 중 "일부보다" GPA 가 높은 타 학과 학생
SELECT s.student_id,
       s.name,
       s.major,
       s.gpa,
       s.gpa > ALL (SELECT h.gpa FROM lab.student h WHERE h.major = 'HR') AS HR전원보다높음
  FROM lab.student s
 WHERE s.major <> 'HR'
   AND s.gpa > ANY (SELECT h.gpa FROM lab.student h WHERE h.major = 'HR')
 ORDER BY s.gpa DESC, s.student_id
 LIMIT 5;   -- 화면 캡처용

-- (2) 기준값 확인 — ANY 는 MIN, ALL 은 MAX 와 같은 뜻이다
--     HR 최고 GPA 가 전체 최고 GPA 와 같으면 > ALL 조건은 0건이 된다.
SELECT MIN(gpa) AS HR최저GPA_ANY기준,
       MAX(gpa) AS HR최고GPA_ALL기준,
       (SELECT MAX(gpa) FROM lab.student)                       AS 전체최고GPA,
       (SELECT COUNT(*) FROM lab.student s
         WHERE s.major <> 'HR'
           AND s.gpa > ANY (SELECT gpa FROM lab.student WHERE major='HR')) AS ANY_충족인원,
       (SELECT COUNT(*) FROM lab.student s
         WHERE s.major <> 'HR'
           AND s.gpa > ALL (SELECT gpa FROM lab.student WHERE major='HR')) AS ALL_충족인원
  FROM lab.student
 WHERE major = 'HR';


-- ###################################################################
-- #  Q20
-- ###################################################################
-- Q20. CS 학과 학생 또는 DB 과목 수강 학생 목록 (UNION)
--   목적 : 두 결과집합을 세로로 합친다.
--          UNION 은 중복 행을 제거하고, UNION ALL 은 그대로 둔다.
--   조건 : 양쪽 SELECT 의 컬럼 개수와 타입이 서로 맞아야 한다.
--   참고 : ORDER BY 는 UNION 전체에 한 번만, 맨 끝에 붙인다.
SELECT s.student_id, s.name, s.major
  FROM lab.student s
 WHERE s.major = 'CS'
UNION
SELECT s.student_id, s.name, s.major
  FROM lab.student s
  JOIN lab.enroll e ON e.student_id = s.student_id
 WHERE e.course = 'DB'
 ORDER BY student_id
 LIMIT 5;   -- 화면 캡처용

-- 참고 : UNION 과 UNION ALL 의 건수 차이 = 중복 제거된 행 수
--        (CS 학과이면서 DB 를 수강한 학생, 그리고 DB 를 여러 번 수강한 행)
SELECT (SELECT COUNT(*) FROM (
          SELECT student_id FROM lab.student WHERE major='CS'
          UNION
          SELECT s.student_id FROM lab.student s
            JOIN lab.enroll e ON e.student_id=s.student_id WHERE e.course='DB') u)  AS UNION_건수,
       (SELECT COUNT(*) FROM (
          SELECT student_id FROM lab.student WHERE major='CS'
          UNION ALL
          SELECT s.student_id FROM lab.student s
            JOIN lab.enroll e ON e.student_id=s.student_id WHERE e.course='DB') a)  AS UNION_ALL_건수;


-- ###################################################################
-- #  Q21
-- ###################################################################
-- Q21. 학과별·GPA 구간별 인원을 소계·총계까지 한 쿼리로 (GROUP BY ROLLUP)
--   목적 : ROLLUP(major, gpa_tier) 는 아래 세 단계를 한 번에 집계한다.
--            ① (major, gpa_tier) 상세  ② (major) 학과 소계  ③ () 전체 총계
--   라벨 : 소계 행의 major/gpa_tier 는 NULL 이 된다. 원래 데이터의 NULL 과
--          구분해야 하므로 GROUPING() 함수로 판별한다(소계면 1).
--   정렬 : GPA 구간을 한글 라벨로 정렬하면 순서가 뒤섞이므로
--          숫자 tier_no 로 그룹핑·정렬하고 라벨은 표시할 때만 붙인다.
--          소계·총계 행은 GROUPING() 을 정렬 1순위로 두어 하단에 모은다.
--   비율 : 분모로 SUM(COUNT(*)) OVER () 를 쓰면 안 된다. 소계·총계 행까지
--          같이 더해져 분모가 실제 인원의 3배(3,000)가 된다.
--          모집단 전체를 세는 스칼라 서브쿼리를 분모로 쓴다.
WITH tiered AS (
    SELECT major,
           gpa,
           CASE WHEN gpa <  3.0 THEN 1
                WHEN gpa <= 3.5 THEN 2
                ELSE                 3
           END AS tier_no
      FROM lab.student
)
SELECT CASE WHEN GROUPING(major) = 1 THEN '전체' ELSE major END        AS 학과,
       CASE WHEN GROUPING(major)    = 1 THEN '총계'
            WHEN GROUPING(tier_no)  = 1 THEN '학과 소계'
            WHEN tier_no = 1 THEN '3.0 미만'
            WHEN tier_no = 2 THEN '3.0~3.5'
            ELSE                 '3.5 초과'
       END                                                             AS GPA구간,
       COUNT(*)                                                        AS 인원,
       ROUND(AVG(gpa), 2)                                              AS 평균GPA,
       ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM tiered), 1)      AS 전체대비비율
  FROM tiered
 GROUP BY ROLLUP (major, tier_no)
 ORDER BY GROUPING(major),      -- 총계 행을 맨 아래로
          major,
          GROUPING(tier_no),    -- 학과 소계를 각 학과 아래로
          tier_no;


-- ###################################################################
-- #  Q22
-- ###################################################################
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


-- ###################################################################
-- #  Q23
-- ###################################################################
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


-- ###################################################################
-- #  Q24
-- ###################################################################
-- Q24. 학생별 이전 과목 대비 성적 변화 (LAG)
--   변환 : grade(A~D) 는 문자라 뺄셈이 안 되므로 CASE 로 점수화한다 (A=4 … D=1).
--   LAG  : PARTITION BY student_id 로 학생마다 창을 나누고 ORDER BY course 순서에서
--          바로 앞 행의 값을 가져온다. 첫 행은 앞이 없으므로 NULL 이다.
--   주의 : LAG 는 이미 계산된 창 안에서만 동작하므로 같은 SELECT 단계에서
--          그 결과를 다시 참조할 수 없다. 한 단계 감싸서 diff 를 계산한다.
--   범위 : score_range 는 학생 전체 창의 MAX-MIN 이라 ORDER BY 없이 PARTITION 만 준다.
WITH scored AS (
    SELECT e.student_id,
           e.course,
           CASE e.grade WHEN 'A' THEN 4
                        WHEN 'B' THEN 3
                        WHEN 'C' THEN 2
                        WHEN 'D' THEN 1
           END AS score
      FROM lab.enroll e
     WHERE e.student_id IS NOT NULL
),
windowed AS (
    SELECT student_id,
           course,
           score,
           LAG(score) OVER (PARTITION BY student_id ORDER BY course) AS prev_score,
           MAX(score) OVER (PARTITION BY student_id)
         - MIN(score) OVER (PARTITION BY student_id)                 AS score_range
      FROM scored
)
SELECT w.student_id,
       s.name,
       w.course,
       w.score,
       w.prev_score,
       w.score - w.prev_score AS diff,
       CASE WHEN w.prev_score IS NULL      THEN '첫 과목'
            WHEN w.score > w.prev_score    THEN '상승'
            WHEN w.score = w.prev_score    THEN '유지'
            ELSE                                '하락'
       END AS 변화,
       w.score_range
  FROM windowed w
  LEFT JOIN lab.student s ON s.student_id = w.student_id
 ORDER BY w.student_id, w.course
 LIMIT 5;   -- 화면 캡처용 (전체 1,002건)

-- 참고 : 변화 유형별 건수
WITH scored AS (
    SELECT student_id, course,
           CASE grade WHEN 'A' THEN 4 WHEN 'B' THEN 3
                      WHEN 'C' THEN 2 WHEN 'D' THEN 1 END AS score
      FROM lab.enroll WHERE student_id IS NOT NULL
),
windowed AS (
    SELECT student_id, score,
           LAG(score) OVER (PARTITION BY student_id ORDER BY course) AS prev_score
      FROM scored
)
SELECT CASE WHEN prev_score IS NULL   THEN '첫 과목'
            WHEN score > prev_score   THEN '상승'
            WHEN score = prev_score   THEN '유지'
            ELSE                           '하락' END AS 변화,
       COUNT(*) AS 건수
  FROM windowed
 GROUP BY 1
 ORDER BY 2 DESC;


-- ###################################################################
-- #  Q25
-- ###################################################################
-- Q25. 주문 누적금액과 이동평균 (Window Frame · ROWS BETWEEN)

-- =====================================================================
SELECT o.order_id,
       o.customer_id,
       o.amount,
       SUM(o.amount) OVER (ORDER BY o.order_id
                           ROWS BETWEEN UNBOUNDED PRECEDING
                                    AND CURRENT ROW)          AS 누적금액,
       ROUND(AVG(o.amount) OVER (ORDER BY o.order_id
                                 ROWS BETWEEN 2 PRECEDING
                                          AND CURRENT ROW), 2) AS 이동평균_3건,
       COUNT(*) OVER (ORDER BY o.order_id
                      ROWS BETWEEN 2 PRECEDING
                               AND CURRENT ROW)               AS 프레임건수
  FROM lab.orders o
 ORDER BY o.order_id
 LIMIT 5;  

-- =====================================================================
SELECT o.customer_id,
       o.order_id,
       o.amount,
       SUM(o.amount) OVER (PARTITION BY o.customer_id
                           ORDER BY o.order_id
                           ROWS BETWEEN UNBOUNDED PRECEDING
                                    AND CURRENT ROW)          AS 고객별_누적금액,
       ROW_NUMBER() OVER (PARTITION BY o.customer_id
                          ORDER BY o.order_id)                AS 고객내_주문순번,
       SUM(o.amount) OVER (ORDER BY o.order_id
                           ROWS BETWEEN UNBOUNDED PRECEDING
                                    AND CURRENT ROW)          AS 전체_누적금액
  FROM lab.orders o
 WHERE o.customer_id IN (1, 2)
 ORDER BY o.customer_id, o.order_id;


-- =====================================================================
WITH cum AS (
    SELECT o.order_id,
           o.customer_id,
           o.amount,
           SUM(o.amount) OVER (ORDER BY o.order_id
                               ROWS BETWEEN UNBOUNDED PRECEDING
                                        AND CURRENT ROW) AS 누적금액,
           SUM(o.amount) OVER ()                         AS 전체합
      FROM lab.orders o
)
SELECT order_id,
       customer_id,
       amount,
       누적금액,
       전체합,
       ROUND(100.0 * 누적금액 / 전체합, 2) AS 누적비율_퍼센트
  FROM cum
 WHERE 누적금액 > 전체합 * 0.5
 ORDER BY order_id
 LIMIT 5;

-- 검증 : 바로 앞 주문은 아직 50% 를 넘지 않았는지 확인 (경계 앞뒤 2건)
WITH cum AS (
    SELECT o.order_id,
           o.amount,
           SUM(o.amount) OVER (ORDER BY o.order_id
                               ROWS BETWEEN UNBOUNDED PRECEDING
                                        AND CURRENT ROW) AS 누적금액,
           SUM(o.amount) OVER ()                         AS 전체합
      FROM lab.orders o
),
경계 AS (
    SELECT MIN(order_id) AS 첫초과 FROM cum WHERE 누적금액 > 전체합 * 0.5
)
SELECT c.order_id,
       c.amount,
       c.누적금액,
       ROUND(100.0 * c.누적금액 / c.전체합, 2) AS 누적비율_퍼센트,
       CASE WHEN c.누적금액 > c.전체합 * 0.5 THEN '초과' ELSE '미달' END AS 판정
  FROM cum c, 경계 b
 WHERE c.order_id BETWEEN b.첫초과 - 2 AND b.첫초과 + 1
 ORDER BY c.order_id;

-- =====================================================================
SELECT o.customer_id,
       o.order_id,
       o.amount,
       SUM(o.amount) OVER (ORDER BY o.customer_id
                           ROWS BETWEEN UNBOUNDED PRECEDING
                                    AND CURRENT ROW)  AS ROWS_동점미해소,
       SUM(o.amount) OVER (ORDER BY o.customer_id, o.order_id
                           ROWS BETWEEN UNBOUNDED PRECEDING
                                    AND CURRENT ROW)  AS ROWS_동점해소,
       SUM(o.amount) OVER (ORDER BY o.customer_id
                           RANGE BETWEEN UNBOUNDED PRECEDING
                                     AND CURRENT ROW) AS RANGE_누적
  FROM lab.orders o
 WHERE o.customer_id IN (1, 2)
 ORDER BY o.customer_id, o.order_id;


-- ###################################################################
-- #  Q26
-- ###################################################################
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


-- ###################################################################
-- #  Q27
-- ###################################################################
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
