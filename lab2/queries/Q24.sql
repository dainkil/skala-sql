-- Q24. 학생별 이전 과목 대비 성적 변화 (LAG)
--   변환 : grade(A~D) 는 문자라 뺄셈이 안 되므로 CASE 로 점수화한다 (A=4 … D=1).
--   LAG  : PARTITION BY student_id 로 학생마다 창을 나누고 ORDER BY course 순서에서
--          바로 앞 행의 값을 가져온다. 첫 행은 앞이 없으므로 NULL 이다.
--   주의 : LAG 는 이미 계산된 창 안에서만 동작하므로 같은 SELECT 단계에서
--          그 결과를 다시 참조할 수 없다. 한 단계 감싸서 diff 를 계산한다.
--   범위 : score_range 는 학생 전체 창의 MAX-MIN 이라 ORDER BY 없이 PARTITION 만 준다.
WITH scored AS (
    SELECT e.student_id,
           e.course,
           CASE e.grade WHEN 'A' THEN 4
                        WHEN 'B' THEN 3
                        WHEN 'C' THEN 2
                        WHEN 'D' THEN 1
           END AS score
      FROM lab.enroll e
     WHERE e.student_id IS NOT NULL
),
windowed AS (
    SELECT student_id,
           course,
           score,
           LAG(score) OVER (PARTITION BY student_id ORDER BY course) AS prev_score,
           MAX(score) OVER (PARTITION BY student_id)
         - MIN(score) OVER (PARTITION BY student_id)                 AS score_range
      FROM scored
)
SELECT w.student_id,
       s.name,
       w.course,
       w.score,
       w.prev_score,
       w.score - w.prev_score AS diff,
       CASE WHEN w.prev_score IS NULL      THEN '첫 과목'
            WHEN w.score > w.prev_score    THEN '상승'
            WHEN w.score = w.prev_score    THEN '유지'
            ELSE                                '하락'
       END AS 변화,
       w.score_range
  FROM windowed w
  LEFT JOIN lab.student s ON s.student_id = w.student_id
 ORDER BY w.student_id, w.course
 LIMIT 5;   -- 화면 캡처용 (전체 1,002건)

-- 참고 : 변화 유형별 건수
WITH scored AS (
    SELECT student_id, course,
           CASE grade WHEN 'A' THEN 4 WHEN 'B' THEN 3
                      WHEN 'C' THEN 2 WHEN 'D' THEN 1 END AS score
      FROM lab.enroll WHERE student_id IS NOT NULL
),
windowed AS (
    SELECT student_id, score,
           LAG(score) OVER (PARTITION BY student_id ORDER BY course) AS prev_score
      FROM scored
)
SELECT CASE WHEN prev_score IS NULL   THEN '첫 과목'
            WHEN score > prev_score   THEN '상승'
            WHEN score = prev_score   THEN '유지'
            ELSE                           '하락' END AS 변화,
       COUNT(*) AS 건수
  FROM windowed
 GROUP BY 1
 ORDER BY 2 DESC;
