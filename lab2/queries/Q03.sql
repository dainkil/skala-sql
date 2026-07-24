-- Q03. RIGHT JOIN — 수강 기준, 학생 정보가 없으면 NULL
--   목적 : 오른쪽(enroll) 을 전부 남긴다. student 에 없는 student_id 를 가진
--          수강행(고아행) 이 드러나므로 참조무결성 점검에 쓸 수 있다.
--   참고 : enroll.student_id 에는 FK 제약이 없어 실제로 고아행 2건이 존재한다.
--   정렬 : 학생 정보가 비어 있는 행을 맨 위로 올려 캡처에 보이게 한다.
SELECT s.student_id,
       s.name,
       s.major,
       e.student_id AS enroll_student_id,
       e.course,
       e.grade
  FROM lab.student s
 RIGHT JOIN lab.enroll e ON e.student_id = s.student_id
 ORDER BY s.student_id NULLS FIRST, e.course
 LIMIT 5;   -- 화면 캡처용 (전체 1,002건 · 고아행 2건이 최상단)
