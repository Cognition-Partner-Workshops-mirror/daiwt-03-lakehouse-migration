WITH cases(month_number, expected) AS (
  VALUES (1, 'Q4'), (2, 'Q4'), (3, 'Q1'), (4, 'Q1'), (5, 'Q1'),
         (6, 'Q2'), (7, 'Q2'), (8, 'Q2'), (9, 'Q3'), (10, 'Q3'),
         (11, 'Q3'), (12, 'Q4'), (CAST(NULL AS INT), CAST(NULL AS STRING))
), checked AS (
  SELECT expected,
         IDENTIFIER(:catalog || '.' || :silver_schema || '.f_fiscal_qtr')(
           make_date(2025, month_number, 1)) AS actual
  FROM cases
)
SELECT CASE WHEN count(*) = 13 AND count_if(NOT (actual <=> expected)) = 0
            THEN 'PASS f_fiscal_qtr: 12 months + NULL'
            ELSE raise_error('f_fiscal_qtr semantics drift') END AS self_check
FROM checked;

WITH cases(phone, expected) AS (
  VALUES ('+1 (212) 555-0199', '12125550199'),
         ('0044.20.1234 ext 9', '00442012349'),
         ('123456', '123456'), ('', ''), (' ()-+./abc', ''),
         ('abc١۲３45', '45'), (CAST(NULL AS STRING), CAST(NULL AS STRING))
), checked AS (
  SELECT expected,
         IDENTIFIER(:catalog || '.' || :silver_schema || '.f_clean_phone')(phone) AS actual
  FROM cases
)
SELECT CASE WHEN count(*) = 7 AND count_if(NOT (actual <=> expected)) = 0
            THEN 'PASS f_clean_phone: 7 cases including NULL and empty'
            ELSE raise_error('f_clean_phone semantics drift') END AS self_check
FROM checked;
