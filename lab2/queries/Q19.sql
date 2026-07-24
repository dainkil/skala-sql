-- Q19. HR 학과 학생들과의 비교 데모 (ANY / ALL)
--   목적 : 다중행 서브쿼리를 비교연산자와 함께 쓰는 두 방식을 대조한다.
--          > ANY (집합)  →  집합의 최솟값보다 크면 참 ("일부보다 높다")
--          > ALL (집합)  →  집합의 최댓값보다 크면 참 ("전원보다 높다")
--   주의 : 서브쿼리가 2행 이상을 반환하는데 ANY/ALL 없이 > 만 쓰면 에러가 난다.

-- (1) HR 학과 학생 중 "일부보다" GPA 가 높은 타 학과 학생
SELECT s.student_id,
       s.name,
       s.major,
       s.gpa,
       s.gpa > ALL (SELECT h.gpa FROM lab.student h WHERE h.major = 'HR') AS HR전원보다높음
  FROM lab.student s
 WHERE s.major <> 'HR'
   AND s.gpa > ANY (SELECT h.gpa FROM lab.student h WHERE h.major = 'HR')
 ORDER BY s.gpa DESC, s.student_id
 LIMIT 5;   -- 화면 캡처용

-- (2) 기준값 확인 — ANY 는 MIN, ALL 은 MAX 와 같은 뜻이다
--     HR 최고 GPA 가 전체 최고 GPA 와 같으면 > ALL 조건은 0건이 된다.
SELECT MIN(gpa) AS HR최저GPA_ANY기준,
       MAX(gpa) AS HR최고GPA_ALL기준,
       (SELECT MAX(gpa) FROM lab.student)                       AS 전체최고GPA,
       (SELECT COUNT(*) FROM lab.student s
         WHERE s.major <> 'HR'
           AND s.gpa > ANY (SELECT gpa FROM lab.student WHERE major='HR')) AS ANY_충족인원,
       (SELECT COUNT(*) FROM lab.student s
         WHERE s.major <> 'HR'
           AND s.gpa > ALL (SELECT gpa FROM lab.student WHERE major='HR')) AS ALL_충족인원
  FROM lab.student
 WHERE major = 'HR';
