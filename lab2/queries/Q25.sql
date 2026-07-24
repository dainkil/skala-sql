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
