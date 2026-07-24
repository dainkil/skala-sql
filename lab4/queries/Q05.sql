-- =====================================================================
-- Q05. 고객 RFM 분석 (Recency / Frequency / Monetary) + NTILE 5등급   [튜닝 후: 고객 MV]
--   - Recency=마지막주문 경과일(최근5), Frequency=주문수(많으면5), Monetary=누적매출(크면5)
--   - 각 지표 NTILE(5)로 1~5 등급화
-- 실행: psql skala_db4 -v ON_ERROR_STOP=1 -f lab4/queries/Q05.sql
--
-- ---------------------------------------------------------------------
-- [튜닝 기록]  (근거: captures/Q05_before.txt, Q05_after.txt, Q05_joins.txt)
--
-- 병목(튜닝 전): order_items(18,700행) ⋈ orders → 고객별 집계
--   · COUNT(DISTINCT order_id) 위해 (customer_id, order_id) [Sort 1065kB] (최대 비용)
--   · 이어 NTILE 3개 → 정렬 3회 + 최종 정렬 1회
--   · 조인 3종: HJ cost649 < SMJ 1113 < NLJ 3429 → 플래너 HJ 선택
--   · Execution Time ≈ 17.85ms
--
-- 처방(통계 테이블 전략 = user_stats 패턴): 고객 R/F/M 원지표 사전집계 MV 사용
--   · mv_customer_rev (customer_id, last_order_ts, frequency, monetary) 2,246행
--     → tuning/mv_customer_rev.sql
--   · order_items 조인 + COUNT(DISTINCT) 대형 Sort 제거. NTILE는 조회 시 부여.
--   · Recency 경과일은 CURRENT_DATE 로 조회 시 계산 → 매일 최신 유지
--   · Execution Time ≈ 5.54ms (약 69%↓), 결과 완전 일치(mismatch 0)
--   · 남은 비용 = NTILE 3중 정렬(전체 고객 순위라 사전계산 불가, 2,246행이라 저렴)
-- ⚠️ 트레이드오프: MV는 REFRESH 전까지 stale. 갱신은 refresh_mv_daily_gmv.sh(15:00).
-- ---------------------------------------------------------------------
WITH scored AS (                -- 사전집계 MV에 NTILE(5) 등급화 (5 = 우량)
    SELECT customer_id,
           last_order_ts,
           (CURRENT_DATE - last_order_ts::date) AS recency_days,
           frequency,
           monetary,
           NTILE(5) OVER (ORDER BY last_order_ts ASC) AS r_score,  -- 최근일수록 5
           NTILE(5) OVER (ORDER BY frequency    ASC) AS f_score,   -- 많을수록 5
           NTILE(5) OVER (ORDER BY monetary     ASC) AS m_score    -- 클수록 5
    FROM ecom.mv_customer_rev
)
SELECT
    customer_id, recency_days, frequency, monetary, r_score, f_score, m_score,
    (r_score * 100 + f_score * 10 + m_score) AS rfm_cell   -- 예: 555 = 최우량
FROM scored
ORDER BY r_score DESC, f_score DESC, m_score DESC, monetary DESC;

-- [튜닝 전 · 원본 조인 버전]
-- WITH customer_rfm AS (
--     SELECT o.customer_id, MAX(o.order_ts) AS last_order_ts,
--            COUNT(DISTINCT o.order_id) AS frequency, SUM(oi.line_total) AS monetary
--     FROM ecom.orders o JOIN ecom.order_items oi ON oi.order_id = o.order_id
--     WHERE o.order_status IN ('paid','shipped','delivered')
--     GROUP BY o.customer_id),
-- scored AS (SELECT customer_id, last_order_ts, (CURRENT_DATE - last_order_ts::date) AS recency_days,
--            frequency, monetary,
--            NTILE(5) OVER (ORDER BY last_order_ts ASC) AS r_score,
--            NTILE(5) OVER (ORDER BY frequency ASC) AS f_score,
--            NTILE(5) OVER (ORDER BY monetary ASC) AS m_score FROM customer_rfm)
-- SELECT customer_id, recency_days, frequency, monetary, r_score, f_score, m_score,
--        (r_score*100+f_score*10+m_score) AS rfm_cell
-- FROM scored ORDER BY r_score DESC, f_score DESC, m_score DESC, monetary DESC;
