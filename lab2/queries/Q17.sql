-- Q17. 수강(enroll) 기록이 있는 학생만 조회 (EXISTS)
--   목적 : EXISTS 는 짝이 하나라도 있으면 참이고 즉시 탐색을 멈춘다.
--          JOIN 과 달리 행이 늘어나지 않으므로 DISTINCT 가 필요 없다.
--   참고 : SELECT 1 을 쓰는 이유 — EXISTS 는 서브쿼리가 행을 반환하는지만
--          보고 그 값은 쓰지 않는다. 컬럼을 나열해도 의미가 없다.
SELECT s.student_id,
       s.name,
       s.major,
       s.gpa
  FROM lab.student s
 WHERE EXISTS (SELECT 1
                 FROM lab.enroll e
                WHERE e.student_id = s.student_id)
 ORDER BY s.student_id
 LIMIT 5;   -- 화면 캡처용

-- 참고 : EXISTS 결과 건수 = Q06 의 DISTINCT JOIN 결과 건수
SELECT COUNT(*) AS 수강기록보유학생
  FROM lab.student s
 WHERE EXISTS (SELECT 1 FROM lab.enroll e WHERE e.student_id = s.student_id);
