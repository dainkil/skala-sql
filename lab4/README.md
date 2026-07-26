# lab4 — E-Commerce 쿼리 튜닝 리포트

`skala_db4` / 스키마 `ecom`. 각 문항을 **작성 → EXPLAIN ANALYZE 병목 파악 → 인덱스/조인/MV 처방 → 재측정** 순으로 튜닝한다.

**측정 기준:** `EXPLAIN (ANALYZE, BUFFERS)`, 2회차 값 채택, 비교는 `Execution Time`. 캡처는 `captures/Q0X_{before,after,joins}.txt`. 시드가 `random()` 기반이라 수치는 스냅샷이며 재적재하면 달라진다.

**환경:** PostgreSQL 17(로컬), 접속 계정 `dain`(superuser). Q01~Q11 의 튜닝 전/후 쿼리를 한 파일에서 실행·대조할 수 있게 `queries/ALL.sql` 로 묶었다. 앞머리에서 튜닝 후 쿼리가 의존하는 인덱스와 MV(사전집계 3종)를 먼저 만들고, 문항마다 `[튜닝 전]`·`[튜닝 후]` 를 나란히 실행한다.

## 1. 문항별 튜닝 요약

| 문항 | 주제 | 병목 | 처방 | 개선 |
|---|---|---|---|---|
| **Q01** | 최근 1개월 실판매 총액 | `COUNT(DISTINCT)`가 부른 Sort(219kB) | 불필요한 컬럼 제거 → Sort 소멸 | **8.36→4.99ms (~40%↓)** |
| **Q02** | 월별 주문수/매출/AOV | `COUNT(DISTINCT)`가 부른 Sort(952kB) + order_items 18,700행 조인 스캔 | ①매출=MV 롤업·건수=orders 단독(조인·Sort 제거) ②부분 커버링 인덱스로 Index-Only Scan | **12.16→2.07ms (~83%↓)** |
| **Q03** | 최근 90일 카테고리 Top10 | order_items 18,700행 조인 + 집계(HJ). order_ts 61% 통과라 인덱스 기각 | 카테고리×일 사전집계 MV(`mv_category_daily`)로 조인 대체 | **12.35→1.11ms (~91%↓)** |
| **Q04** | 제품별 누적매출 RANK Top20 | order_items 18,700행 조인→제품 집계(HJ). 누적이라 날짜필터 없음→인덱스 무의미 | 제품 누적매출 MV(`mv_product_revenue`, 600행)로 조인 대체 후 RANK | **10.76→0.55ms (~95%↓)** |
| **Q05** | 고객 RFM(최근성·빈도·금액) | order_items 조인 + `COUNT(DISTINCT)` Sort(1065kB) | 고객 집계 MV(`mv_customer_rev`)로 조인·대형Sort 제거. 세 지표(recency/frequency/monetary)만 조회 | **17.85→5.54ms (~69%↓)** |
| **Q06** | 30일 내 재구매율 | `orders` 2회 Seq Scan + self-join(30일 window=Join Filter) | **쿼리 재작성**: `MIN() OVER`로 첫주문일 부여→단일 스캔, self-join 제거(MV 미사용) | **8.55→5.98ms (~30%↓)**, Buffers 142→74 |
| **Q07** | 품절 위험 재고 | 없음 — inventory(600)⋈products(600), 이미 ~0.4ms | **불필요 컬럼 제거**: product_name·active 를 빼고 식별자+재고근거+부족분만. 인덱스/조인은 검토 후 유지 | **0.385ms (컬럼 정리)** |
| **Q08** | 효자상품(평점4.5↑·리뷰50↑) | reviews(2031)⋈products 조인을 먼저 → 2031행에 상품정보 실어 GROUP BY | **집계-후-조인 재작성**: reviews 먼저 집계+HAVING(12개)→살아남은 12개만 조인 | **1.94→0.79ms (~59%↓)** |
| **Q09** | 쿠폰 사용/미사용 AOV 비교 | order_items⋈orders(14,522행) 위 `COUNT(DISTINCT)`용 Sort(1030kB, ~9ms) | **매출/건수 분리**(Q02 패턴): 매출=조인 후 2그룹 SUM, 주문수=orders 단독 COUNT → DISTINCT·Sort 소멸 | **16.04→6.95ms (~57%↓)** |
| **Q10** | 상위 1% 고객 최근 60일 매출 | `customer_total` 대전집계(order_items 18,700⋈orders→2,246고객)로 상위1% 판별 (~9.7ms) | **MV 재사용**: 랭킹을 `mv_customer_rev.monetary`로 대체, 60일 매출만 실데이터 조인 | **14.33→7.06ms (~51%↓)** |
| **Q11** | 안전 나눗셈 평균 | 리뷰 0건 상품 다수 → 0/0 division by zero (수동 평균) | **함수 선택**: sql `safe_div`는 인라인(=NULLIF 동일 1.28ms), plpgsql `f_safe_div`는 미인라인 2.87ms → safe_div 채택 | **4.10→1.28ms (~69%↓)** |

