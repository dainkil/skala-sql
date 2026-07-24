-- =====================================================================
--  01_ddl.sql — 학사관리시스템 스키마 정의
--  SKALA SQL 종합실습 1
--
--  대상   : PostgreSQL 17 / skala_db1 / 스키마 app
--  실행   : psql skala_db1 -v ON_ERROR_STOP=1 -f 01_ddl.sql
--  구성   : 테이블 12 · PK 12 · FK 15 · UNIQUE 11 · CHECK 25 · 인덱스 11
--           (검증: SELECT contype, count(*) FROM pg_constraint
--                    WHERE connamespace='app'::regnamespace GROUP BY contype;)
--
--  ※ CREATE DATABASE 는 이 파일에 포함하지 않는다.
--    데이터베이스에 접속한 상태에서는 자기 자신을 만들 수 없기 때문이다.
--    → 00_create_db.sql 에 분리 (postgres DB 에 접속해서 먼저 실행할 것)
-- =====================================================================


-- =====================================================================
--  0. 스키마
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS app AUTHORIZATION muna;
COMMENT ON SCHEMA app IS '학사관리 업무 테이블';

SET search_path TO app, public;


-- =====================================================================
--  ※ 재실행용 초기화 블록 (필요할 때만 주석 해제)
--    데이터가 들어있는 상태에서 실행하면 전부 삭제된다.
--    자식 → 부모 역순으로 삭제해야 FK 위반이 나지 않는다.
-- =====================================================================
--
-- DROP TABLE IF EXISTS app.enrollments        CASCADE;
-- DROP TABLE IF EXISTS app.offering_schedules CASCADE;
-- DROP TABLE IF EXISTS app.offerings          CASCADE;
-- DROP TABLE IF EXISTS app.scholarships       CASCADE;
-- DROP TABLE IF EXISTS app.registrations      CASCADE;
-- DROP TABLE IF EXISTS app.status_changes     CASCADE;
-- DROP TABLE IF EXISTS app.student_majors     CASCADE;
-- DROP TABLE IF EXISTS app.courses            CASCADE;
-- DROP TABLE IF EXISTS app.professors         CASCADE;
-- DROP TABLE IF EXISTS app.students           CASCADE;
-- DROP TABLE IF EXISTS app.departments        CASCADE;
-- DROP TABLE IF EXISTS app.semesters          CASCADE;


-- =====================================================================
--  1단계 — 독립 테이블 (다른 테이블을 참조하지 않음)
-- =====================================================================

-- 목적: 학기 마스터. 개설·등록·장학이 공통 참조하는 시간 축.
--       '2026-1' 문자열을 세 테이블에 반복 저장하지 않기 위해 엔터티로 승격.
CREATE TABLE app.semesters (
    id               BIGINT      GENERATED ALWAYS AS IDENTITY,
    year             SMALLINT    NOT NULL,
    term             VARCHAR(10) NOT NULL,
    starts_on        DATE        NOT NULL,
    ends_on          DATE        NOT NULL,
    enroll_starts_on DATE,
    enroll_ends_on   DATE,
    CONSTRAINT pk_semesters           PRIMARY KEY (id),
    CONSTRAINT uq_semesters_year_term UNIQUE (year, term),
    CONSTRAINT ck_semesters_year      CHECK (year BETWEEN 1900 AND 2100),
    CONSTRAINT ck_semesters_term      CHECK (term IN ('1','2','여름','겨울')),
    CONSTRAINT ck_semesters_period    CHECK (ends_on > starts_on),
    CONSTRAINT ck_semesters_enroll    CHECK (enroll_starts_on IS NULL
                                          OR enroll_ends_on   IS NULL
                                          OR enroll_ends_on >= enroll_starts_on)
);

-- 목적: 학과 마스터. 소속·개설의 조직 단위.
CREATE TABLE app.departments (
    id         BIGINT       GENERATED ALWAYS AS IDENTITY,
    code       VARCHAR(10)  NOT NULL,
    name       VARCHAR(100) NOT NULL,
    college    VARCHAR(50)  NOT NULL,
    created_at TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT pk_departments      PRIMARY KEY (id),
    CONSTRAINT uq_departments_code UNIQUE (code),
    CONSTRAINT uq_departments_name UNIQUE (name)
);

