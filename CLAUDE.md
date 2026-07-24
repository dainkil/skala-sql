# CLAUDE.md — SKALA SQL 종합실습

## 리포지터리 개요
SKALA 3기 DB 종합실습. 실습 차수별로 **DB·스키마가 다르며**, 디렉터리도 분리한다.

| 디렉터리 | 실습 | Database | Schema | 주제 |
|---|---|---|---|---|
| `lab1/` | 종합실습 1 | `skala_db1` | `app` | 학사관리시스템 설계·구축 (ERD → DDL → DML → 조회) |
| `lab2/` | 종합실습 2 | `skala_db` | `lab` | 조회 심화 (Q01~Q27) |
| `lab4/` | 종합실습 4 | `skala_db4` | `ecom` | E-Commerce 분석 리포트 + 실행계획/성능 개선 |

- `lab3` 은 없다. 디렉터리 번호는 **배포 파일명의 종합실습 번호**를 따른다.
- 파일을 차수 간에 섞지 말 것. 실행 경로는 리포지터리 루트 기준
  (`psql skala_db4 -f lab4/...`)으로 쓰되, 파일 간 상호 참조 주석은 같은 디렉터리 기준이다.

## 공통 환경
- **DBMS**: PostgreSQL 17 (Homebrew 설치, 로컬)
- **접속 도구**: psql 또는 DBeaver — `localhost:5432` / 사용자 `muna` (superuser)
- **포트**: 5432 (Mac 기본은 5433일 수 있음)
- **인코딩**: UTF-8 — 한국어 콜레이션을 처음부터 지정 (나중에 바꾸면 전체 데이터 재변환 필요)
  - `createdb -E UTF8 --locale-provider=icu --icu-locale=ko-KR --template=template0 <db>`
- Docker 기반 DB는 이후 과정에서 진행 예정 (현재는 로컬 설치 기준)

```bash
brew install postgresql@17
brew services start postgresql@17          # 서비스 시작
psql postgres                              # psql 접속 (postgres=# 확인)
# ALTER USER <user> WITH PASSWORD '...';    # DB 비번 지정
psql postgres -U <계정> -W                 # 비번으로 접속
```

## 공통 코딩 규칙
- `SELECT *` 지양 — 필요한 컬럼만 명시 (**불필요한 컬럼 선택은 감점 요소**)
- 모든 쿼리에 **목적 주석** 작성 (채점 항목)
- `UPDATE` / `DELETE` 는 **반드시 WHERE 포함**
- NULL 비교는 `IS NULL` / `IS NOT NULL` (`= NULL` 금지), NULL 처리는 `COALESCE`
- 파생 컬럼·분류는 `CASE WHEN` 활용
- WHERE 절에서는 SELECT 별칭(alias) 사용 불가 — ORDER BY 에서만 가능
- 데이터 타입: 금액 `NUMERIC`, 시각 `TIMESTAMPTZ`, FK 컬럼에는 인덱스 고려
- 스크립트 실행은 항상 `psql <db> -v ON_ERROR_STOP=1 -f <file>`
  (없으면 중간 실패 후에도 계속 진행되어 반쯤 들어간 상태가 된다)

---

# lab1 — 학사관리시스템 (skala_db1 / app)

학사관리 DB를 **설계 → 구축 → 조회**. ERD 설계, 제약조건 포함 DDL, 샘플 데이터 입력,
WHERE·함수·CASE WHEN 조회 쿼리 작성.

- **테이블**
  - `majors` (학과): `id` PK, `code` UNIQUE, `name`
  - `students` (학생): `id` PK, `student_no` UNIQUE, `name`, `email` UNIQUE, `major_id` FK→majors, `grade`, `created_at`
  - `courses` (과목): `id` PK, `code` UNIQUE, `title`, `credits`
  - `enrollments` (수강 · 교차 테이블): `student_id` FK, `course_id` FK, `score`, `enrolled_at`, **PK(student_id, course_id)**
  - (선택) `professors` (교수): `id` PK, `name`
- 관계: student N:M course → enrollments 교차 테이블로 분리 (1NF~3NF 준수)
- 모든 테이블에 **제약조건 포함** DDL (PK / FK / UNIQUE / NOT NULL / CHECK)
- 각 테이블 샘플 데이터 **최소 10건 이상** INSERT

---

# lab4 — E-Commerce 분석 (skala_db4 / ecom)

