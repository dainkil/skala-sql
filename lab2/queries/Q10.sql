-- Q10. 모든 학생 기준 수강 과목 분포 (LEFT JOIN + 집계)
--   목적 : 학생 전원을 모집단으로 두고 수강 과목 수를 센다.
--          INNER JOIN 으로 집계하면 미수강 학생이 모집단에서 빠져
--          "0과목" 이라는 정보 자체가 사라진다.
--   주의 : COUNT(*) 가 아니라 COUNT(e.course) 를 써야 한다.
--          LEFT JOIN 으로 붙은 빈 행도 COUNT(*) 는 1로 세기 때문이다.

-- (1) 수강 과목 수별 학생 수 분포 — 0과목 구간이 나오는지 확인
SELECT 수강과목수,
       COUNT(*) AS 학생수
  FROM (SELECT s.student_id,
               COUNT(e.course) AS 수강과목수
          FROM lab.student s
          LEFT JOIN lab.enroll e ON e.student_id = s.student_id
         GROUP BY s.student_id) t
 GROUP BY 수강과목수
 ORDER BY 수강과목수;

-- (2) 학생별 수강 과목 수 + 과목 목록 (STRING_AGG)
--   STRING_AGG(값, 구분자) 로 그룹 안의 여러 행을 문자열 하나로 합친다.
--   "몇 과목인지" 뿐 아니라 "어떤 과목인지" 까지 한 행에 담긴다.
--   ORDER BY 를 집계 함수 안에 넣어야 이어붙는 순서가 고정된다.
--   COUNT 와 마찬가지로 STRING_AGG 도 NULL 은 건너뛰므로,
--   미수강 학생은 빈 문자열이 아니라 NULL 이 되어 COALESCE 로 표시를 채운다.
SELECT s.student_id,
       s.name,
       s.major,
       COUNT(e.course) AS 수강과목수,
       COALESCE(STRING_AGG(e.course, ', ' ORDER BY e.course), '(수강 없음)') AS 수강과목목록
  FROM lab.student s
  LEFT JOIN lab.enroll e ON e.student_id = s.student_id
 GROUP BY s.student_id, s.name, s.major
 ORDER BY 수강과목수 DESC, s.student_id
 LIMIT 5;   -- 화면 캡처용 (전체 1,000명)
