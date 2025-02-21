CREATE OR REPLACE TEMPORARY STAGE #(stageName);

PUT file://#(filePath) @#(stageName)/file.csv
    AUTO_COMPRESS = FALSE
    OVERWRITE = TRUE;

COPY INTO #(tableName) FROM @#(stageName)/file.csv
    FILE_FORMAT = (TYPE = 'CSV' SKIP_HEADER = 1);
