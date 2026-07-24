-- Q04. FULL OUTER JOIN — 학생과 수강을 모두 포함
--   목적 : 어느 한쪽에만 있는 행까지 전부 남긴다.
--          '수강없음'(학생만 존재) 과 '학생없음'(고아 수강행) 이 동시에 보인다.
--   정렬 : 라벨 문자열이 아니라 숫자 정렬키로 정렬해야 순서가 안정적이다.
--   캡처 : 그냥 정렬 후 LIMIT 을 걸면 안 된다. 세 구분이 뭉쳐 있고
--          학생없음 2건 → 수강없음 333건 → 양쪽매칭 1,000건 순이라
--          앞 몇 건만 잘라오면 '양쪽매칭' 이 한 행도 안 나온다.
--          구분마다 ROW_NUMBER 를 매겨 2건씩 뽑으면 세 경우가 다 보인다.
SELECT 구분,
       student_id,
       name,
       enroll_student_id,
       course,
       grade
  FROM (SELECT CASE WHEN e.student_id IS NULL THEN '수강없음'
                    WHEN s.student_id IS NULL THEN '학생없음'
                    ELSE '양쪽매칭'
               END AS 구분,
               CASE WHEN s.student_id IS NULL THEN 1
                    WHEN e.student_id IS NULL THEN 2
                    ELSE 3
               END AS 정렬키,
               s.student_id,
               s.name,
               e.student_id AS enroll_student_id,
               e.course,
               e.grade,
               ROW_NUMBER() OVER (
                   PARTITION BY CASE WHEN s.student_id IS NULL THEN 1
                                     WHEN e.student_id IS NULL THEN 2
                                     ELSE 3 END
                   ORDER BY COALESCE(s.student_id, e.student_id), e.course) AS rn
          FROM lab.student s
          FULL JOIN lab.enroll e ON e.student_id = s.student_id) t
 WHERE rn <= 2   -- 구분별 2건씩 = 총 6행
 ORDER BY 정렬키, rn;
