-- Q06. 한 과목 이상 수강한 학생 목록 (중복 제거)
--   목적 : 조인 결과는 학생당 수강 건수만큼 행이 늘어난다.
--          학생 목록만 필요하므로 DISTINCT 로 중복을 제거한다.
SELECT DISTINCT s.student_id,
       s.name,
       s.major
  FROM lab.student s
  JOIN lab.enroll  e ON e.student_id = s.student_id
 ORDER BY s.student_id
 LIMIT 5;   -- 화면 캡처용