문항 성격에 따라 개선 수단이 갈린다. Q02~Q04 는 무거운 팩트 조인을 사전집계 MV 로 대체했고, Q06 은 self-join 을 윈도우 함수 재작성으로 단일 스캔으로 바꿨으며, Q08 은 집계-후-조인으로 조인 입력을 2,031행에서 12행으로 줄였다. Q01·Q05·Q07 처럼 결과에 필요한 컬럼만 남기는 것도 튜닝의 한 축이다. Q05 는 요구대로 고객별 최근성·빈도·금액 세 지표만 조회하도록 정리했고, Q07 은 인덱스·조인이 이미 최적(~0.4ms)이라 개선점을 품절 판단에 쓰지 않는 `product_name·active` 를 빼는 컬럼 정리로 잡았다.

**인덱스 추가/개선**(`tuning/indexes.sql`) — Q02 에 부분 커버링 인덱스 `idx_orders_rev_ts = orders(order_ts) WHERE status IN(3)` 를 추가해 월별 주문건수 집계를 `Seq Scan`에서 `Index Only Scan`(Heap Fetches 0)으로 바꿨다(4.69→2.07ms). 같은 인덱스를 Q01 에도 검토했지만 Q01 은 `line_total`(order_items 조인)이 필요해 커버가 안 되고 선택도도 21%라 플래너가 Seq Scan 을 유지했다. Q07 의 부분 커버링 인덱스, Q08 의 커버링 인덱스도 만들어 봤으나 대상이 수백~2천 행으로 작아 전건 스캔이 더 싸서 플래너가 쓰지 않았다. 인덱스는 대형 테이블과 낮은 선택도에서만 의미가 있다는 점을 반대 사례로 확인했다.

## 2. 세 가지 조인 방식의 차이

PostgreSQL 플래너가 등가 조인을 처리할 때 고르는 물리 연산은 Nested Loop Join, Hash Join, Sort-Merge Join 세 가지다. 이번 실습의 핵심 조인인 `order_items ⋈ orders`(매출 상태 필터)를 대상으로 `enable_hashjoin`, `enable_mergejoin` 스위치를 꺼 가며 세 방식을 강제로 비교했고, 근거는 `captures/Q0X_joins.txt` 에 남겼다.

Nested Loop 은 바깥 테이블의 행마다 안쪽 테이블을 반복 탐색한다. 한쪽이 아주 작고 다른 쪽에 인덱스가 있을 때 유리하며 정렬도 필요 없고 메모리도 거의 안 쓴다. 그러나 행이 많아지면 반복 횟수가 곱으로 늘어 접근량이 폭증한다. Hash Join 은 작은 쪽으로 해시 테이블을 만들고 큰 쪽을 한 번 훑어 매칭한다. 큰 테이블끼리의 등가 조인에 가장 잘 맞고 정렬이 필요 없지만, 해시가 작업 메모리를 넘으면 디스크로 분할되며 느려진다. Sort-Merge 는 양쪽을 정렬한 뒤 병합하는 방식으로, 입력이 이미 정렬돼 있으면 좋지만 그렇지 않으면 정렬 비용이 부담이다.

