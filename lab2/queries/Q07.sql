-- Q07. 고객별 주문 건수와 총 주문금액
--   목적 : LEFT JOIN + GROUP BY 집계. 주문이 없는 고객도 0 으로 표시한다.
--   주의 : COUNT(*) 는 조인 후 행 수라 주문 없는 고객도 1 이 된다.
--          COUNT(o.order_id) 는 NULL 을 세지 않으므로 정확히 0 이 나온다.
--          SUM 은 대상이 없으면 NULL 이므로 COALESCE 로 0 을 채운다.
SELECT c.customer_id,
       c.customer_name,
       COUNT(o.order_id)          AS 주문건수,
       COALESCE(SUM(o.amount), 0) AS 총주문금액
  FROM lab.customers c
  LEFT JOIN lab.orders o ON o.customer_id = c.customer_id
 GROUP BY c.customer_id, c.customer_name
 ORDER BY 총주문금액 DESC, c.customer_id
 LIMIT 20;   -- 화면 캡처용 (전체 500명)