-- 목적: 학생 마스터.
--       학과 FK 를 두지 않는다 — 전공 정보는 student_majors 가 단일 진실 원천.
--       양쪽에 저장하면 전과 시 한쪽만 갱신되는 갱신 이상(3NF 위반)이 발생한다.
--       gender 는 NULL 허용이지만 CHECK 가 걸려 있다. NULL 비교는 unknown 이 되고
--       CHECK 는 false 일 때만 거부하므로 미기재가 정상 통과한다.
CREATE TABLE app.students (
    id             BIGINT       GENERATED ALWAYS AS IDENTITY,
    student_no     VARCHAR(10)  NOT NULL,
    name           VARCHAR(50)  NOT NULL,
    birth_date     DATE         NOT NULL,
    gender         VARCHAR(1),
    phone          VARCHAR(20),
    email          VARCHAR(255) NOT NULL,
    address        VARCHAR(200),
    admitted_on    DATE         NOT NULL,
    grade          SMALLINT     NOT NULL,
    status         VARCHAR(10)  NOT NULL DEFAULT '재학',
    privacy_agreed BOOLEAN      NOT NULL DEFAULT false,
    refund_account VARCHAR(50),
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT pk_students            PRIMARY KEY (id),
    CONSTRAINT uq_students_student_no UNIQUE (student_no),
    CONSTRAINT uq_students_email      UNIQUE (email),
    CONSTRAINT ck_students_gender     CHECK (gender IN ('M','F')),
    CONSTRAINT ck_students_grade      CHECK (grade BETWEEN 1 AND 4),
    CONSTRAINT ck_students_status     CHECK (status IN ('재학','휴학','졸업','자퇴')),
    CONSTRAINT ck_students_birth      CHECK (birth_date < admitted_on)
);


-- =====================================================================
--  2단계 — 1단계 참조
-- =====================================================================

-- 목적: 교수 마스터. 소속 학과는 필수(R2) → NOT NULL + RESTRICT.
CREATE TABLE app.professors (
    id            BIGINT       GENERATED ALWAYS AS IDENTITY,
    professor_no  VARCHAR(10)  NOT NULL,
    name          VARCHAR(50)  NOT NULL,
    department_id BIGINT       NOT NULL,
    hired_on      DATE         NOT NULL,
    email         VARCHAR(255),
    CONSTRAINT pk_professors              PRIMARY KEY (id),
    CONSTRAINT uq_professors_professor_no UNIQUE (professor_no),
    CONSTRAINT uq_professors_email        UNIQUE (email),
    CONSTRAINT fk_professors_department_id FOREIGN KEY (department_id)
        REFERENCES app.departments (id) ON DELETE RESTRICT ON UPDATE CASCADE
);

-- 목적: 교과목 카탈로그(불변에 가까움). 학기별 실체는 offerings 가 담당.
--       교양과목은 개설학과가 없을 수 있어 department_id 는 NULL 허용(R3).
--       ck_courses_liberal_area 는 두 컬럼을 동시에 보므로 테이블 레벨 CHECK 여야 한다.
CREATE TABLE app.courses (
    id            BIGINT       GENERATED ALWAYS AS IDENTITY,
    code          VARCHAR(20)  NOT NULL,
    title         VARCHAR(100) NOT NULL,
    credits       NUMERIC(3,1) NOT NULL,
    course_type   VARCHAR(10)  NOT NULL,
    liberal_area  VARCHAR(50),
    department_id BIGINT,
    CONSTRAINT pk_courses      PRIMARY KEY (id),
    CONSTRAINT uq_courses_code UNIQUE (code),
    CONSTRAINT fk_courses_department_id FOREIGN KEY (department_id)
        REFERENCES app.departments (id) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT ck_courses_credits CHECK (credits > 0),
    CONSTRAINT ck_courses_type    CHECK (course_type IN ('전공','교양','일반')),
    CONSTRAINT ck_courses_liberal_area CHECK (
           (course_type =  '교양' AND liberal_area IS NOT NULL)
        OR (course_type <> '교양' AND liberal_area IS     NULL)
    )
);

-- 목적: 전공이수 교차 테이블. 학생 N:M 학과 (주전공·이중전공·부전공 등).
--       "학생당 주전공 정확히 1개"(BR-1)는 일반 UNIQUE 로 표현할 수 없어
--       하단 5단계에서 부분 유니크 인덱스로 강제한다.
CREATE TABLE app.student_majors (
    student_id    BIGINT      NOT NULL,
    department_id BIGINT      NOT NULL,
    major_type    VARCHAR(20) NOT NULL,
    started_on    DATE        NOT NULL,
    status        VARCHAR(10) NOT NULL DEFAULT '이수중',
    CONSTRAINT pk_student_majors PRIMARY KEY (student_id, department_id, major_type),
    CONSTRAINT fk_student_majors_student_id FOREIGN KEY (student_id)
        REFERENCES app.students (id) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_student_majors_department_id FOREIGN KEY (department_id)
        REFERENCES app.departments (id) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT ck_student_majors_type CHECK (
        major_type IN ('주전공','이중전공','부전공','전공심화','마이크로디그리')),
    CONSTRAINT ck_student_majors_status CHECK (
        status IN ('이수중','이수완료','포기'))
);

