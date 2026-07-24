-- Q16. 자신의 학과 평균 GPA 보다 높은 학생 (상관 서브쿼리)
--   목적 : 서브쿼리가 바깥 행의 s.major 를 참조한다(correlated).
--          비교 기준이 행마다 달라지므로 Q15 처럼 한 번만 계산할 수 없다.
--   비교 : Q15 는 기준이 하나(전체 평균), Q16 은 기준이 학과마다 다르다.
SELECT s.student_id,
       s.name,
       s.major,
       s.gpa,
       (SELECT ROUND(AVG(x.gpa), 2)
          FROM lab.student x
         WHERE x.major = s.major) AS 학과평균GPA
  FROM lab.student s
 WHERE s.gpa > (SELECT AVG(x.gpa)
                  FROM lab.student x
                 WHERE x.major = s.major)
 ORDER BY s.major, s.gpa DESC
 LIMIT 5;   -- 화면 캡처용

-- 참고 : 학과별 평균과 초과 인원
SELECT s.major,
       COUNT(*)                                AS 학과인원,
       ROUND(AVG(s.gpa), 3)                    AS 학과평균GPA,
       COUNT(*) FILTER (WHERE s.gpa > a.avg_gpa) AS 평균초과인원
  FROM lab.student s
  JOIN (SELECT major, AVG(gpa) AS avg_gpa
          FROM lab.student GROUP BY major) a ON a.major = s.major
 GROUP BY s.major
 ORDER BY s.major;