실측에서 확인한 것은 세 가지다. 첫째, 대형 테이블 간 등가 조인에서는 Hash Join 의 cost 가 항상 가장 낮았다. Q01 의 `order_items ⋈ orders` 에서 Hash Join cost 651 에 비해 Sort-Merge 1001, Nested Loop 1610 이었고, Q03 의 4중 조인은 Hash Join 903 대 Sort-Merge 2172, Nested Loop 4417 로 격차가 더 컸다. 둘째, Nested Loop 에는 함정이 있다. 데이터가 작고 전부 캐시에 올라 있으면 실측 wall-clock 은 오히려 Nested Loop 이 빠를 때가 있는데, 이는 반복 접근이 전부 메모리 히트라 거의 공짜이기 때문이다. Q01 에서 Nested Loop 의 Buffers 는 4,363 으로 Hash Join 의 252 보다 17배 많았고, Q09·Q10 에서는 62배(16,000여 buffers)까지 벌어졌다. 데이터가 커지거나 캐시 미스가 나면 이 접근량이 그대로 지연으로 돌아오므로, 실행시간만 보지 말고 cost·Buffers·loops 를 함께 봐야 한다. 셋째, Sort-Merge 는 `order_items` 가 `idx_order_items_order` 로 이미 정렬돼 있어 나쁘지 않았지만 반대쪽을 정렬하는 비용 때문에 Hash Join 보다 cost 가 높았다.

결국 조인 전략 자체는 플래너의 Hash Join 선택이 모든 문항에서 최적이라 강제로 바꾼 것은 없다. 한 걸음 더 나아간 튜닝은 어떤 조인이 빠른가가 아니라 조인을 없애거나 줄이는 것이었다. Q02~Q04 는 사전집계 MV 로 무거운 팩트 조인을 MV 읽기로 대체했고, Q06 은 윈도우 함수로 self-join 을 단일 스캔으로 바꿨으며, Q08 은 집계-후-조인으로 조인 입력을 2,031행에서 12행으로 줄였다.

## 3. Materialized View 생성 스크립트와 실행 후 결과 화면

대상은 일별 총 판매금액을 미리 집계해 두는 `mv_daily_gmv` 다. 매번 `orders ⋈ order_items` 를 조인해 SUM 하는 대신, 하루 단위로 확정된 값을 저장해 두고 리포트가 그 스냅샷만 읽게 하는 것이 목적이다. 스크립트는 `tuning/mv_daily_gmv.sql`, 갱신 셸은 `tuning/refresh_mv_daily_gmv.sh` 이며 아래 순서대로 진행한다. 다른 MV 인 `mv_category_daily`·`mv_product_revenue`·`mv_customer_rev` 는 같은 형식으로 별도 정리한다.

**1단계 — MV 정의 확인.** 매출 인정 상태(paid/shipped/delivered) 3종만 대상으로, `date_trunc('day', order_ts)` 기준 `sum(line_total)` 을 집계한 뷰다.

```sql
SELECT definition FROM pg_matviews WHERE matviewname = 'mv_daily_gmv';
```
```
  SELECT date_trunc('day'::text, o.order_ts) AS day,
     sum(oi.line_total) AS gmv
    FROM (orders o
      JOIN order_items oi ON ((oi.order_id = o.order_id)))
   WHERE (o.order_status = ANY (ARRAY['paid','shipped','delivered']))
   GROUP BY (date_trunc('day'::text, o.order_ts));
```

**2단계 — 무중단 갱신용 UNIQUE 인덱스 생성.** `REFRESH ... CONCURRENTLY` 는 유니크 인덱스가 있어야 동작한다. 배포 스키마에 주석으로만 있던 인덱스를 실제로 만든다.

```sql
CREATE UNIQUE INDEX IF NOT EXISTS ux_mv_daily_gmv_day ON ecom.mv_daily_gmv (day);
```
```
CREATE INDEX
```

**3단계 — 갱신 실행.** MV 는 조회할 때 재계산하지 않고 저장된 스냅샷만 읽는다. 실제 재계산은 REFRESH 할 때만 일어나며, CONCURRENTLY 를 쓰면 갱신 중에도 조회가 막히지 않는다.

```sql
REFRESH MATERIALIZED VIEW CONCURRENTLY ecom.mv_daily_gmv;
```
```
REFRESH MATERIALIZED VIEW
```