-- 목적: 학적변동 이력.
--       (학번+변동일자)를 PK 로 쓰면 같은 날 복수 변동(자퇴 철회 후 휴학)을
--       표현할 수 없으므로 대리키를 쓴다.
CREATE TABLE app.status_changes (
    id          BIGINT       GENERATED ALWAYS AS IDENTITY,
    student_id  BIGINT       NOT NULL,
    change_type VARCHAR(10)  NOT NULL,
    changed_on  DATE         NOT NULL,
    reason      VARCHAR(200),
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT pk_status_changes PRIMARY KEY (id),
    CONSTRAINT fk_status_changes_student_id FOREIGN KEY (student_id)
        REFERENCES app.students (id) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT ck_status_changes_type CHECK (
        change_type IN ('휴학','복학','재입학','전과','자퇴','조기졸업'))
);

-- 목적: 등록(등록금 정산). 학기당 1건이므로 복합 PK.
--       미납금액은 저장하지 않고 (billed_amount - paid_amount) 로 파생한다.
CREATE TABLE app.registrations (
    student_id     BIGINT        NOT NULL,
    semester_id    BIGINT        NOT NULL,
    billed_amount  NUMERIC(12,2) NOT NULL,
    paid_amount    NUMERIC(12,2) NOT NULL DEFAULT 0,
    paid_on        DATE,
    is_installment BOOLEAN       NOT NULL DEFAULT false,
    CONSTRAINT pk_registrations PRIMARY KEY (student_id, semester_id),
    CONSTRAINT fk_registrations_student_id FOREIGN KEY (student_id)
        REFERENCES app.students (id) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_registrations_semester_id FOREIGN KEY (semester_id)
        REFERENCES app.semesters (id) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT ck_registrations_billed       CHECK (billed_amount >= 0),
    CONSTRAINT ck_registrations_paid         CHECK (paid_amount   >= 0),
    CONSTRAINT ck_registrations_paid_le_bill CHECK (paid_amount <= billed_amount)
);

-- 목적: 장학내역.
--       장학유형은 부가 속성이 없어 코드 테이블로 분리하지 않고 CHECK 로 통제(과설계 회피).
--       "미수혜"는 NULL 이 아니라 행 자체의 부재다 → 조회는 LEFT JOIN + COALESCE.
CREATE TABLE app.scholarships (
    id               BIGINT        GENERATED ALWAYS AS IDENTITY,
    student_id       BIGINT        NOT NULL,
    semester_id      BIGINT        NOT NULL,
    scholarship_type VARCHAR(20)   NOT NULL,
    amount           NUMERIC(12,2) NOT NULL,
    awarded_on       DATE          NOT NULL,
    CONSTRAINT pk_scholarships       PRIMARY KEY (id),
    CONSTRAINT uq_scholarships_award UNIQUE (student_id, semester_id, scholarship_type),
    CONSTRAINT fk_scholarships_student_id FOREIGN KEY (student_id)
        REFERENCES app.students (id) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_scholarships_semester_id FOREIGN KEY (semester_id)
        REFERENCES app.semesters (id) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT ck_scholarships_amount CHECK (amount > 0),
    CONSTRAINT ck_scholarships_type   CHECK (
        scholarship_type IN ('성적우수','가계곤란','국가장학','교내근로','동문','외부'))
);


-- =====================================================================
--  3단계 — 개설강좌
-- =====================================================================

