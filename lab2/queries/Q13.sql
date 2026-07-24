-- Q13. 학생 × 과목 전체 조합으로 과목 추천 후보 생성 (CROSS JOIN)
--   목적 : CROSS JOIN 은 조인 조건이 없어 두 집합의 데카르트 곱을 만든다.
--          학생 1,000명 × 과목 23개 = 23,000 조합이 생성된다.
--   주의 : 조인 조건을 빠뜨린 실수도 같은 결과를 내므로, 의도한 경우에만
--          CROSS JOIN 을 명시적으로 써서 실수와 구분되게 한다.
--   출력 : 이미 수강한 조합인지 표시하고 샘플 100건만 조회한다.
SELECT s.student_id,
       s.name,
       s.major,
       c.course,
       CASE WHEN EXISTS (SELECT 1
                           FROM lab.enroll e
                          WHERE e.student_id = s.student_id
                            AND e.course     = c.course)
            THEN '수강완료' ELSE '추천후보'
       END AS 상태
  FROM lab.student s
 CROSS JOIN (SELECT DISTINCT course FROM lab.enroll WHERE course IS NOT NULL) c
 ORDER BY s.student_id, c.course
 LIMIT 100;   -- 문항 요구: 샘플 100건

-- 참고 : 전체 조합 수 확인
SELECT (SELECT COUNT(*) FROM lab.student)                        AS 학생수,
       (SELECT COUNT(DISTINCT course) FROM lab.enroll)           AS 과목수,
       (SELECT COUNT(*) FROM lab.student)
     * (SELECT COUNT(DISTINCT course) FROM lab.enroll)           AS 전체조합수;
