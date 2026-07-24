-- Q08. 총 주문금액 상위 10명과 그 금액
--   목적 : 집계 결과를 정렬해 상위 N 건만 추출한다.
--   참고 : 주문이 없는 고객은 상위권에 올 수 없으므로 INNER JOIN 으로 충분하다.
SELECT c.customer_id,
       c.customer_name,
       COUNT(o.order_id) AS 주문건수,
       SUM(o.amount)     AS 총주문금액,
       ROUND(AVG(o.amount), 2) AS 평균주문금액
  FROM lab.customers c
  JOIN lab.orders    o ON o.customer_id = c.customer_id
 GROUP BY c.customer_id, c.customer_name
 ORDER BY 총주문금액 DESC
 LIMIT 10;