## 역할과 목표
E-Commerce 데이터팀 **주니어 엔지니어** 관점에서,
월간 매출 리포트/AOV · 카테고리별 성과 · 재구매/RFM 분석 · 재고 이슈 탐지를 만들고,
**실행계획(성능)까지 개선**한다. 즉 "쿼리가 맞다"에서 끝내지 않고
"이 쿼리가 왜 느린지, 어떻게 빨라지는지"를 근거와 함께 제시하는 것이 최종 산출물이다.

## 도메인 규칙
- **채널(`orders.channel`)**: `web`, `mobile`, `marketplace`
- **주문 상태(`orders.order_status`)**: `created` / `paid` / `shipped` / `delivered` / `cancelled` / `refunded`
  - **매출로 인정하는 상태는 `paid`, `shipped`, `delivered`** (`mv_daily_gmv` 정의와 동일).
    `cancelled` / `refunded` 는 매출 집계에서 제외한다.
- **가격**: 가격이력(SCD2)으로 관리 — `product_prices(valid_from ~ valid_to, is_current)`
  - 상품별 기간 겹침 금지(EXCLUDE gist), 현재가는 상품당 1개(부분 UNIQUE 인덱스)
  - **주문 금액은 가격이력이 아니라 `order_items.unit_price` / `line_total` 로 계산**한다
    (주문 시점 가격이 이미 order_items 에 스냅샷되어 있음)
- **카테고리**: 트리 구조 (`categories.parent_id` self-FK) → **재귀 CTE** 로 전개
- **재고**: `inventory.qty_on_hand` vs `reorder_point` 로 재주문 시점 관리
- **리뷰**: 평점 1~5, `UNIQUE(product_id, customer_id)` — 효자상품 판별에 사용
- **쿠폰**: `orders.coupon_code` (예: `SAVE10`), 미사용 주문은 NULL → `IS NULL` 로 구분

## 스키마 요약 (`ecom`)
| 구분 | 객체 | 핵심 컬럼 |
|---|---|---|
| 마스터 | `country` | `country_code` PK |
| | `customers` | `customer_id` PK, `email` **citext** UNIQUE, `created_at`, `country_code` |
| | `addresses` | `address_id` PK, `customer_id` FK, `is_default` |
| | `categories` | `category_id` PK, `parent_id` self-FK (트리) |
| | `products` | `product_id` PK, `sku` UNIQUE, `category_id` FK, `active` |
| | `product_prices` | SCD2 — `price`, `valid_from`, `valid_to`, `is_current` |
| | `suppliers` / `product_suppliers` | 공급사, N:M |
| | `inventory` | `product_id` PK, `qty_on_hand`, `reorder_point` |
| 팩트 | `orders` | `order_status`, `order_ts`, `coupon_code`, `channel` |
| | `order_items` | `qty`, `unit_price`, `discount`, **`line_total` GENERATED STORED** = `unit_price*qty - discount` |
| | `payments` | `method`(card/bank/paypal/cod), `amount`, `paid_at` |
| | `shipments` | `shipped_at`, `delivered_at` |
| | `reviews` | `rating` 1~5 |
| 파생 | `mv_daily_gmv` | MATERIALIZED VIEW — 일별 GMV (매출 상태 3종만) |
| | `v_product_current_price` | 상품별 현재가 |
| | `v_category_path` | 재귀 CTE 카테고리 경로 |
| 함수 | `f_safe_div(numer, denom)` | 0으로 나누면 **0** 반환 (plpgsql) |
| | `ecom.safe_div(n, d)` | 0/NULL 이면 **NULL** 반환 (sql) — 반환값이 다르니 주의 |

시드 규모(참고): order_items 18,700 / orders 6,860 / payments 5,834 / addresses 4,056 /
shipments 3,561 / customers 3,000 / reviews 2,031 / product_prices 1,800 / products 600 / mv 124일.