-- 목적: 학기별 개설강좌(분반). courses(카탈로그)와 분리했기에
--       같은 과목의 학기별 개설과 재수강(같은 course, 다른 offering) 표현이 가능하다.
--       professor_id 만 NULL 허용(R7) — 그래서 ON DELETE SET NULL 을 쓸 수 있다.
--       NOT NULL 컬럼에는 SET NULL 을 지정할 수 없다.
CREATE TABLE app.offerings (
    id           BIGINT   GENERATED ALWAYS AS IDENTITY,
    semester_id  BIGINT   NOT NULL,
    course_id    BIGINT   NOT NULL,
    professor_id BIGINT,
    section      SMALLINT NOT NULL DEFAULT 1,
    capacity     SMALLINT NOT NULL,
    CONSTRAINT pk_offerings         PRIMARY KEY (id),
    CONSTRAINT uq_offerings_natural UNIQUE (semester_id, course_id, section),
    CONSTRAINT fk_offerings_semester_id FOREIGN KEY (semester_id)
        REFERENCES app.semesters (id) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_offerings_course_id FOREIGN KEY (course_id)
        REFERENCES app.courses (id) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_offerings_professor_id FOREIGN KEY (professor_id)
        REFERENCES app.professors (id) ON DELETE SET NULL ON UPDATE CASCADE,
    CONSTRAINT ck_offerings_section  CHECK (section  > 0),
    CONSTRAINT ck_offerings_capacity CHECK (capacity > 0)
);


-- =====================================================================
--  4단계 — 개설강좌 하위
-- =====================================================================

-- 목적: 강의시간. '월3,수4' 처럼 한 칸에 여러 값을 넣으면 1NF 위반이고
--       "수요일 4교시 수업" 조회가 문자열 파싱이 되어 인덱스를 탈 수 없다.
--       요일·교시로 원자화하여 개인시간표와 강의실 중복 검사를 SQL 로 해결한다.
CREATE TABLE app.offering_schedules (
    id          BIGINT      GENERATED ALWAYS AS IDENTITY,
    offering_id BIGINT      NOT NULL,
    day_of_week SMALLINT    NOT NULL,
    period      SMALLINT    NOT NULL,
    classroom   VARCHAR(30) NOT NULL,
    CONSTRAINT pk_offering_schedules PRIMARY KEY (id),
    CONSTRAINT uq_offering_schedules UNIQUE (offering_id, day_of_week, period),
    CONSTRAINT fk_offering_schedules_offering_id FOREIGN KEY (offering_id)
        REFERENCES app.offerings (id) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT ck_offering_schedules_day    CHECK (day_of_week BETWEEN 1 AND 5),
    CONSTRAINT ck_offering_schedules_period CHECK (period      BETWEEN 1 AND 9)
);

-- 목적: 수강신청 교차 테이블. 학생 N:M 개설강좌 + 성적 속성.
--       PK(student_id, offering_id) 가 곧 "동일 강좌 중복신청 불가"(BR-2) 제약이다.
--       score NULL = 미채점. 성적등급은 저장하지 않고 조회 시 CASE WHEN 으로 파생.
--       is_retake 는 파생 가능하지만 신청 시점 판정의 스냅샷이므로 저장한다.
CREATE TABLE app.enrollments (
    student_id  BIGINT      NOT NULL,
    offering_id BIGINT      NOT NULL,
    enrolled_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    status      VARCHAR(10) NOT NULL DEFAULT '신청',
    score       NUMERIC(5,2),
    is_retake   BOOLEAN     NOT NULL DEFAULT false,
    CONSTRAINT pk_enrollments PRIMARY KEY (student_id, offering_id),
    CONSTRAINT fk_enrollments_student_id FOREIGN KEY (student_id)
        REFERENCES app.students (id) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_enrollments_offering_id FOREIGN KEY (offering_id)
        REFERENCES app.offerings (id) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT ck_enrollments_status CHECK (status IN ('신청','확정','취소')),
    CONSTRAINT ck_enrollments_score  CHECK (score BETWEEN 0 AND 100)
);


-- =====================================================================
--  5단계 — 인덱스
--
--  PostgreSQL 은 외래키에 인덱스를 자동 생성하지 않는다. 자동인 것은 PK 와 UNIQUE 뿐.
--  인덱스 없는 FK 는 JOIN 이 느릴 뿐 아니라 부모 삭제 시
--  CASCADE / RESTRICT 검사가 자식 테이블을 전체 스캔한다.
--
--  단, PK/UNIQUE 인덱스의 "선두 컬럼"으로 이미 커버되는 FK 는 만들지 않는다.
--  아래 3개는 중복이라 생략했다:
--    offerings(semester_id)           → uq_offerings_natural 선두
--    offering_schedules(offering_id)  → uq_offering_schedules 선두
--    scholarships(student_id)         → uq_scholarships_award 선두
-- =====================================================================

