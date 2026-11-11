CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :gold_schema || '.rfm_segments_report') AS
SELECT CAST(rfm_segment AS STRING) AS rfm_segment,
       CAST(COUNT(*) AS BIGINT) AS customers,
       CAST(SUM(monetary) AS DECIMAL(38,2)) AS total_monetary,
       CAST(SUM(frequency) DIV COUNT(frequency) AS BIGINT) AS avg_frequency
FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.rfm_segments')
GROUP BY rfm_segment
ORDER BY rfm_segment;
