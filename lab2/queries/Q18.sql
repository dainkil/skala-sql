-- Q18. 한 번도 수강하지 않은 학생 (NOT EXISTS)
--   목적 : Q05 의 LEFT JOIN + IS NULL 과 같은 결과를 NOT EXISTS 로 표현한다.
--          두 방식은 결과가 같고 PostgreSQL 은 대개 같은 anti-join 계획을 만든다.
--   주의 : NOT IN 은 서브쿼리 결과에 NULL 이 섞이면 항상 0건이 된다.
--          NOT EXISTS 는 NULL 의 영향을 받지 않으므로 기본 선택지로 삼는다.
SELECT s.student_id,
       s.name,
       s.major,
       s.gpa
  FROM lab.student s
 WHERE NOT EXISTS (SELECT 1
                     FROM lab.enroll e
                    WHERE e.student_id = s.student_id)
 ORDER BY s.student_id
 LIMIT 5;   -- 화면 캡처용

-- 참고 : Q05(LEFT JOIN + IS NULL) 과 건수가 일치하는지 확인
SELECT (SELECT COUNT(*) FROM lab.student s
         WHERE NOT EXISTS (SELECT 1 FROM lab.enroll e
                            WHERE e.student_id = s.student_id))  AS NOT_EXISTS_건수,
       (SELECT COUNT(*) FROM lab.student s
          LEFT JOIN lab.enroll e ON e.student_id = s.student_id
         WHERE e.student_id IS NULL)                             AS LEFT_JOIN_건수;
