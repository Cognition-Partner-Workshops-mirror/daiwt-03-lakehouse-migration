CREATE OR REPLACE FUNCTION IDENTIFIER(:catalog || '.' || :silver_schema || '.f_fiscal_qtr')(d DATE)
RETURNS STRING
DETERMINISTIC
RETURN 'Q' || CAST((((month(d) + 9) % 12) DIV 3) + 1 AS STRING);

CREATE OR REPLACE FUNCTION IDENTIFIER(:catalog || '.' || :silver_schema || '.f_clean_phone')(p STRING)
RETURNS STRING
DETERMINISTIC
RETURN regexp_replace(p, '[^0-9]', '');
