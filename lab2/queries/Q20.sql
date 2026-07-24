-- Q20. CS 학과 학생 또는 DB 과목 수강 학생 목록 (UNION)
--   목적 : 두 결과집합을 세로로 합친다.
--          UNION 은 중복 행을 제거하고, UNION ALL 은 그대로 둔다.
--   조건 : 양쪽 SELECT 의 컬럼 개수와 타입이 서로 맞아야 한다.
--   참고 : ORDER BY 는 UNION 전체에 한 번만, 맨 끝에 붙인다.
SELECT s.student_id, s.name, s.major
  FROM lab.student s
 WHERE s.major = 'CS'
UNION
SELECT s.student_id, s.name, s.major
  FROM lab.student s
  JOIN lab.enroll e ON e.student_id = s.student_id
 WHERE e.course = 'DB'
 ORDER BY student_id
 LIMIT 5;   -- 화면 캡처용

-- 참고 : UNION 과 UNION ALL 의 건수 차이 = 중복 제거된 행 수
--        (CS 학과이면서 DB 를 수강한 학생, 그리고 DB 를 여러 번 수강한 행)
SELECT (SELECT COUNT(*) FROM (
          SELECT student_id FROM lab.student WHERE major='CS'
          UNION
          SELECT s.student_id FROM lab.student s
            JOIN lab.enroll e ON e.student_id=s.student_id WHERE e.course='DB') u)  AS UNION_건수,
       (SELECT COUNT(*) FROM (
          SELECT student_id FROM lab.student WHERE major='CS'
          UNION ALL
          SELECT s.student_id FROM lab.student s
            JOIN lab.enroll e ON e.student_id=s.student_id WHERE e.course='DB') a)  AS UNION_ALL_건수;
