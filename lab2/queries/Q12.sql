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
