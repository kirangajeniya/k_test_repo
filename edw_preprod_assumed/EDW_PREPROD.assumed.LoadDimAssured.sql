-- Database: EDW_PREPROD
-- Schema: assumed
-- Procedure: LoadDimAssured

CREATE   PROCEDURE [assumed].[LoadDimAssured]
AS
BEGIN
BEGIN TRY
SET NOCOUNT ON
	DROP TABLE IF EXISTS #Parameters
	DROP TABLE IF EXISTS #DimAssured;
	
	SELECT ClosingValidTo = DATEADD(NANOSECOND, -100, SYSDATETIME())
		,NewValidFrom = SYSDATETIME()
	INTO #Parameters

	-- Staging logic
	select * into #DimAssured from
	(
	--TIRS data
	SELECT DISTINCT
	tucc.CEDNG_COMPANY_CD,
	tucc.CEDNG_COMPANY_NAME,
	tucc.CEDNG_ADDR_1,
	tucc.CEDNG_ADDR_2,
	tucc.CEDNG_ADDR_3,
	tucc.CEDNG_CITY,
	tucc.CEDNG_NAIC,
	tucc.CEDNG_PARENT_KEY,
	tucc.CEDNG_PROD_KEY,
	tucc.CEDNG_PROD_NBR,
	tucc.CEDNG_STATUS_FLG,
	tucc.CEDNG_TAX_ID,
	tucc.CEDNG_PHONE,
	tucc.CEDNG_ZIP,
	--'Ceding' AS RoleCode,
	tucc.CEDNG_COUNTRY,
	-- CEDNG_STATE is updated where it's NA for following companies TE2-105
	CASE WHEN tucc.CEDNG_STATE = 'NA' AND tucc.CEDNG_COMPANY_CD = 30202 THEN 'Sidney'
		WHEN tucc.CEDNG_STATE = 'NA' AND tucc.CEDNG_COMPANY_CD = 31223 THEN 'Queensland'
		WHEN tucc.CEDNG_STATE = 'NA' AND tucc.CEDNG_COMPANY_CD = 31224 THEN 'NEW SOUTH WALES'
		WHEN tucc.CEDNG_STATE = 'NA' AND tucc.CEDNG_COMPANY_CD = 30200 THEN 'Gaborone'
		WHEN tucc.CEDNG_STATE = 'NA' AND tucc.CEDNG_COMPANY_CD = 29853 THEN 'BRASIL'
		WHEN tucc.CEDNG_STATE = 'NA' AND tucc.CEDNG_COMPANY_CD = 29863 THEN 'BRASIL'
		WHEN tucc.CEDNG_STATE = 'NA' AND tucc.CEDNG_COMPANY_CD = 30415 THEN 'Sao Paolo'
		WHEN tucc.CEDNG_STATE = 'NA' AND tucc.CEDNG_COMPANY_CD = 31188 THEN 'GRAND CAYMAN'
		WHEN tucc.CEDNG_STATE = 'NA' AND tucc.CEDNG_COMPANY_CD = 30236 THEN 'Guernsey'
		WHEN tucc.CEDNG_STATE = 'NA' AND tucc.CEDNG_COMPANY_CD = 29941 THEN 'Shenzhen'
		WHEN tucc.CEDNG_STATE = 'NA' AND tucc.CEDNG_COMPANY_CD = 29973 THEN 'Chengdu,Sichuan'
		WHEN tucc.CEDNG_STATE = 'NA' AND tucc.CEDNG_COMPANY_CD = 30582 THEN 'D.C.'
		WHEN tucc.CEDNG_STATE = 'NA' AND tucc.CEDNG_COMPANY_CD = 31151 THEN 'SAN SALVADOR'
		WHEN tucc.CEDNG_STATE = 'NA' AND tucc.CEDNG_COMPANY_CD = 29852 THEN 'Surrey'
		WHEN tucc.CEDNG_STATE = 'NA' AND tucc.CEDNG_COMPANY_CD = 30231 THEN 'Truro'
		WHEN tucc.CEDNG_STATE = 'NA' AND tucc.CEDNG_COMPANY_CD = 23303 THEN 'Kopavogur'
		WHEN tucc.CEDNG_STATE = 'NA' AND tucc.CEDNG_COMPANY_CD = 30086 THEN 'Mumbai'
		WHEN tucc.CEDNG_STATE = 'NA' AND tucc.CEDNG_COMPANY_CD = 30041 THEN 'Tel Aviv'
		WHEN tucc.CEDNG_STATE = 'NA' AND tucc.CEDNG_COMPANY_CD = 30184 THEN 'Seoul'
		WHEN tucc.CEDNG_STATE = 'NA' AND tucc.CEDNG_COMPANY_CD = 30071 THEN 'Kuala Lumpur'
		WHEN tucc.CEDNG_STATE = 'NA' AND tucc.CEDNG_COMPANY_CD = 29882 THEN 'FEDERAL DISTRICT OF MEXICO'
		WHEN tucc.CEDNG_STATE = 'NA' AND tucc.CEDNG_COMPANY_CD = 30690 THEN 'MEXICO'
		WHEN tucc.CEDNG_STATE = 'NA' AND tucc.CEDNG_COMPANY_CD = 29936 THEN 'Auckland'
		WHEN tucc.CEDNG_STATE = 'NA' AND tucc.CEDNG_COMPANY_CD = 30172 THEN 'Hohola'
		WHEN tucc.CEDNG_STATE = 'NA' AND tucc.CEDNG_COMPANY_CD = 29947 THEN 'Metro Manila'
		WHEN tucc.CEDNG_STATE = 'NA' AND tucc.CEDNG_COMPANY_CD = 30183 THEN 'MANILA'
		WHEN tucc.CEDNG_STATE = 'NA' AND tucc.CEDNG_COMPANY_CD = 31186 THEN 'ST VINCENT'
		WHEN tucc.CEDNG_STATE = 'NA' AND tucc.CEDNG_COMPANY_CD = 30155 THEN 'Taipei City'
		WHEN tucc.CEDNG_STATE = 'NA' AND tucc.CEDNG_COMPANY_CD = 30159 THEN 'Guernsey'
		WHEN tucc.CEDNG_STATE = 'NA' AND tucc.CEDNG_COMPANY_CD = 30224 THEN 'HaNoi Vietnam'
	ELSE tucc.CEDNG_STATE
	END AS CEDNG_STATE
	,SourceCreatedDate = COALESCE(da.SourceCreatedDate, xpb.touch_dt)
	, 4 AS SourceSysKey
	FROM SRC_TIRS_DB.SSIS.vw_TIRS_UW_CedingCompany tucc
	LEFT JOIN SRC_TIRS_DB.dbo.xrf_prod_branches xpb
		ON xpb.prod_br_key = tucc.CEDNG_COMPANY_CD
	LEFT JOIN assumed.DimAssured da
		ON da.CEDNG_COMPANY_CD = tucc.CEDNG_COMPANY_CD COLLATE DATABASE_DEFAULT
	UNION

	--OPENBOX data

SELECT  distinct      
                       c.CEDNG_COMPANY_CD COLLATE DATABASE_DEFAULT as CEDNG_COMPANY_CD
					   , cast(cc.be_name as varchar) COLLATE DATABASE_DEFAULT as CEDNG_COMPANY_NAME
					   , cc.CEDNG_ADDR_1 COLLATE DATABASE_DEFAULT as CEDNG_ADDR_1
					   , cc.CEDNG_ADDR_2 COLLATE DATABASE_DEFAULT as CEDNG_ADDR_2
					   , cc.CEDNG_ADDR_3 COLLATE DATABASE_DEFAULT as CEDNG_ADDR_3
					   , cc.CEDNG_CITY COLLATE DATABASE_DEFAULT as CEDNG_CITY	
					   , cc.CEDNG_NAIC COLLATE DATABASE_DEFAULT as CEDNG_NAIC
					    , cc.CEDNG_PARENT_KEY COLLATE DATABASE_DEFAULT as CEDNG_PARENT_KEY
                      , cc.CEDNG_PROD_KEY COLLATE DATABASE_DEFAULT as CEDNG_PROD_KEY
					 , cc.CEDNG_PROD_NBR COLLATE DATABASE_DEFAULT as CEDNG_PROD_NBR
					 , cc.CEDNG_STATUS_FLG COLLATE DATABASE_DEFAULT as CEDNG_STATUS_FLG 
					  , cc.CEDNG_TAX_ID COLLATE DATABASE_DEFAULT as CEDNG_TAX_ID
		               , cc.CEDNG_PHONE COLLATE DATABASE_DEFAULT as CEDNG_PHONE
                      , cc.CEDNG_ZIP COLLATE DATABASE_DEFAULT as CEDNG_ZIP
					  , cc.CEDING_COUNTRY COLLATE DATABASE_DEFAULT  as CEDNG_COUNTRY
                      , cc.CEDING_STATE COLLATE DATABASE_DEFAULT as CEDNG_STATE
					  , NULL AS SourceCreatedDate
    				  , 1 AS SourceSysKey
FROM edw_staging.openbox.Contract c with(nolock)
  	  LEFT JOIN EDW_PREPROD.cognos.ATT_CEDNG_COMPANY cc with(nolock)
            ON c.CEDNG_COMPANY_CD = cc.CEDNG_COMPANY_CD
			and c.PLCY_SRC = 'openbox' AND cast(cc.end_date as date) ='9999-12-31'

	UNION ALL
		SELECT
	    'Uncoded' AS CEDNG_COMPANY_CD,
		'Uncoded' AS CEDNG_COMPANY_NAME,
	    'Uncoded' AS CEDNG_ADDR_1,
	    'Uncoded' AS CEDNG_ADDR_2,
	    'Uncoded' AS CEDNG_ADDR_3,
	    'Uncoded' AS CEDNG_CITY,
		'Uncoded' AS CEDNG_NAIC,
		 '0' AS CEDNG_PARENT_KEY,
	     '0' AS CEDNG_PROD_KEY,	 
	    'Uncoded' AS CEDNG_PROD_NBR,	
	     '0' AS CEDNG_STATUS_FLG,
		 '0' AS CEDNG_TAX_ID,
	    'Uncoded' AS CEDNG_PHONE,
	    'Uncoded' AS CEDNG_ZIP,
	    'Uncoded' AS CEDNG_COUNTRY,	
	    'Uncoded' AS CEDNG_STATE, 
		 NULL AS SourceCreatedDate,
	     0 AS SourceSysKey
	UNION ALL
		SELECT
	    'N/A' AS CEDNG_COMPANY_CD,
		'N/A' AS CEDNG_COMPANY_NAME,
	    'N/A' AS CEDNG_ADDR_1,
	    'N/A' AS CEDNG_ADDR_2,
	    'N/A' AS CEDNG_ADDR_3,
	    'N/A' AS CEDNG_CITY,
		'N/A' AS CEDNG_NAIC,
		 '0' AS CEDNG_PARENT_KEY,
	     '0' AS CEDNG_PROD_KEY,	 
	    'N/A' AS CEDNG_PROD_NBR,	
	     '0' AS CEDNG_STATUS_FLG,
		 '0' AS CEDNG_TAX_ID,
	    'N/A' AS CEDNG_PHONE,
	    'N/A' AS CEDNG_ZIP,
	    'N/A' AS CEDNG_COUNTRY,	
	    'N/A' AS CEDNG_STATE, 
		 NULL AS SourceCreatedDate,
	     0 AS SourceSysKey
		 )	a

		-- Loading logic
	ALTER TABLE #DimAssured ADD DataHash BINARY(20) NULL;
	ALTER TABLE #DimAssured ADD DataHashType1	BINARY(20) NULL;

	UPDATE s
	SET DataHash = HASHBYTES('SHA1', 
	concat(s.CEDNG_COMPANY_NAME
	,'|',s.CEDNG_ADDR_1
	,'|',s.CEDNG_ADDR_2
	,'|',s.CEDNG_ADDR_3
	,'|',s.CEDNG_CITY
	,'|',s.CEDNG_NAIC
	,'|',s.CEDNG_PARENT_KEY
	,'|',s.CEDNG_PROD_KEY
	,'|',s.CEDNG_PROD_NBR
	,'|',s.CEDNG_STATUS_FLG
	,'|',s.CEDNG_TAX_ID
	,'|',s.CEDNG_PHONE
	,'|',s.CEDNG_ZIP
	,'|',s.CEDNG_COUNTRY
	,'|',s.CEDNG_STATE )),
		DataHashType1= HASHBYTES('SHA1', CONCAT ('|', s.SourceCreatedDate))
	FROM #DimAssured s

	DROP TABLE IF EXISTS #LoadOperation

	CREATE TABLE #LoadOperation
	(CEDNG_COMPANY_CD VARCHAR(200) COLLATE DATABASE_DEFAULT NULL
	,SourceSysKey smallint NULL
	,Operation CHAR(1) NOT NULL
	,UNIQUE (CEDNG_COMPANY_CD,SourceSysKey)
	)

	INSERT INTO #LoadOperation
		(CEDNG_COMPANY_CD
		,SourceSysKey
		,Operation
		)
	SELECT CEDNG_COMPANY_CD = COALESCE(t.CEDNG_COMPANY_CD COLLATE DATABASE_DEFAULT, s.CEDNG_COMPANY_CD COLLATE DATABASE_DEFAULT)
		,SourceSysKey = COALESCE(t.SourceSysKey, s.SourceSysKey)
		,Operation = CASE WHEN t.DimAssuredID IS NULL THEN 'I' WHEN s.DataHash IS NULL THEN 'D' WHEN t.DataHash != s.DataHash AND t.DataHashType1 != s.DataHashType1 THEN 'U' WHEN t.DataHash != s.DataHash THEN '2' ELSE '1' END
	FROM (
		SELECT t.DimAssuredID, t.CEDNG_COMPANY_CD, t.SourceSysKey, t.DataHash,
				DataHashType1 = HASHBYTES('SHA1', CONCAT ('|', t.SourceCreatedDate))
		FROM assumed.DimAssured t
		WHERE t.EndDate = '31 Dec 9999'
		) t
	FULL JOIN #DimAssured s
		ON COALESCE(s.CEDNG_COMPANY_CD, '^&*') = COALESCE(t.CEDNG_COMPANY_CD, '^&*') COLLATE DATABASE_DEFAULT
		AND COALESCE(s.SourceSysKey, -1) = COALESCE(t.SourceSysKey, -1) 
		WHERE t.DataHash IS NULL
		OR s.DataHash IS NULL
		OR t.DataHash != s.DataHash
		OR t.DataHashType1 != s.DataHashType1

	BEGIN TRAN
	
	UPDATE t
	SET SourceCreatedDate		= s.SourceCreatedDate
		,DataHashType1			= s.DataHashType1
	FROM assumed.DimAssured t
	INNER JOIN #LoadOperation lo
		ON COALESCE(lo.CEDNG_COMPANY_CD, '^&*') = COALESCE(t.CEDNG_COMPANY_CD, '^&*') 
		AND COALESCE(lo.SourceSysKey, -1) = COALESCE(t.SourceSysKey, -1)
		AND lo.Operation IN ('U', '1')
	INNER JOIN #DimAssured s
		ON COALESCE(s.CEDNG_COMPANY_CD, '^&*') = COALESCE(t.CEDNG_COMPANY_CD, '^&*') 
		AND COALESCE(s.SourceSysKey, -1) = COALESCE(t.SourceSysKey, -1)
	CROSS JOIN #Parameters p
	WHERE p.NewValidFrom BETWEEN t.StartDate AND t.EndDate
	
	UPDATE t
	SET EndDate = p.ClosingValidTo
	FROM assumed.DimAssured t
	INNER JOIN #LoadOperation lo
		ON COALESCE(lo.CEDNG_COMPANY_CD, '^&*') = COALESCE(t.CEDNG_COMPANY_CD, '^&*')
		AND COALESCE(lo.SourceSysKey, -1) = COALESCE(t.SourceSysKey, -1) 
		AND lo.Operation = 'U'
	CROSS JOIN #Parameters p
	WHERE t.EndDate = '31 Dec 9999'

	INSERT INTO assumed.DimAssured
	([StartDate]
      ,[CEDNG_COMPANY_CD]
      ,[CEDNG_ADDR_1]
      ,[CEDNG_ADDR_2]
      ,[CEDNG_ADDR_3]
      ,[CEDNG_CITY]
      ,[CEDNG_COMPANY_NAME]
      ,[CEDNG_NAIC]
      ,[CEDNG_PARENT_KEY]
      ,[CEDNG_PROD_KEY]
      ,[CEDNG_STATUS_FLG]
      ,[CEDNG_TAX_ID]
      ,[CEDNG_PHONE]
      ,[CEDNG_ZIP]
      ,[CEDNG_PROD_NBR]
      ,[CEDNG_COUNTRY]
      ,[CEDNG_STATE]
	  ,[SourceCreatedDate]
	  ,[SourceSysKey]
      ,[DataHash]
		)
	SELECT StartDate = p.NewValidFrom
	  ,s.[CEDNG_COMPANY_CD]
      ,s.[CEDNG_ADDR_1]
      ,s.[CEDNG_ADDR_2]
      ,s.[CEDNG_ADDR_3]
      ,s.[CEDNG_CITY]
      ,s.[CEDNG_COMPANY_NAME]
      ,s.[CEDNG_NAIC]
      ,s.[CEDNG_PARENT_KEY]
      ,s.[CEDNG_PROD_KEY]
      ,s.[CEDNG_STATUS_FLG]
      ,s.[CEDNG_TAX_ID]
      ,s.[CEDNG_PHONE]
      ,s.[CEDNG_ZIP]
      ,s.[CEDNG_PROD_NBR]
      ,s.[CEDNG_COUNTRY]
      ,s.[CEDNG_STATE]
	  ,s.[SourceCreatedDate]
	  ,s.[SourceSysKey]
      ,s.[DataHash]
	FROM #DimAssured s
	INNER JOIN #LoadOperation lo
		ON COALESCE(lo.CEDNG_COMPANY_CD, '^&*') = COALESCE(s.CEDNG_COMPANY_CD, '^&*') COLLATE DATABASE_DEFAULT
		AND COALESCE(lo.SourceSysKey, -1) = COALESCE(s.SourceSysKey, -1)
		AND lo.Operation IN ('I', 'U')
	CROSS JOIN #Parameters p 
	
    COMMIT

		DECLARE @ProcessName VARCHAR(100) = OBJECT_SCHEMA_NAME(@@PROCID) + '.' + OBJECT_NAME(@@PROCID)
		DECLARE @RowsProcessed BIGINT = COALESCE((SELECT COUNT(0) FROM #LoadOperation WHERE Operation IN ('I', 'U')), 0)
		DECLARE @LastIdentity BIGINT = SCOPE_IDENTITY()
		DECLARE @ProcessingStarted DATETIME = (SELECT p.NewValidFrom FROM #Parameters p)
		DECLARE @ProcessingEnded DATETIME = GETDATE()
		DECLARE @SourceDataDate DATETIME = (SELECT [sql_date] FROM ETL.dbo.[day] WHERE today = 1)

		EXEC ETL.dbo.update_etl_controller @ps_process_name = @ProcessName
			,@pn_rows_processed = @RowsProcessed
			,@pdt_data_datetime = @SourceDataDate
			,@pdt_process_start_datetime = @ProcessingStarted
			,@pdt_process_end_datetime = @ProcessingEnded
			,@pn_error_number = 0
			,@ps_comment = NULL
			,@pn_max_processed_event_id = @LastIdentity
	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > 0
		BEGIN
			ROLLBACK
		END

		DECLARE @ErrorDescription VARCHAR(8000) = CONCAT('Error: ', ERROR_NUMBER(), ' - ', ERROR_MESSAGE(), '; ', 'Occurred in procedure: ' + ERROR_PROCEDURE() + ', ', 'Line ', ERROR_LINE())
		DECLARE @ErrorNumber INT = ERROR_NUMBER()
		DECLARE @ErrorMessage VARCHAR(8000) = ERROR_MESSAGE()
		DECLARE @ErrorSeverity INT = ERROR_SEVERITY()
		DECLARE @ErrorState INT = ERROR_STATE()
		DECLARE @ProcessNameC VARCHAR(100) = OBJECT_SCHEMA_NAME(@@PROCID) + '.' + OBJECT_NAME(@@PROCID)
		DECLARE @ProcessingStartedC DATETIME = (SELECT p.NewValidFrom FROM #Parameters p)
		DECLARE @ProcessingEndedC DATETIME = GETDATE()
		DECLARE @SourceDataDateC DATETIME = (SELECT [sql_date] FROM ETL.dbo.[day] WHERE today = 1)

		EXEC ETL.dbo.update_etl_controller @ps_process_name = @ProcessNameC
			,@pn_rows_processed = 0
			,@pdt_data_datetime = @SourceDataDateC
			,@pdt_process_start_datetime = @ProcessingStartedC
			,@pdt_process_end_datetime = @ProcessingEndedC
			,@pn_error_number = @ErrorNumber
			,@ps_comment = @ErrorDescription
			,@pn_max_processed_event_id = 0

		EXEC ETL.dbo.insert_error_log @process_name = @ProcessNameC
			,@object_name = 0
			,@user_message = @ErrorDescription
			,@status = 0
			,@remedy = 'Contact EDW team'

		RAISERROR(@ErrorMessage, @ErrorSeverity, @ErrorState)
	END CATCH
END