CREATE INDEX idx_student_majors_department_id ON app.student_majors (department_id);
CREATE INDEX idx_status_changes_student_id    ON app.status_changes (student_id);
CREATE INDEX idx_professors_department_id     ON app.professors     (department_id);
CREATE INDEX idx_courses_department_id        ON app.courses        (department_id);
CREATE INDEX idx_offerings_course_id          ON app.offerings      (course_id);
CREATE INDEX idx_offerings_professor_id       ON app.offerings      (professor_id);
CREATE INDEX idx_registrations_semester_id    ON app.registrations  (semester_id);
CREATE INDEX idx_scholarships_semester_id     ON app.scholarships   (semester_id);

-- 복합 PK (student_id, offering_id) 는 왼쪽 접두사로만 쓰이므로
-- "이 강좌의 수강생 명단"(WHERE offering_id = ?) 에는 별도 인덱스가 필요하다.
CREATE INDEX idx_enrollments_offering_id      ON app.enrollments    (offering_id);

-- 조회 패턴 인덱스 — Q1 재학생 조회가 가장 빈번하다.
CREATE INDEX idx_students_status              ON app.students       (status);

-- BR-1: 학생당 주전공은 정확히 1개.
-- 일반 UNIQUE(student_id) 는 부전공까지 막으므로 부분 인덱스가 필요하다.
CREATE UNIQUE INDEX uq_student_majors_primary
    ON app.student_majors (student_id)
    WHERE major_type = '주전공';


-- =====================================================================
--  6단계 — 주석 (설계 의도 기록)
-- =====================================================================

COMMENT ON TABLE app.semesters          IS '학기 마스터 — 개설·등록·장학의 공통 시간 축';
COMMENT ON TABLE app.departments        IS '학과 마스터';
COMMENT ON TABLE app.students           IS '학생 마스터 — 전공은 student_majors 가 단일 진실 원천';
COMMENT ON TABLE app.status_changes     IS '학적변동 이력 (휴학·복학·전과·자퇴)';
COMMENT ON TABLE app.student_majors     IS '전공이수 교차 테이블 — 학생 N:M 학과 (다중전공)';
COMMENT ON TABLE app.professors         IS '교수 마스터';
COMMENT ON TABLE app.courses            IS '교과목 카탈로그';
COMMENT ON TABLE app.offerings          IS '개설강좌 — 학기별 분반 실체';
COMMENT ON TABLE app.offering_schedules IS '강의시간 — 요일·교시 원자화 (1NF)';
COMMENT ON TABLE app.enrollments        IS '수강신청 교차 테이블 — 학생 N:M 개설강좌 (성적 보유)';
COMMENT ON TABLE app.registrations      IS '등록 — 학기별 등록금 정산';
COMMENT ON TABLE app.scholarships       IS '장학내역';

COMMENT ON COLUMN app.students.status        IS '의도적 역정규화 — status_changes 에서 파생 가능하나 스냅샷 유지';
COMMENT ON COLUMN app.enrollments.score      IS 'NULL = 미채점. 등급은 저장하지 않고 CASE WHEN 으로 파생';
COMMENT ON COLUMN app.enrollments.is_retake  IS '신청 시점 판정의 스냅샷 (파생 아님)';
COMMENT ON COLUMN app.offerings.professor_id IS 'NULL = 담당교수 미배정';
COMMENT ON COLUMN app.registrations.paid_on  IS 'NULL = 미납';
COMMENT ON COLUMN app.courses.liberal_area   IS 'NULL = 교양과목이 아님 (조건부 CHECK 로 정합성 보장)';


-- =====================================================================
--  7단계 — 검증
-- =====================================================================

-- 목적: 테이블 12개 생성 확인
SELECT table_name AS 테이블
  FROM information_schema.tables
 WHERE table_schema = 'app' AND table_type = 'BASE TABLE'
 ORDER BY table_name;

-- 목적: 제약조건 종류별 집계
SELECT CASE c.contype WHEN 'p' THEN 'PRIMARY KEY'
                      WHEN 'f' THEN 'FOREIGN KEY'
                      WHEN 'u' THEN 'UNIQUE'
                      WHEN 'c' THEN 'CHECK' END AS 제약종류,
       COUNT(*) AS 개수
  FROM pg_constraint c
  JOIN pg_namespace  n ON n.oid = c.connamespace
 WHERE n.nspname = 'app'
 GROUP BY c.contype
 ORDER BY c.contype;

-- 목적: 인덱스 목록
SELECT tablename AS 테이블, indexname AS 인덱스
  FROM pg_indexes
 WHERE schemaname = 'app'
 ORDER BY tablename, indexname;