**4단계 — 적재 결과·신선도 확인.** 137일 치가 적재됐고 전체 GMV 는 2,623,426.45 다. 시드가 `random()` 기반이라 재적재 시 이 수치는 달라진다.

```sql
SELECT count(*) AS rows, min(day)::date AS first_day, max(day)::date AS last_day,
       to_char(sum(gmv), 'FM999,999,999.00') AS total_gmv
FROM ecom.mv_daily_gmv;
```
```
 rows | first_day  |  last_day  |  total_gmv
------+------------+------------+--------------
  137 | 2026-03-28 | 2026-08-18 | 2,623,426.45
```

**5단계 — 가속 실증.** 같은 결과를 얻는 두 방식을 `EXPLAIN (ANALYZE, BUFFERS)` 로 비교했다. 원본 조인 집계는 order_items 와 orders 를 각각 Seq Scan 한 뒤 Hash Join 하고 HashAggregate 로 모으는데, 8천여 행을 처리하며 실행시간이 약 11ms(콜드 실행 시 ~29ms), Buffers 138 이 나온다. 반면 MV 조회는 미리 계산된 137행을 한 번 훑기만 하므로 실행시간 0.05ms, Buffers 1 이다.

```sql
-- before: 원본 조인 집계
EXPLAIN (ANALYZE, BUFFERS)
SELECT date_trunc('day', o.order_ts) AS day, sum(oi.line_total) AS gmv
FROM ecom.orders o JOIN ecom.order_items oi ON oi.order_id = o.order_id
WHERE o.order_status IN ('paid','shipped','delivered') GROUP BY 1;
```
```
 HashAggregate  (actual time=11.298..11.367 rows=137)   Buffers: shared hit=138
   ->  Hash Join  (actual time=2.309..8.968 rows=7985)
         ->  Seq Scan on order_items oi  (rows=10165)
         ->  Hash -> Seq Scan on orders o  (rows=2906)
 Execution Time: 11.3 ms
```
```sql
-- after: MV 조회
EXPLAIN (ANALYZE, BUFFERS) SELECT day, gmv FROM ecom.mv_daily_gmv;
```
```
 Seq Scan on mv_daily_gmv  (actual time=0.007..0.019 rows=137)   Buffers: shared hit=1
 Execution Time: 0.053 ms
```

두 테이블을 조인하고 집계하던 작업이 미리 계산된 137행을 읽는 것으로 바뀌면서 실행시간과 버퍼 접근량이 모두 크게 줄었다.

**갱신 전략.** MV 는 자동으로 갱신되지 않으므로 신선도를 어떻게 관리할지 정해야 한다. 이 리포트는 매일 오후 3시에 한 번 REFRESH 하는 방식으로 설계했다. 과거일은 확정값이라 다시 계산할 필요가 없고 당일 데이터만 갱신 대상이므로 하루 1회로 충분하며, 갱신 중 조회를 막지 않기 위해 CONCURRENTLY 를 쓴다. 핵심은 조회·갱신·원본 변경이 서로 분리돼 있다는 점이다. 리포트 조회는 스냅샷만 읽고, 재계산은 스케줄러의 REFRESH 가 담당하며, 원본 변경은 다음 REFRESH 전까지 MV 에 반영되지 않는다. 실제 스케줄은 `pg_cron` 대신 OS 스케줄러(launchd 또는 cron)로 `refresh_mv_daily_gmv.sh` 를 오후 3시에 호출하도록 설계했다.

## 4. DBMS 엔진별 옵티마이저

네 엔진 모두 비용 기반 옵티마이저(CBO)를 쓴다. 통계로 각 연산의 비용을 추정하고 가장 싼 실행계획을 고른다는 큰 틀은 같지만, 지원하는 조인 알고리즘, 힌트 철학, 실행 중 계획을 바꾸는 능력, MV 를 자동으로 활용하는지에서 차이가 뚜렷하다.