## 환경 구축 절차 (완료 · 재구축 시 이 순서 그대로)
```bash
# 1) DB 생성 (UTF-8 + ko-KR)
createdb -E UTF8 --locale-provider=icu --icu-locale=ko-KR --template=template0 skala_db4

# 2) 확장을 public 에 먼저 설치 (중요 — 아래 주의사항 참고)
psql skala_db4 -c "CREATE EXTENSION IF NOT EXISTS citext SCHEMA public;
                   CREATE EXTENSION IF NOT EXISTS btree_gist SCHEMA public;"

# 3) 스키마 → 시드 순서
psql skala_db4 -v ON_ERROR_STOP=1 -f lab4/00_schema.sql
psql skala_db4 -v ON_ERROR_STOP=1 -f lab4/01_seed.sql

# 4) 스크립트에 없는 마무리
psql skala_db4 -c "REFRESH MATERIALIZED VIEW ecom.mv_daily_gmv;" -c "ANALYZE;"
psql skala_db4 -c "ALTER DATABASE skala_db4 SET search_path = ecom, public;"
```

**주의사항 (배포 스크립트의 함정)**
- 배포 스크립트는 `SET search_path = ecom, public` 뒤에 `CREATE EXTENSION` 을 하므로,
  그냥 실행하면 `citext` 타입/연산자가 `ecom` 스키마에 생성된다 →
  `search_path` 에 `ecom` 이 없는 세션에서 이메일 비교가 깨진다. **미리 `public` 에 설치**하면
  스크립트의 `IF NOT EXISTS` 가 건너뛴다 (원본 파일 수정 불필요).
- 시드 스크립트는 `product_prices` 의 배타 제약을 `[]` → **`[)`** 로 재생성한다
  (구간이 맞닿는 건 허용, 겹치는 건 금지).
- 시드는 재실행 가능(`TRUNCATE ... RESTART IDENTITY CASCADE`)하지만 **PK가 리셋**되므로,
  이전 실행 결과를 캡처해 뒀다면 값이 달라진다. 시드에 `random()` 이 쓰여 재실행할 때마다 데이터가 바뀐다.
- `mv_daily_gmv` 는 데이터 입력 **전에** 생성되므로 시드 후 `REFRESH` 하지 않으면 0행이다.

## 실습 문제 (Q1~Q11)
| # | 요구사항 | 핵심 기법 |
|---|---|---|
| Q1 | 지난 한 달 실제 판매 총액 (paid+shipped+delivered) | 상태 필터, `now() - interval '1 month'` |
| Q2 | 월별 주문 건수 / 매출 / 주문당 평균금액(AOV) | `date_trunc`, GROUP BY, 안전 나눗셈 |
| Q3 | 최근 90일 카테고리 Top10 | 카테고리 조인(+재귀 CTE로 상위 카테고리 롤업), ORDER BY LIMIT |
| Q4 | 제품별 누적매출 `RANK()` Top20 | 윈도우 함수 |
| Q5 | 고객 RFM — 최근성/빈도/금액 | 고객별 집계, `NTILE()` 등 등급화 |
| Q6 | 첫 구매 후 30일 내 재구매율 | 첫 주문일 산출(윈도우/집계) 후 self-join, 비율 계산 |
| Q7 | 재고가 임계치보다 낮은 상품 (품절 위험) | `qty_on_hand < reorder_point` |
| Q8 | 리뷰 평점 4.5↑ & 리뷰 50건↑ 효자상품 | GROUP BY + HAVING |
| Q9 | 쿠폰 사용/미사용 주문의 평균 주문금액 비교 | `coupon_code IS NULL` 기준 `CASE WHEN` 분기 |
| Q10 | 상위 1% 고객의 최근 60일 매출 | `PERCENT_RANK()`/`NTILE(100)` 또는 임계 매출 서브쿼리 |
| Q11 | 0으로 나눠도 에러 안 나는 나눗셈 함수로 평균 안전 계산 | `f_safe_div` / `ecom.safe_div` |

**쿼리 작성 시 공통 전제**
- 매출 = `SUM(order_items.line_total)`, 상태는 `('paid','shipped','delivered')`
- 기간 필터는 `orders.order_ts` (TIMESTAMPTZ) 기준 — 인덱스가 타도록 컬럼에 함수를 씌우지 말 것
  (`date_trunc('month', order_ts) = ...` 대신 `order_ts >= ... AND order_ts < ...`)
- 평균/비율은 분모 0 방지 (Q11 함수 또는 `NULLIF`)

## 성능 개선 과제
1. **병목 파악**: `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)` 으로 개선 전/후 비교.
   Seq Scan vs Index Scan, 실제 행수 vs 예상 행수 오차, 정렬/해시 spill 확인.
2. **인덱스 추가·개선**: 기존 인덱스(`idx_orders_customer_ts`, `idx_orders_status`,
   `idx_order_items_order/product`, `ux_product_prices_current` 등)로 커버되지 않는 접근 경로 식별.
   복합 인덱스 컬럼 순서, 부분 인덱스, 커버링(INCLUDE) 검토.
