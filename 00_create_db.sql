-- =====================================================================
--  00_create_db.sql — 데이터베이스 생성
--  SKALA SQL 종합실습 1
--
--  대상 : PostgreSQL 17
--  실행 : psql postgres -v ON_ERROR_STOP=1 -f 00_create_db.sql
--  이후 : psql skala_db1 -f 01_ddl.sql → 02_dml_insert.sql → 03_queries.sql
--
--  ※ 이 파일만 postgres DB 에 접속해서 실행한다.
--    CREATE DATABASE 는 자기 자신에 접속한 상태에서 실행할 수 없고,
--    트랜잭션 블록 안에서도 실행할 수 없기 때문에 01_ddl.sql 과 분리했다.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 목적 : 학사관리시스템 전용 데이터베이스 생성
--
-- 인코딩 : UTF8 — 한글 저장에 필수
-- 콜레이션 : ICU 제공자 + ko-KR 로케일
--   왜 libc 가 아니라 ICU 인가
--     libc en_US.UTF-8 로 만들면 한글 정렬이 OS 로케일 구현에 의존하고
--     플랫폼(macOS / Linux)마다 결과가 달라진다. ICU 는 DB 안에 규칙을
--     내장하므로 어디서 실행해도 동일한 한국어 사전식 정렬이 나온다.
--   왜 처음에 정해야 하는가
--     생성 후 콜레이션을 바꾸려면 DB 를 새로 만들고 전체 데이터를
--     옮겨야 한다. 인덱스도 전부 REINDEX 대상이 된다.
--
-- TEMPLATE template0
--   template1 에는 로케일이 이미 고정돼 있어 다른 로케일을 지정할 수 없다.
--   비어 있는 template0 을 써야 ICU_LOCALE 지정이 허용된다.
--
-- 검증 : psql -l  →  인코딩 UTF8 / 로케일 제공자 icu / 로케일 ko-KR
-- ---------------------------------------------------------------------
CREATE DATABASE skala_db1
    OWNER            muna
    ENCODING         'UTF8'
    LOCALE_PROVIDER  icu
    ICU_LOCALE       'ko-KR'
    LC_COLLATE       'en_US.UTF-8'
    LC_CTYPE         'en_US.UTF-8'
    TEMPLATE         template0;

COMMENT ON DATABASE skala_db1 IS 'SKALA SQL 종합실습 1 — 학사관리시스템';


-- ---------------------------------------------------------------------
-- 생성 결과 확인
-- ---------------------------------------------------------------------
SELECT datname                            AS 데이터베이스,
       pg_encoding_to_char(encoding)      AS 인코딩,
       datlocprovider                     AS 로케일제공자,   -- i = ICU
       datlocale                          AS ICU로케일
  FROM pg_database
 WHERE datname = 'skala_db1';
