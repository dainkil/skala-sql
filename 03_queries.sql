-- =====================================================================
--  03_queries.sql — 학사관리시스템 조회
--  SKALA SQL 종합실습 1
--
--  대상 : PostgreSQL 17 / skala_db / 스키마 app
--  실행 : psql skala_db -f 03_queries.sql
--  선행 : 01_ddl.sql → 02_dml_insert.sql
--
--  [섹션 1] SELECT + WHERE + ORDER BY 기초 조회   ← 현재 파일
--  [섹션 2] COALESCE / CASE WHEN / 날짜 함수      (예정)
--  [섹션 3] 교차 테이블 JOIN 조회                 (예정)
-- =====================================================================
--
--  작성 규칙
--   · SELECT * 를 쓰지 않는다 — 필요한 컬럼만 명시한다
--   · 모든 쿼리에 목적 주석을 단다
--   · NULL 비교는 IS NULL / IS NOT NULL 을 쓴다 (= NULL 은 항상 거짓)
--   · WHERE 절에서는 SELECT 별칭을 쓸 수 없다 (ORDER BY 에서만 가능)
-- =====================================================================

SET search_path TO app, public;

\pset border 2


-- =====================================================================
--  섹션 1. SELECT + WHERE + ORDER BY 기초 조회
-- =====================================================================


-- ---------------------------------------------------------------------
-- Q1-1. 재학생 명단을 학번순으로 조회
--   목적 : 가장 기본적인 등가 조건(=) 필터와 오름차순 정렬
--   기대 : 15건 (전체 20명 − 휴학 2 − 졸업 2 − 자퇴 1)
-- ---------------------------------------------------------------------
SELECT student_no  AS 학번,
       name        AS 성명,
       grade       AS 학년,
       email       AS 이메일
  FROM app.students
 WHERE status = '재학'
 ORDER BY student_no;


-- ---------------------------------------------------------------------
-- Q1-2. 3·4학년 재학생을 학년 내림차순, 성명 가나다순으로 조회
--   목적 : IN 목록 조건 + AND 결합 + 다중 컬럼 정렬(방향 혼합)
--   참고 : ORDER BY 는 왼쪽 컬럼이 1순위. 같은 값일 때만 다음 컬럼을 본다.
--          성명 정렬 결과가 가나다순이면 ICU ko-KR 콜레이션이 적용된 것이다.
--   기대 : 7건 (4학년 재학 3 + 3학년 재학 4)
-- ---------------------------------------------------------------------
SELECT student_no AS 학번,
       name       AS 성명,
       grade      AS 학년,
       status     AS 학적상태
  FROM app.students
 WHERE grade IN (3, 4)
   AND status = '재학'
 ORDER BY grade DESC, name;


-- ---------------------------------------------------------------------
-- Q1-3. 연락처 또는 주소가 미기재된 학생 조회
--   목적 : NULL 판별. IS NULL 을 써야 하는 이유를 보여준다.
--   주의 : WHERE phone = NULL 은 결과가 항상 0건이다.
--          NULL 은 "알 수 없는 값"이라 = 비교의 결과가 참도 거짓도 아닌
--          unknown 이 되고, WHERE 는 참인 행만 통과시키기 때문이다.
--   기대 : 5건
-- ---------------------------------------------------------------------
SELECT student_no AS 학번,
       name       AS 성명,
       phone      AS 연락처,
       address    AS 주소
  FROM app.students
 WHERE phone   IS NULL
    OR address IS NULL
 ORDER BY student_no;


-- ---------------------------------------------------------------------
-- Q1-4. 2023~2024년 입학생 조회
--   목적 : BETWEEN 범위 조건 + 날짜 정렬
--   참고 : BETWEEN 은 양쪽 경계를 포함한다(>= AND <=).
--          날짜 리터럴은 DATE '2023-01-01' 처럼 타입을 명시하는 편이
--          문자열 자동 변환에 의존하는 것보다 안전하다.
--   기대 : 10건
-- ---------------------------------------------------------------------
SELECT student_no  AS 학번,
       name        AS 성명,
       admitted_on AS 입학일,
       grade       AS 학년
  FROM app.students
 WHERE admitted_on BETWEEN DATE '2023-01-01' AND DATE '2024-12-31'
 ORDER BY admitted_on, student_no;


