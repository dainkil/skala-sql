-- Q15. 전체 평균 GPA 보다 높은 학생 (WHERE 절 서브쿼리)
--   목적 : 비상관(uncorrelated) 서브쿼리. 바깥 행을 참조하지 않으므로
--          한 번만 실행되고 그 결과값이 모든 행 비교에 재사용된다.
--   주의 : WHERE 절에서는 SELECT 의 별칭을 쓸 수 없다.
--          별칭은 SELECT 목록이 계산된 뒤 확정되고 WHERE 는 그 전에 평가된다.
SELECT s.student_id,
       s.name,
       s.major,
       s.gpa
  FROM lab.student s
 WHERE s.gpa > (SELECT AVG(gpa) FROM lab.student)
 ORDER BY s.gpa DESC, s.student_id
 LIMIT 5;   -- 화면 캡처용

-- 참고 : 기준값과 대상 인원 확인
SELECT ROUND((SELECT AVG(gpa) FROM lab.student), 3) AS 전체평균GPA,
       (SELECT COUNT(*) FROM lab.student
         WHERE gpa > (SELECT AVG(gpa) FROM lab.student)) AS 평균초과인원;
