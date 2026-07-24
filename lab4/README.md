# lab4 — E-Commerce 쿼리 튜닝 리포트

`skala_db4` / 스키마 `ecom`. 각 문항을 **작성 → EXPLAIN ANALYZE 병목 파악 → 인덱스/조인/MV 처방 → 재측정** 순으로 튜닝한다.

**측정 기준:** `EXPLAIN (ANALYZE, BUFFERS)`, 2회차 값 채택, 비교는 `Execution Time`.
캡처는 `captures/Q0X_{before,after,joins}.txt`. (시드가 `random()` 기반이라 수치는 스냅샷)

## 문항별 요약

| 문항 | 주제 | 병목 | 처방 | 개선 |
|---|---|---|---|---|
| **Q01** | 최근 1개월 실판매 총액 | `COUNT(DISTINCT)`가 부른 Sort(219kB) | 불필요한 컬럼 제거 → Sort 소멸 | **8.36→4.99ms (~40%↓)** |
| **Q02** | 월별 주문수/매출/AOV | `COUNT(DISTINCT)`가 부른 Sort(952kB) + order_items 18,700행 조인 스캔 | ①매출=MV 롤업·건수=orders 단독(조인·Sort 제거) ②부분 커버링 인덱스로 Index-Only Scan | **12.16→2.07ms (~83%↓)** |
| **Q03** | 최근 90일 카테고리 Top10 | order_items 18,700행 조인 + 집계(HJ). order_ts 61% 통과라 인덱스 기각 | 카테고리×일 사전집계 MV(`mv_category_daily`)로 조인 대체 | **12.35→1.11ms (~91%↓)** |
| **Q04** | 제품별 누적매출 RANK Top20 | order_items 18,700행 조인→제품 집계(HJ). 누적이라 날짜필터 없음→인덱스 무의미 | 제품 누적매출 MV(`mv_product_revenue`, 600행)로 조인 대체 후 RANK | **10.76→0.55ms (~95%↓)** |
| **Q05** | 고객 RFM | order_items 조인 + `COUNT(DISTINCT)` Sort(1065kB) + NTILE 3중 정렬 | 고객 집계 MV(`mv_customer_rev`)로 조인·대형Sort 제거, NTILE는 조회 시 | **17.85→5.54ms (~69%↓)** |
| **Q06** | 30일 내 재구매율 | `orders` 2회 Seq Scan + self-join(30일 window=Join Filter) | **쿼리 재작성**: `MIN() OVER`로 첫주문일 부여→단일 스캔, self-join 제거(MV 미사용) | **8.55→5.98ms (~30%↓)**, Buffers 142→74 |
| **Q07** | 품절 위험 재고 | 없음 — inventory(600)⋈products(600), 이미 ~0.4ms | **변경 없음**: 부분 인덱스 검토→기각(소규모라 Seq Scan 최적, 강제 시 더 느림) | **0.385ms (튜닝 불필요)** |
| **Q08** | 효자상품(평점4.5↑·리뷰50↑) | reviews(2031)⋈products 조인을 먼저 → 2031행에 상품정보 실어 GROUP BY | **집계-후-조인 재작성**: reviews 먼저 집계+HAVING(12개)→살아남은 12개만 조인 | **1.94→0.79ms (~59%↓)** |
| **Q09** | 쿠폰 사용/미사용 AOV 비교 | order_items⋈orders(14,522행) 위 `COUNT(DISTINCT)`용 Sort(1030kB, ~9ms) | **매출/건수 분리**(Q02 패턴): 매출=조인 후 2그룹 SUM, 주문수=orders 단독 COUNT → DISTINCT·Sort 소멸 | **16.04→6.95ms (~57%↓)** |
| **Q10** | 상위 1% 고객 최근 60일 매출 | `customer_total` 대전집계(order_items 18,700⋈orders→2,246고객)로 상위1% 판별 (~9.7ms) | **MV 재사용**: 랭킹을 `mv_customer_rev.monetary`로 대체, 60일 매출만 실데이터 조인 | **14.33→7.06ms (~51%↓)** |
| **Q11** | 안전 나눗셈 평균 | 리뷰 0건 상품 479개 → 0/0 division by zero (수동 평균) | **함수 선택**: sql `safe_div`는 인라인(=NULLIF 동일 1.28ms), plpgsql `f_safe_div`는 미인라인 2.87ms → safe_div 채택 | **4.10→1.28ms (~69%↓)** |