-- ---------------------------------------------------------------------
-- Q1-5. 2022학번 학생 조회
--   목적 : LIKE 패턴 매칭
--   참고 : '2022%' 처럼 와일드카드가 뒤에 있으면 인덱스를 탈 수 있지만,
--          '%2022' 처럼 앞에 있으면 인덱스를 쓰지 못하고 전체 스캔이 된다.
--          대소문자 무시 검색이 필요하면 ILIKE 를 쓴다.
--   기대 : 5건
-- ---------------------------------------------------------------------
SELECT student_no  AS 학번,
       name        AS 성명,
       status      AS 학적상태,
       admitted_on AS 입학일
  FROM app.students
 WHERE student_no LIKE '2022%'
 ORDER BY student_no;


-- ---------------------------------------------------------------------
-- Q1-6. 4학년 재학생 또는 졸업생 조회
--   목적 : AND / OR 혼합 시 괄호로 우선순위를 명시한다
--   주의 : AND 가 OR 보다 우선순위가 높다. 괄호가 없으면
--            status='재학' AND grade=4 OR status='졸업'
--          는 (status='재학' AND grade=4) OR status='졸업' 로 해석된다.
--          의도와 같더라도 괄호를 써서 읽는 사람이 헷갈리지 않게 한다.
--   기대 : 5건 (4학년 재학 3 + 졸업 2)
-- ---------------------------------------------------------------------
SELECT student_no AS 학번,
       name       AS 성명,
       grade      AS 학년,
       status     AS 학적상태
  FROM app.students
 WHERE (status = '재학' AND grade = 4)
    OR (status = '졸업')
 ORDER BY status, grade DESC, student_no;


-- ---------------------------------------------------------------------
-- Q1-7. 환불계좌 등록 현황 조회 (미등록자를 먼저)
--   목적 : ORDER BY 의 NULL 위치 제어
--   참고 : PostgreSQL 기본값은 ASC → NULLS LAST, DESC → NULLS FIRST 다.
--          기본값에 의존하지 말고 필요하면 명시하는 편이 안전하다.
--   기대 : 20건 (미등록 9건이 위로 올라온다)
-- ---------------------------------------------------------------------
SELECT student_no     AS 학번,
       name           AS 성명,
       refund_account AS 환불계좌
  FROM app.students
 ORDER BY refund_account NULLS FIRST, student_no;


-- ---------------------------------------------------------------------
-- Q1-8. 공학 계열 학과 조회 — ORDER BY 에서 별칭 사용
--   목적 : WHERE 와 ORDER BY 의 별칭 사용 가능 여부 차이를 보여준다
--   핵심 : SQL 실행 순서는 FROM → WHERE → SELECT → ORDER BY 다.
--          WHERE 가 실행되는 시점에는 SELECT 의 별칭이 아직 없다.
--            WHERE 계열 = '공학'    → ERROR: column "계열" does not exist
--            ORDER BY 학과명        → 정상 (SELECT 이후에 실행되므로)
--   기대 : 4건
-- ---------------------------------------------------------------------
SELECT code    AS 학과코드,
       name    AS 학과명,
       college AS 계열
  FROM app.departments
 WHERE college = '공학'          -- 별칭 '계열' 이 아니라 원본 컬럼명을 쓴다
 ORDER BY 학과명;                -- 여기서는 별칭 사용 가능


-- ---------------------------------------------------------------------
-- Q1-9. 교양과목을 영역별로 조회
--   목적 : 등가 조건 + 두 컬럼 정렬
--   참고 : liberal_area 는 교양과목에만 값이 있다(조건부 CHECK).
--          전공·일반 과목은 NULL 이므로 이 결과에는 나오지 않는다.
--   기대 : 5건
-- ---------------------------------------------------------------------
SELECT code         AS 과목코드,
       title        AS 과목명,
       credits      AS 학점,
       liberal_area AS 교양영역
  FROM app.courses
 WHERE course_type = '교양'
 ORDER BY liberal_area, code;


-- ---------------------------------------------------------------------
-- Q1-10. 개설학과가 지정되지 않은 과목 조회
--   목적 : IS NULL 로 "관계가 없는" 행을 찾는다
--   참고 : courses.department_id 가 NULL 이라는 것은 교양·일반 과목이라
--          특정 학과에 귀속되지 않는다는 업무적 의미다. 값 누락이 아니다.
--   기대 : 6건 (교양 5 + 일반 1)
-- ---------------------------------------------------------------------
SELECT code        AS 과목코드,
       title       AS 과목명,
       course_type AS 이수구분,
       credits     AS 학점
  FROM app.courses
 WHERE department_id IS NULL
 ORDER BY course_type, code;


