-- Q14. 스칼라 서브쿼리(SELECT 절) — 학생에 소속 학과명 붙이기
--   목적 : SELECT 절의 서브쿼리는 행마다 실행되어 값 하나(1행 1열)를 반환한다.
--          2행 이상을 반환하면 실행 시점에 에러가 난다.
--   참고 : student.major 는 코드값(CS, EE …)만 갖고 학과 테이블이 없으므로
--          VALUES 목록을 인라인 매핑표로 사용한다.
--   비교 : 학과명은 비상관 매핑, 학과평균GPA 는 바깥 행의 major 를 참조하는
--          상관(correlated) 스칼라 서브쿼리다.
SELECT s.student_id,
       s.name,
       s.major,
       (SELECT m.major_name
          FROM (VALUES ('CS',  '컴퓨터공학과'),
                       ('EE',  '전자공학과'),
                       ('ME',  '기계공학과'),
                       ('CE',  '건설환경공학과'),
                       ('BIO', '생명과학과'),
                       ('HR',  '인적자원학과')
               ) AS m(code, major_name)
         WHERE m.code = s.major)                    AS 학과명,
       s.gpa,
       (SELECT ROUND(AVG(x.gpa), 2)
          FROM lab.student x
         WHERE x.major = s.major)                   AS 학과평균GPA
  FROM lab.student s
 ORDER BY s.student_id
 LIMIT 5;   -- 화면 캡처용