## 인덱스 추가/개선

스크립트: `tuning/indexes.sql`

| 문항 | 인덱스 | 결과 |
|---|---|---|
| **Q02** | `idx_orders_rev_ts` = `orders(order_ts) WHERE status IN(3)` (부분 커버링) | **적용** — 월별 주문건수 집계가 `Seq Scan`→`Index Only Scan`(Heap Fetches 0). order_ts·상태만 필요해 인덱스가 쿼리를 완전 커버 → 힙·필터 생략. 4.69→2.07ms. 단 Index-Only 이득은 VACUUM 최신에 의존 |
| Q01 | 동일 인덱스 후보 검토 | **미적용** — Q01은 `line_total`(order_items 조인)이 필요해 인덱스가 커버 못 함 + 21% 선택도 → 플래너가 Seq Scan 유지. "같은 인덱스라도 쿼리가 커버돼야 탄다"는 대비 사례 |
| Q04 | `idx_mv_product_revenue_rev` = `mv_product_revenue(revenue DESC)` | **생성했으나 미사용** — RANK의 ORDER BY용이지만 MV가 600행이라 플래너가 Seq Scan+quicksort 선택. ORDER BY+인덱스 이득은 규모 의존(행 수가 커지면 Sort 제거에 기여) |
| Q07 | `idx_inventory_at_risk` = `inventory(product_id) INCLUDE(qty,reorder) WHERE qty<reorder` (부분 커버링) | **검토 후 기각** — inventory 600행이라 Seq Scan(5 buffers)이 인덱스+힙보다 저렴 → 플래너 거부, 강제 사용 시 cost 12.5→16으로 더 느림. "부분 인덱스는 대형+저선택도에서만 의미"의 대비 사례 |
| Q08 | `idx_reviews_prod_rating` = `reviews(product_id) INCLUDE(rating)` (커버링) | **검토 후 기각** — reviews 2,031행 전건 집계라 Seq Scan(21 buffers)이 Index-Only Scan보다 저렴 → 플래너 미사용. Q08은 인덱스 대신 **집계-후-조인 재작성**으로 해결 |

## Join 전략 비교·적용 (SMJ / HJ / NLJ)

Q01~Q04는 같은 **`order_items ⋈ orders`(매출상태) 등가 조인**, Q06은 **`orders ⋈ orders` self-join**.
`enable_hashjoin`/`enable_mergejoin` 스위치로 3전략을 강제 비교했다. **cost는 항상 HJ가 최소 → 플래너가 HJ 선택**.
(캡처: `captures/Q0X_joins.txt`)

| 문항 | 조인 규모 | HJ cost(선택) | SMJ cost | NLJ cost | 비고 |
|---|---|---|---|---|---|
| Q01 | items⋈orders (최근 1개월) | **651** | 1001 | 1610 | NLJ Buffers 4363(=17배) |
| Q02 | items⋈orders (전체 매출) | **685** | 1149 | 3056 | |
| Q03 | items⋈orders⋈products⋈cat (90일) | **903** | 2172 | 4417 | NLJ 실측도 최악(14.8ms) |
| Q04 | items⋈orders (누적) | **795** | 1311 | 3363 | |
| Q06 | orders⋈orders self (30일 window) | **442** | 1019 | 1607 | NLJ Buffers 5919(=41배), window는 Join Filter |
| Q07 | inventory⋈products (600×600) | **29.6** | 59.9 | 115 | NLJ Buffers 185(=15배); 소규모라 실측 wall은 NLJ 최소 |
| Q08 | reviews(2031)⋈products (before) | **67.2** | 219.5 | 130 | NLJ+Memoize Buffers 384(=13.7배); 튜닝 후엔 12행만 조인 |
| Q09 | items⋈orders (매출, before) | **649** | 1113 | 3019 | NLJ Buffers 16176(=62배); 지배 비용은 조인 위 COUNT(DISTINCT) Sort |
| Q10 | items⋈orders (고객집계, before) | **649** | 1113 | 3019 | NLJ Buffers 16168(=62배); 튜닝 후 MV로 이 조인 제거 |
| Q11 | products(600)⋈prod_rev(121) | (~0.11) | (~0.14) | (~0.10) | 소규모라 3방식 sub-0.15ms 동일권; Q11 핵심은 조인 아닌 함수 선택 |

