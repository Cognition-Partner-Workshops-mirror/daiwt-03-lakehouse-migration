CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.report_rfm_segments') AS
SELECT rfm_segment,
       CAST(COUNT(*) AS BIGINT) AS customers,
       CAST(SUM(monetary) AS DECIMAL(38,2)) AS total_monetary,
       CAST(SUM(frequency) DIV NULLIF(COUNT(frequency), 0) AS BIGINT) AS avg_frequency
FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.rfm_segments')
GROUP BY rfm_segment;
