-- Q05. 한 번도 수강하지 않은 학생 목록
--   목적 : LEFT JOIN 후 오른쪽이 NULL 인 행만 남기는 anti-join 패턴.
--          짝을 찾지 못한 행은 오른쪽 컬럼이 전부 NULL 이 되므로
--          "짝이 없다" 는 조건을 IS NULL 로 표현할 수 있다.
--   주의 : NULL 판별이므로 e.student_id = NULL 이 아니라 IS NULL 을 쓴다.
SELECT s.student_id,
       s.name,
       s.major,
       s.gpa
  FROM lab.student s
  LEFT JOIN lab.enroll e ON e.student_id = s.student_id
 WHERE e.student_id IS NULL
 ORDER BY s.student_id
 LIMIT 5;   -- 화면 캡처용