**해석**
- **HJ가 정답**: 대형×대형 등가 조인 → 양쪽 1회 스캔 후 해시. cost 최소이자 규모 안정적.
- **NLJ의 함정**: 작고 캐시된 데이터에선 wall-clock이 빠를 때가 있으나(Q01), **Buffers가 17배**(252→4363)라 데이터↑/캐시미스 시 폭발. cost·buffers·loops로 판단해야 함.
- **SMJ**: order_items가 `idx_order_items_order`로 이미 정렬돼 있어 나쁘지 않지만, 다른 쪽 정렬 비용 탓에 HJ보다 cost 높음.

**적용 결과**: 강제 전환한 쿼리는 **없음** — 모든 문항에서 플래너의 HJ가 최적이라 유지.
더 나아가 **조인 자체를 제거하거나 줄이는** 게 최종 튜닝이 됐다 — 문항 성격별로 수단이 갈린다:
- **Q02~Q04**: MV 사전집계로 `order_items ⋈ orders` 조인을 MV 읽기로 대체(무거운 팩트 조인).
- **Q06**: `MIN() OVER (PARTITION BY customer_id)` 재작성으로 self-join을 **단일 스캔**으로 대체(자기참조).
- **Q08**: 집계-후-조인 재작성으로 조인 입력을 2,031행 → **12행**으로 축소(조인 대상이 집계 결과).

즉 "어떤 조인 전략이냐"를 넘어 **"조인을 없애거나 줄인다"**가 핵심이고, 그 수단은 문항 성격에 맞춰 MV / window 재작성 / 집계-후-조인으로 달라진다.

## 함수·표현식 최적화 (Q11 — 안전 나눗셈)

리뷰 0건 상품 479개 → 수동 평균 `COALESCE(합,0)/COALESCE(개수,0)` 이 **0/0 → division by zero**.
안전 나눗셈 함수로 방지하는데, **어떤 함수를 쓰느냐가 곧 성능**이었다. 같은 쿼리에서 나눗셈 컬럼만 교체해 측정:

| 방식 | Execution | 인라인 |
|---|---|---|
| `ecom.safe_div` (sql) | **1.28ms** | O (플래너가 식으로 펼침) |
| 인라인 `NULLIF` | 1.28ms | — (safe_div 와 동일 = 완전 인라인 증거) |
| `ecom.f_safe_div` (plpgsql) | 2.87ms | X (행당 함수 호출, ~2.2배) |

- **sql 함수는 인라인**되어 순수 `NULLIF` 와 동일 속도(호출 오버헤드 0), **plpgsql 함수는 인라인 불가**라 행 수만큼 호출 비용이 붙는다 → 행 단위 나눗셈엔 `safe_div` 채택.
- 반환값 semantics 도 갈린다: '리뷰 없음'은 `0`(safe_div→NULL)이 아니라 **NULL(평가 없음)**이 맞고, `f_safe_div`(→0)는 '없으면 0으로 볼' 지표(매출·건수)에 적합. **속도·의미 모두 문항에 맞는 함수를 고른다.**

## MV 활용

**활용 쿼리 요약**

| MV | 활용 쿼리 | 효과 | 스크립트 |
|---|---|---|---|
| `mv_daily_gmv` | Q02 (월별 매출) | order_items 조인 대신 MV(124행) 월 롤업 → 12.16→4.69ms | 배포 스키마 + `tuning/mv_daily_gmv.sql` |
| `mv_category_daily` | Q03 (카테고리 Top10) | order_items 18,700행 조인 대신 MV(~890행) → 12.35→1.11ms | `tuning/mv_category_daily.sql` |
| `mv_product_revenue` | Q04 (제품 RANK Top20) | order_items 18,700행 조인 대신 MV(600행) → 10.76→0.55ms | `tuning/mv_product_revenue.sql` |
| `mv_customer_rev` | **Q05 (고객 RFM) + Q10 (상위1%)** | Q05: 조인+`COUNT(DISTINCT)` 제거 17.85→5.54ms / Q10: 랭킹 대전집계 대체 14.33→7.06ms | `tuning/mv_customer_rev.sql` |