PostgreSQL 은 세 가지 조인과 Seq·Index·Bitmap 스캔을 모두 갖췄고, 이번 실습처럼 `enable_hashjoin` 같은 세션 스위치로 연산을 강제해 비교할 수 있다. 특징은 쿼리 힌트를 기본으로 제공하지 않는다는 점이다. 플래너를 신뢰하고, 문제가 있으면 통계를 갱신(ANALYZE)하거나 다중 컬럼 상관관계용 확장 통계(CREATE STATISTICS)로 추정을 개선하라는 설계 철학이다. 조인 대상이 많아지면 유전 알고리즘 기반 GEQO 로 탐색 공간을 줄인다. 계획은 실행 전에 확정되며 실행 도중 바꾸는 적응형 기능은 내장돼 있지 않다. MV 는 만들어 두더라도 쿼리가 명시적으로 참조해야 쓰인다. 자동 재작성이 없기 때문에 이번 실습에서도 각 쿼리를 직접 MV 기준으로 고쳐 썼다.

MySQL(InnoDB) 은 전통적으로 조인 알고리즘이 단순해서 오랫동안 중첩 루프 계열만 지원했고 Sort-Merge Join 은 없다. 8.0.18 에서야 인덱스 없는 등가 조인에 한해 Hash Join 이 들어왔다. 대형 테이블 간 조인 최적화의 폭이 상대적으로 좁다는 뜻이다. 대신 8.0 부터 옵티마이저 힌트와 히스토그램 통계를 지원하고 `USE/FORCE INDEX` 같은 인덱스 힌트로 사람이 개입할 여지를 준다. 실행 중 계획을 바꾸는 적응형 기능이나 MV, 그리고 MV 자동 재작성 자체가 없다는 점이 다른 세 엔진과 크게 다르다.

Oracle 은 가장 성숙한 옵티마이저로 세 조인을 모두 지원하고 힌트 체계가 방대하다. 12c 부터 적응형 계획(Adaptive Plans)을 도입해 실행 초반의 실제 행 수를 보고 중첩 루프와 해시 조인 사이를 런타임에 전환할 수 있다. SQL Plan Management(계획 베이스라인)로 좋은 계획을 고정하고, 바인드 변수 값에 따라 계획을 달리 뽑는 bind peeking 도 갖췄다. 특히 MV 쿼리 재작성이 자동이라, 사용자가 원본 테이블로 질의해도 옵티마이저가 알아서 적합한 MV 로 바꿔 읽는다. 우리가 Postgres 에서 손으로 했던 MV 로 조인 대체를 엔진이 대신 해 주는 셈이다.

SQL Server 는 세 조인을 모두 지원하며 힌트와 플랜 가이드를 제공한다. 2014년의 새 카디널리티 추정기, 2017년의 적응형 조인(Batch Mode Adaptive Joins)으로 해시와 중첩 루프를 런타임에 고르고, Query Store 로 계획 이력을 관리하며 성능이 퇴행한 계획을 자동으로 교정한다. Oracle 의 MV 에 해당하는 인덱스 뷰(Indexed View)는 조건이 맞으면 옵티마이저가 자동으로 활용한다.

정리하면, Postgres 는 힌트로 옵티마이저를 강제하기보다 통계를 맞추고 쿼리·MV 구조를 바꿔 해결하는 방향이 자연스럽다. 같은 목표를 Oracle 이나 SQL Server 라면 MV 자동 재작성이나 적응형 조인으로 엔진이 더 많이 대신 처리했을 것이고, MySQL 이라면 조인 알고리즘과 MV 부재 탓에 쿼리·인덱스 설계에 더 기대야 했을 것이다.

## 함수·표현식 최적화 (Q11 참고)

리뷰 0건 상품 때문에 수동 평균 `COALESCE(합,0)/COALESCE(개수,0)` 이 0/0 → division by zero 가 된다. 안전 나눗셈 함수로 막는데, 어떤 함수를 쓰느냐가 곧 성능이었다. sql 로 짠 `ecom.safe_div` 는 플래너가 식으로 인라인해 순수 `NULLIF` 와 같은 1.28ms 였고, plpgsql 로 짠 `ecom.f_safe_div` 는 인라인되지 않아 행마다 함수를 호출하느라 2.87ms 로 약 2.2배 느렸다. 반환값 의미도 갈리는데, 리뷰 없음은 0 이 아니라 NULL(평가 없음)이 맞으므로 `safe_div`(→NULL)가 속도·의미 모두 적합하고, `f_safe_div`(→0)는 없으면 0 으로 볼 지표(매출·건수)에 어울린다.
