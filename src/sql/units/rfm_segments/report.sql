CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.report_rfm_segments')
USING DELTA
AS
SELECT rfm_segment,
       CAST(COUNT(*) AS BIGINT)                    AS customers,
       CAST(SUM(monetary) AS DECIMAL(38,2))        AS total_monetary,
       CAST(SUM(frequency) DIV COUNT(frequency) AS BIGINT) AS avg_frequency
FROM   IDENTIFIER(:catalog || '.' || :gold_schema || '.rfm_segments')
GROUP  BY rfm_segment;