3. **Join 전략 비교**: Hash Join vs Nested Loop vs Merge Join, Bitmap Heap Scan 발생 조건.
   `SET enable_hashjoin = off` 같은 스위치로 강제 비교 후 **원래대로 복구**(세션 한정).
4. **Materialized View 활용**: 아래 별도 항목.
5. **(선택) 엔진별 옵티마이저 차이 정리**: Postgres / MySQL / Oracle / SQL Server.

측정할 때는 캐시 효과 때문에 **같은 쿼리를 2회 이상 실행**하고, 통계가 최신인지
(`ANALYZE`) 확인한 뒤 비교한다. 실행계획 캡처는 `lab4/captures/` 에 저장한다.

## Materialized View 전략 (mv_daily_gmv)
- 목적: 매일의 총 판매금액 조회 시 `orders ⋈ order_items` 조인 + SUM 을 매번 하지 않도록
  **미리 집계**해 리포트 쿼리를 가속.
- 정의: 매출 상태 3종만 대상, `date_trunc('day', order_ts)` 기준 `sum(line_total)`.
- **비교 실습**: 원본 조인 집계 쿼리 vs `mv_daily_gmv` 조회의 `EXPLAIN ANALYZE` 를 나란히 제시.
- **갱신 전략 검토** (데이터 변경 빈도에 맞춰 선택):
  - MV 는 **자동 갱신되지 않는다** → `REFRESH MATERIALIZED VIEW mv_daily_gmv;`
  - `CONCURRENTLY` 는 UNIQUE 인덱스 필요 (`ux_mv_daily_gmv_day` 주석 해제) — 갱신 중 조회 차단 없음, 대신 느림
  - 정리할 항목: 갱신 주기(일 1회 야간 vs 시간 단위), 지연 허용 범위(신선도),
    전체 갱신 비용 vs 증분(최근 N일만 갱신하는 대안), 락/동시성 영향

---

## 파일 구조
```
skala-sql/
├── lab1/                    # 종합실습 1 — DB 설계·구축 (skala_db1 / app)
│   ├── 00_create_db.sql     # CREATE DATABASE (postgres DB 에 접속해 실행)
│   ├── 01_ddl.sql           # CREATE SCHEMA / TABLE (제약조건 포함)
│   ├── 02_dml_insert.sql    # 샘플 데이터 (테이블별 10건 이상)
│   ├── 03_queries.sql       # SELECT / WHERE / 함수 / CASE WHEN / JOIN 조회
│   ├── erd/                 # ERD 이미지 (dbdiagram.io, ERDCloud 등)
│   └── report/              # 제출용 PDF 리포트 및 결과 화면 캡처
├── lab2/                    # 종합실습 2 — 조회 심화 (skala_db / lab)
│   ├── 00_data_fix.sql      # 배포 스크립트와 배경 문서 간 데이터 보정
│   ├── psqlrc               # 실습용 psql 설정
│   ├── queries/             # 문제별 쿼리 Q01~Q27, ALL.sql (전체 모음)
│   ├── captures/            # 실행계획(JSON) 등 결과 캡처
│   └── report/              # 제출용 리포트
├── lab4/                    # 종합실습 4 — E-Commerce 분석 (skala_db4 / ecom)
│   ├── 00_schema.sql        # 배포 스키마 스크립트 (원본: 종합실습4_ecom_schema_postgres_테이블생성.sql)
│   ├── 01_seed.sql          # 배포 시드 스크립트 (원본: 종합실습4_ecom_seed_postgres_데이터입력.sql)
│   ├── psqlrc               # search_path = ecom 용 psql 설정
│   ├── queries/             # 문제별 쿼리 Q01~Q11, ALL.sql
│   ├── tuning/              # 인덱스 추가/조인 전략/MV 비교 스크립트
│   ├── captures/            # EXPLAIN ANALYZE 결과 (개선 전/후)
│   └── report/              # 제출용 리포트
└── CLAUDE.md
```
`00_schema.sql` / `01_seed.sql` 은 **배포된 원본을 이름만 바꿔 옮긴 것**이며 내용은 수정하지 않는다.
보정이 필요하면 lab2 의 `00_data_fix.sql` 처럼 **별도 파일**로 만든다.
