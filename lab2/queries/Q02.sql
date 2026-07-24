-- Q02. LEFT JOIN — 모든 학생을 기준으로 수강 내역 붙이기 (없으면 NULL)
--   목적 : 왼쪽(student) 은 전부 남기고 오른쪽(enroll) 은 짝이 있을 때만 채운다.
--          수강 기록이 없는 학생은 course/grade 가 NULL 로 나온다.
--   정렬 : student_id 순으로 둔다.
--          course NULLS FIRST 로 정렬하면 미수강 학생 333명이 앞을 다 차지해
--          캡처에 NULL 행만 잡히고 조인이 실패한 것처럼 보인다.
--          student_id 순이면 매칭된 행과 NULL 행이 섞여 나와
--          "모든 학생을 남기되 짝이 없으면 NULL" 이라는 동작이 한눈에 보인다.
SELECT s.student_id,
       s.name,
       s.major,
       e.course,
       e.grade
  FROM lab.student s
  LEFT JOIN lab.enroll e ON e.student_id = s.student_id
 ORDER BY s.student_id, e.course
 LIMIT 20;   -- 화면 캡처용 (전체 1,333건 = 매칭 1,000 + 미수강 333)
