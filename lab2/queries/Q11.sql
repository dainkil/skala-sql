-- Q11. DB 과목을 듣지 않은 모든 학생 나열
--   목적 : NOT EXISTS 를 이용한 anti-join.
--   주의 : NOT IN (SELECT student_id FROM lab.enroll WHERE course='DB') 로도
--          쓸 수 있지만, 서브쿼리 결과에 NULL 이 하나라도 섞이면
--          NOT IN 은 전체가 unknown 이 되어 결과가 0건이 된다.
--          enroll.student_id 는 NULL 허용 컬럼이므로 NOT EXISTS 가 안전하다.
SELECT s.student_id,
       s.name,
       s.major,
       s.gpa
  FROM lab.student s
 WHERE NOT EXISTS (SELECT 1
                     FROM lab.enroll e
                    WHERE e.student_id = s.student_id
                      AND e.course     = 'DB')
 ORDER BY s.student_id
 LIMIT 5;   -- 화면 캡처용

-- 검증 : 전체 학생 수 − DB 수강 학생 수 = 위 결과 건수
SELECT (SELECT COUNT(*) FROM lab.student)                              AS 전체학생,
       (SELECT COUNT(DISTINCT student_id) FROM lab.enroll
         WHERE course = 'DB')                                          AS DB수강자,
       (SELECT COUNT(*) FROM lab.student s
         WHERE NOT EXISTS (SELECT 1 FROM lab.enroll e
                            WHERE e.student_id = s.student_id
                              AND e.course = 'DB'))                    AS DB미수강자;