- **Q02**: 매출은 MV, 건수는 orders 단독 집계로 분리(실시간 유지). orphan 주문 0건 확인 후 분리해도 결과 동일.
- **Q03**: 카테고리×일 사전집계. ⚠️ MV는 day 단위라 '최근 90일'을 `date_trunc('day', now())` 기준으로 맞춰야 원본과 일치(한낮 경계로 두면 경계일 누락).
- **Q04**: 제품 누적매출(전체 기간) 사전집계. RANK를 600행에만 적용.
- **Q05**: 고객 R/F/M 원지표 사전집계(체크리스트 user_stats 패턴). last_order_ts만 저장→경과일은 조회 시 계산(매일 최신), NTILE 등급도 조회 시 부여. 남은 비용은 NTILE 3중 정렬(전체 순위라 사전계산 불가).
- **Q10**: 같은 `mv_customer_rev`의 `monetary`로 상위 1% 랭킹(`PERCENT_RANK`)만 대체, 최근 60일 매출은 실데이터 조인 → "누가 우량인가"는 MV 스냅샷(15:00), "최근 얼마 썼나"는 항상 최신. **하나의 MV가 두 문항(Q05·Q10)을 함께 가속**하는 재사용 사례.
- 네 MV 모두 `refresh_mv_daily_gmv.sh`가 매일 15:00 `CONCURRENTLY` 갱신 (아래 전략 공통).
- **Q06은 일부러 MV를 만들지 않았다** — order_items 조인이 없어 원래 <10ms인 리포트라, self-join 제거(window 재작성)만으로 충분. MV로 0.99ms(~88%)까지도 가능하지만, 이미 빠른 질의에 5번째 MV+갱신 부담을 더할 이득이 없어 **"MV가 항상 답은 아니다"**의 판단 사례로 남겼다.

### `mv_daily_gmv` 상세

매출상태 3종만 일별 `sum(line_total)` 사전집계 → 일별 총 판매금액 리포트 가속.
현재 124행(2026-03-26~08-01), 총 GMV 4,949,295.02. (스크립트: `tuning/mv_daily_gmv.sql`, `tuning/refresh_mv_daily_gmv.sh`)

**가속 실증** (`captures/mv_daily_gmv_{before,after}.txt`)

| | 원본 조인 집계 | MV 조회 |
|---|---|---|
| 방식 | orders⋈order_items Seq Scan×2 → Hash Join → HashAggregate | 사전집계 124행 읽기 |
| Execution Time | ~12~14ms | **0.02ms (~600배)** |
| Buffers | 252 | **1** |

**언제 실행되나 (핵심)** — 조회·갱신·원본변경 3주체가 분리됨
- 리포트 **조회**(`SELECT ... FROM mv_daily_gmv`): 저장 스냅샷 읽기만, **재계산 안 함** → 빠름
- **REFRESH** 할 때만 재계산 → 오후 3시 **스케줄러가 하루 1회** 실행 (조회가 트리거하지 않음)
- 원본(orders/order_items) 변경: 수시. REFRESH 전까지 MV엔 반영 안 됨(stale)

**갱신 전략**

| 항목 | 결정 | 근거 |
|---|---|---|
| 주기 | 매일 **15:00 1회** | 과거일은 확정값(불변), 당일치만 갱신 대상 |
| 신선도 | 당일 데이터 최대 ~24h 지연 | 오후 리포팅 직전 1회 갱신으로 일관 스냅샷 |
| 방식 | `REFRESH ... CONCURRENTLY` | 갱신 중에도 조회 무차단 (전체 REFRESH는 조회 잠금) |
| 전제 | UNIQUE 인덱스 `ux_mv_daily_gmv_day` | CONCURRENTLY 필수 조건 → `tuning/mv_daily_gmv.sql`에서 추가 완료 |

**오후 3시 스케줄 (설계·문서만, 시스템 미설치)** — `pg_cron` 미설치라 OS 스케줄러 사용
- launchd(권장): `~/Library/LaunchAgents/com.skala.mv-refresh.plist`, `StartCalendarInterval` Hour=15 Minute=0 → `refresh_mv_daily_gmv.sh` 호출 후 `launchctl load`
- cron 대안: `0 15 * * * /Users/muna/Documents/skala-sql/lab4/tuning/refresh_mv_daily_gmv.sh`

> 참고: unique 인덱스 추가로 기존 non-unique `idx_mv_daily_gmv_day`는 중복 → 공간 절약 원하면 삭제 가능(배포 baseline 유지 위해 현재는 존치).
