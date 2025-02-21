CREATE OR REPLACE TEMPORARY STAGE #(stageName);

PUT file://#(filePath) @#(stageName)/file.json
    AUTO_COMPRESS = FALSE
    OVERWRITE = TRUE;

COPY INTO #(tableName) FROM @#(stageName)/file.json
    FILE_FORMAT = (TYPE = 'JSON')
    MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE;
