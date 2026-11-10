CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.payment_mix')
USING DELTA
AS
SELECT NVL(p.method, 'unknown')                                                AS method,
       DECODE(NVL(p.method, 'unknown'),
              'card',      'CARD',
              'cash',      'CASH',
              'wallet',    'DIGITAL',
              'gift_card', 'DIGITAL',
              'OTHER')                                                         AS method_family,
       NVL2(p.method, 'captured', 'missing')                                   AS method_status,
       CAST(COUNT(*) AS BIGINT)                                                AS payment_count,
       CAST(SUM(p.amount) AS DECIMAL(38,2))                                    AS amount_total,
       CAST(FLOOR(SUM(p.amount) / SUM(SUM(p.amount)) OVER (), 4) AS DECIMAL(38,4)) AS amount_share
FROM   IDENTIFIER(:catalog || '.' || :silver_schema || '.payments') p
GROUP  BY p.method;