-- ---------------------------------------------------------------------
-- Q1-11. 등록금 미납 내역 조회
--   목적 : NULL 조건으로 업무 상태를 식별한다
--   참고 : paid_on IS NULL 이 곧 "미납"이다.
--          미납금액은 저장하지 않으므로 billed_amount − paid_amount 로 계산한다.
--          (파생 속성을 저장하지 않는다는 설계 결정의 결과)
--   기대 : 3건
-- ---------------------------------------------------------------------
SELECT billed_amount                  AS 고지금액,
       paid_amount                    AS 납부금액,
       billed_amount - paid_amount    AS 미납금액,
       is_installment                 AS 분할납부
  FROM app.registrations
 WHERE paid_on IS NULL
 ORDER BY billed_amount DESC;


-- ---------------------------------------------------------------------
-- Q1-12. 채점 완료된 성적 중 85점 이상 조회
--   목적 : IS NOT NULL 과 범위 조건의 결합
--   주의 : score >= 85 만 쓰면 NULL 행은 자동으로 제외된다(비교가 unknown).
--          그래도 IS NOT NULL 을 함께 쓰는 이유는 "미채점을 의도적으로
--          제외했다"는 의도를 코드에 남기기 위해서다.
-- ---------------------------------------------------------------------
SELECT score       AS 성적,
       status      AS 신청상태,
       is_retake   AS 재수강여부,
       enrolled_at AS 신청일시
  FROM app.enrollments
 WHERE score IS NOT NULL
   AND score >= 85
 ORDER BY score DESC, enrolled_at;


-- ---------------------------------------------------------------------
-- Q1-13. 개설된 계열 목록 조회
--   목적 : DISTINCT 로 중복 제거
--   기대 : 4건 (공학 · 상경 · 인문 · 자연)
-- ---------------------------------------------------------------------
SELECT DISTINCT college AS 계열
  FROM app.departments
 ORDER BY college;


-- ---------------------------------------------------------------------
-- Q1-14. 학점이 높은 과목 상위 5건
--   목적 : LIMIT 로 결과 건수 제한
--   주의 : ORDER BY 없이 LIMIT 를 쓰면 어떤 행이 나올지 보장되지 않는다.
--          정렬 기준이 같은 행이 여러 개면 순서가 매번 달라질 수 있으므로,
--          동점을 가르는 보조 정렬 컬럼(title)을 함께 지정한다.
-- ---------------------------------------------------------------------
SELECT code        AS 과목코드,
       title       AS 과목명,
       credits     AS 학점,
       course_type AS 이수구분
  FROM app.courses
 ORDER BY credits DESC, title
 LIMIT 5;


-- ---------------------------------------------------------------------
-- Q1-15. 담당교수가 배정되지 않은 개설강좌 조회
--   목적 : FK 가 NULL 인 행 찾기 — 선택적(optional) 관계의 결과
--   참고 : 개념설계에서 "교수는 강좌를 0개 이상 담당한다"고 참여도를
--          선택으로 정했기 때문에 professor_id 가 NULL 일 수 있다.
--          이 설계 결정이 ON DELETE SET NULL 을 가능하게 만든 근거이기도 하다.
--   기대 : 2건
-- ---------------------------------------------------------------------
SELECT section  AS 분반,
       capacity AS 정원
  FROM app.offerings
 WHERE professor_id IS NULL
 ORDER BY capacity DESC;


-- ---------------------------------------------------------------------
-- Q1-16. (참고) 한글 정렬 검증 — ICU ko-KR vs C 콜레이션
--   목적 : CREATE DATABASE 시 지정한 콜레이션이 실제로 동작하는지 확인
--   참고 : COLLATE "C" 는 UTF-8 바이트값 순서라 사전식 정렬과 다르다.
--          두 열의 순서가 다르게 나오면 ICU 가 적용된 것이다.
-- ---------------------------------------------------------------------
SELECT name AS "ICU ko-KR 정렬",
       ROW_NUMBER() OVER (ORDER BY name COLLATE "C") AS "C 콜레이션 순위"
  FROM app.students
 ORDER BY name;


-- =====================================================================
--  섹션 2. COALESCE / CASE WHEN / 날짜 함수 활용
-- =====================================================================

