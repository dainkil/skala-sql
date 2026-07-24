-- Q21. 학과별·GPA 구간별 인원을 소계·총계까지 한 쿼리로 (GROUP BY ROLLUP)
--   목적 : ROLLUP(major, gpa_tier) 는 아래 세 단계를 한 번에 집계한다.
--            ① (major, gpa_tier) 상세  ② (major) 학과 소계  ③ () 전체 총계
--   라벨 : 소계 행의 major/gpa_tier 는 NULL 이 된다. 원래 데이터의 NULL 과
--          구분해야 하므로 GROUPING() 함수로 판별한다(소계면 1).
--   정렬 : GPA 구간을 한글 라벨로 정렬하면 순서가 뒤섞이므로
--          숫자 tier_no 로 그룹핑·정렬하고 라벨은 표시할 때만 붙인다.
--          소계·총계 행은 GROUPING() 을 정렬 1순위로 두어 하단에 모은다.
--   비율 : 분모로 SUM(COUNT(*)) OVER () 를 쓰면 안 된다. 소계·총계 행까지
--          같이 더해져 분모가 실제 인원의 3배(3,000)가 된다.
--          모집단 전체를 세는 스칼라 서브쿼리를 분모로 쓴다.
WITH tiered AS (
    SELECT major,
           gpa,
           CASE WHEN gpa <  3.0 THEN 1
                WHEN gpa <= 3.5 THEN 2
                ELSE                 3
           END AS tier_no
      FROM lab.student
)
SELECT CASE WHEN GROUPING(major) = 1 THEN '전체' ELSE major END        AS 학과,
       CASE WHEN GROUPING(major)    = 1 THEN '총계'
            WHEN GROUPING(tier_no)  = 1 THEN '학과 소계'
            WHEN tier_no = 1 THEN '3.0 미만'
            WHEN tier_no = 2 THEN '3.0~3.5'
            ELSE                 '3.5 초과'
       END                                                             AS GPA구간,
       COUNT(*)                                                        AS 인원,
       ROUND(AVG(gpa), 2)                                              AS 평균GPA,
       ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM tiered), 1)      AS 전체대비비율
  FROM tiered
 GROUP BY ROLLUP (major, tier_no)
 ORDER BY GROUPING(major),      -- 총계 행을 맨 아래로
          major,
          GROUPING(tier_no),    -- 학과 소계를 각 학과 아래로
          tier_no;
