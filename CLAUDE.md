# CLAUDE.md — SKALA SQL 종합실습 1

## 프로젝트 개요
학사관리시스템(Academic Management System) DB를 **설계 → 구축 → 조회**하는 실습.
PostgreSQL 환경에서 ERD 설계, DDL로 테이블 생성, DML로 데이터 입력/조회를 수행하고
WHERE·함수·CASE WHEN을 활용한 쿼리를 작성한다.

## 환경
- **DBMS**: PostgreSQL 17 (Homebrew 설치)
- **접속 도구**: psql 또는 DBeaver
- **포트**: 5432 (Mac 기본은 5433일 수 있음)
- **인코딩**: UTF-8 — 한국어 콜레이션을 처음부터 올바르게 지정 (나중에 바꾸면 전체 데이터 재변환 필요)
- Docker 기반 DB는 이후 과정에서 진행 예정 (현재는 로컬 설치 기준)

## 주요 명령어
```bash
brew install postgresql@17
brew services start postgresql@17          # 서비스 시작
psql postgres                              # psql 접속 (postgres=# 확인)
# ALTER USER <user> WITH PASSWORD '...';    # DB 비번 지정 (필수)
psql postgres -U <계정> -W                 # 비번으로 접속
```

## DB 구조 (권장 스키마, 수정 가능)
- **Database**: `skala_db`
- **Schema**: `app` (애플리케이션), 필요 시 `audit`
- **테이블**
  - `majors` (학과): `id` PK, `code` UNIQUE, `name`
  - `students` (학생): `id` PK, `student_no` UNIQUE, `name`, `email` UNIQUE, `major_id` FK→majors, `grade`, `created_at`
  - `courses` (과목): `id` PK, `code` UNIQUE, `title`, `credits`
  - `enrollments` (수강 · 교차 테이블): `student_id` FK, `course_id` FK, `score`, `enrolled_at`, **PK(student_id, course_id)**
  - (선택) `professors` (교수): `id` PK, `name`
- 관계: student N:M course → enrollments 교차 테이블로 분리 (1NF~3NF 준수)

## 코딩 규칙
- 모든 테이블에 **제약조건 포함** DDL 작성 (PK / FK / UNIQUE / NOT NULL / CHECK)
- 데이터 타입: 금액 `NUMERIC`, 시각 `TIMESTAMPTZ`, FK 컬럼에는 인덱스 고려
- 각 테이블 샘플 데이터 **최소 10건 이상** INSERT
- `UPDATE` / `DELETE`는 **반드시 WHERE 포함** (없으면 전체 행 영향)
- `SELECT *` 지양 — 필요한 컬럼만 명시 (**불필요한 컬럼 선택은 감점 요소**)
- 모든 쿼리에 **목적 주석** 작성 (채점 항목)
- NULL 비교는 `IS NULL` / `IS NOT NULL` 사용 (`= NULL` 금지)
- NULL 처리는 `COALESCE`, 파생 컬럼은 `CASE WHEN` 활용
- WHERE 절에서는 SELECT 별칭(alias) 사용 불가 — ORDER BY에서만 가능

## 실습 과제 체크리스트
1. `CREATE DATABASE` / `CREATE SCHEMA` 실행
2. ERD 설계 (범례 포함, 연결선 겹침 금지)
3. `CREATE TABLE` — 제약조건 포함 DDL 작성
4. `INSERT INTO` — 테이블별 10건 이상 샘플 데이터
5. `SELECT + WHERE + ORDER BY` 기초 조회
6. `COALESCE` / `CASE WHEN` / 날짜 함수(`EXTRACT`, `DATE_TRUNC`, `TO_CHAR`, `INTERVAL`) 활용
7. 수강신청 교차 테이블 JOIN 조회

## 제출물 (당일 제출 원칙)
- **ERD (학사관리시스템)**: 범례 설명문 추가, 각 연결관계가 명확히 보이도록 (선 겹침 금지)
- **리포트 (PDF)**:
  - 학사관리시스템 요구사항 (설계 방향)
  - PostgreSQL 접속 결과 화면
  - 문항별 실습 결과 — SQL문 + 실행 결과 화면 필수 (**항목 누락 시 감점**)

## 권장 파일 구조
```
skala-sql/
├── 01_ddl.sql          # CREATE DATABASE / SCHEMA / TABLE (제약조건 포함)
├── 02_dml_insert.sql   # 샘플 데이터 (테이블별 10건 이상)
├── 03_queries.sql      # SELECT / WHERE / 함수 / CASE WHEN / JOIN 조회
├── erd/                # ERD 이미지 (dbdiagram.io, ERDCloud 등)
└── report/             # 제출용 PDF 리포트 및 결과 화면 캡처
```