-- ---------------------------------------------------------------------
-- Q2-1. 재적 학생의 연락처 보완 표시 · 학적 파생구분 · 입학 후 경과기간 조회
--   목적 : NULL 대체(COALESCE), 조건 분기(CASE WHEN), 날짜 연산을 한 번에 수행
--   함수 : COALESCE / CASE WHEN / TO_CHAR / DATE_TRUNC / EXTRACT / AGE / INTERVAL
--   주의 : WHERE 에는 SELECT 별칭(학적구분)을 쓸 수 없어 원본 컬럼 status 를 쓴다
--   기대 : 19건 (전체 20명 − 자퇴 1)
-- ---------------------------------------------------------------------
SELECT student_no                                        AS 학번,
       name                                              AS 성명,
       COALESCE(phone, '미기재')                          AS 연락처,
       TO_CHAR(admitted_on, 'YYYY"년" MM"월"')            AS 입학시기,
       DATE_TRUNC('month', admitted_on)::date            AS 입학월초,
       EXTRACT(YEAR FROM AGE(CURRENT_DATE, admitted_on)) AS 재학연차,
       CASE WHEN status = '재학' AND grade = 4 THEN '졸업예정'
            WHEN status = '재학'               THEN '재학중'
            WHEN status = '휴학'               THEN '휴학중'
            ELSE                                    '졸업'
       END                                               AS 학적구분,
       CASE WHEN admitted_on <= CURRENT_DATE - INTERVAL '4 years'
                 THEN '수료연한 도래'
            ELSE  '재학기간 내'
       END                                               AS 수료연한
  FROM app.students
 WHERE status <> '자퇴'
 ORDER BY admitted_on, student_no;


-- =====================================================================
--  섹션 3. 수강신청 교차 테이블 JOIN 조회
-- =====================================================================

-- ---------------------------------------------------------------------
-- Q3-1. 2025학년도 이후 1학기 수강신청 내역 조회
--   목적 : 학생 N:M 개설강좌 관계를 교차 테이블 enrollments 로 연결하여
--          "누가 · 어느 학기에 · 무슨 과목을 · 누구에게 · 몇 점으로" 수강했는지 조회
--
--   구조 : 학생 ─ enrollments(교차) ─ 개설강좌 ─ 교과목
--                                        └─ 학기
--                                        └─ 교수 (선택 관계)
--
--   JOIN : 5개 테이블 INNER JOIN + 교수 1개 LEFT JOIN
--          교수만 LEFT JOIN 인 이유 — offerings.professor_id 는 NULL 허용이라
--          INNER JOIN 하면 담당교수 미배정 강좌의 수강생이 통째로 사라진다.
--
--   기대 : 21건 (2025-1 확정 11 + 2026-1 확정 10)
--          담당교수 미배정 4건 · 미채점 10건 · 재수강 3건 포함
-- ---------------------------------------------------------------------
SELECT sm.year::text || '-' || sm.term       AS 학기,
       s.student_no                          AS 학번,
       s.name                                AS 성명,
       c.code                                AS 과목코드,
       c.title                               AS 과목명,
       c.credits                             AS 학점,
       o.section                             AS 분반,
       COALESCE(p.name, '미배정')             AS 담당교수,
       e.score                               AS 성적,
       CASE WHEN e.score IS NULL THEN '미채점'
            WHEN e.score >= 90   THEN 'A'
            WHEN e.score >= 80   THEN 'B'
            WHEN e.score >= 70   THEN 'C'
            WHEN e.score >= 60   THEN 'D'
            ELSE                      'F'
       END                                   AS 등급,
       CASE WHEN e.is_retake THEN '재수강' ELSE '-' END AS 재수강
  FROM app.enrollments e
  JOIN app.students   s  ON s.id  = e.student_id      -- 교차 → 학생
  JOIN app.offerings  o  ON o.id  = e.offering_id     -- 교차 → 개설강좌
  JOIN app.courses    c  ON c.id  = o.course_id       -- 개설강좌 → 교과목
  JOIN app.semesters  sm ON sm.id = o.semester_id     -- 개설강좌 → 학기
  LEFT JOIN app.professors p ON p.id = o.professor_id -- 선택 관계이므로 LEFT
 WHERE sm.year >= 2025
   AND sm.term  = '1'
   AND e.status = '확정'
 ORDER BY sm.year, c.code, s.student_no;
