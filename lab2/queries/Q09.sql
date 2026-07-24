-- Q09. 모든 직원과 그 매니저 이름 (셀프 조인)
--   목적 : 같은 테이블을 두 번 참조해 계층 관계를 펼친다. 별칭이 반드시 필요하다.
--   주의 : CEO 는 manager_id 가 NULL 이라 INNER JOIN 이면 사라진다.
--          "모든 직원" 이므로 LEFT JOIN 을 쓰고 COALESCE 로 표시를 채운다.
SELECT e.emp_id,
       e.name                            AS 직원명,
       e.manager_id,
       COALESCE(m.name, '(없음 · 최상위)') AS 매니저명
  FROM lab.emp e
  LEFT JOIN lab.emp m ON m.emp_id = e.manager_id
 ORDER BY e.emp_id
 LIMIT 5;   -- 화면 캡처용 (전체 311명)
