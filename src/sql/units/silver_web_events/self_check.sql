SELECT CASE WHEN :silver_bad_rows = 'true' OR count(*) = 0 THEN true
  ELSE raise_error('quarantine is not empty') END
FROM IDENTIFIER(:catalog || '.' || :silver_schema || '.web_events_quarantine');

SELECT CASE WHEN
  (SELECT count(*) FROM IDENTIFIER(:catalog || '.' || :silver_schema || '.web_events')) =
  (SELECT count(*) FROM IDENTIFIER(:catalog || '.' || :silver_schema || '.asof_web_events')(:drop))
  THEN true ELSE raise_error('asof row count mismatch') END;
