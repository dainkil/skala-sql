-- Q01. 학생·수강 INNER JOIN — 수강 기록이 있는 학생의 과목/성적 조회
--   목적 : INNER JOIN 은 양쪽 테이블에 짝이 모두 있는 행만 남긴다.
--          수강하지 않은 학생, 학생에 없는 수강행은 결과에서 사라진다.
SELECT s.student_id,
       s.name,
       s.major,
       e.course,
       e.grade
  FROM lab.student s
  JOIN lab.enroll  e ON e.student_id = s.student_id
 ORDER BY s.student_id, e.course
 LIMIT 5;   -- 화면 캡처용 (전체 1,000건)
