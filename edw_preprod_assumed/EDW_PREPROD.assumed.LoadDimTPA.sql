-- Database: EDW_PREPROD
-- Schema: assumed
-- Procedure: LoadDimTPA

CREATE   PROCEDURE [assumed].[LoadDimTPA]
AS
BEGIN 
BEGIN TRY
SET NOCOUNT ON
	DROP TABLE IF EXISTS #Parameters
	DROP TABLE IF EXISTS #DimTPA;


	SELECT ClosingValidTo = DATEADD(NANOSECOND, -100, SYSDATETIME())
		,NewValidFrom = SYSDATETIME()
	INTO #Parameters

	-- Staging logic
	SELECT  
	CLM_TPA_COMPANY_CD,
	CLM_TPA_COMPANY_NAME,
	CLM_TPA_ADDR_1,
	CLM_TPA_ADDR_2,
	CLM_TPA_ADDR_3,
	CLM_TPA_CITY,
	CLM_TPA_NAIC,
	CLM_TPA_PARENT_KEY,
	CLM_TPA_PROD_KEY,
	CLM_TPA_PROD_NBR,
	CLM_TPA_STATUS_FLG,
	CLM_TPA_TAX_ID,
	CLM_TPA_PHONE,
	CLM_TPA_ZIP,
	'Claim TPA' AS RoleCode,
	CLM_TPA_COUNTRY,
	CLM_TPA_STATE
	,4 AS SourceSysKey
	INTO #DimTPA
	FROM SRC_TIRS_DB.SSIS.vw_TIRS_UW_ClaimTPACompany	


	INSERT INTO #DimTPA (
    CLM_TPA_COMPANY_CD,   
    CLM_TPA_COMPANY_NAME, 
    CLM_TPA_ADDR_1,       
    CLM_TPA_ADDR_2,       
    CLM_TPA_ADDR_3,       
    CLM_TPA_CITY,         
    CLM_TPA_NAIC,         
    CLM_TPA_PARENT_KEY,   
    CLM_TPA_PROD_KEY,     
    CLM_TPA_PROD_NBR,     
    CLM_TPA_STATUS_FLG,   
    CLM_TPA_TAX_ID,       
    CLM_TPA_PHONE,        
    CLM_TPA_ZIP,          
    RoleCode,             
    CLM_TPA_COUNTRY,      
    CLM_TPA_STATE,        
    SourceSysKey          
   )
   VALUES
   (
       'Uncoded',     -- CLM_TPA_COMPANY_CD
       'Uncoded',     -- CLM_TPA_COMPANY_NAME
       'Uncoded',     -- CLM_TPA_ADDR_1
       'Uncoded',     -- CLM_TPA_ADDR_2
       'Uncoded',     -- CLM_TPA_ADDR_3
       'Uncoded',     -- CLM_TPA_CITY
       'Uncoded',     -- CLM_TPA_NAIC
       '0',           -- CLM_TPA_PARENT_KEY
       '0',           -- CLM_TPA_PROD_KEY
       '0',           -- CLM_TPA_PROD_NBR
       '0',           -- CLM_TPA_STATUS_FLG
       '0',           -- CLM_TPA_TAX_ID
       'Uncoded',     -- CLM_TPA_PHONE
       'Uncoded',     -- CLM_TPA_ZIP
       'Claim TPA',   -- RoleCode
       'Uncoded',     -- CLM_TPA_COUNTRY
       'Uncoded',     -- CLM_TPA_STATE
       0              -- SourceSysKey
   ),
   (
       'N/A',         -- CLM_TPA_COMPANY_CD
       'N/A',         -- CLM_TPA_COMPANY_NAME
       'N/A',         -- CLM_TPA_ADDR_1
       'N/A',         -- CLM_TPA_ADDR_2
       'N/A',         -- CLM_TPA_ADDR_3
       'N/A',         -- CLM_TPA_CITY
       'N/A',         -- CLM_TPA_NAIC
       '0',           -- CLM_TPA_PARENT_KEY
       '0',           -- CLM_TPA_PROD_KEY
       '0',           -- CLM_TPA_PROD_NBR
       '0',           -- CLM_TPA_STATUS_FLG
       '0',           -- CLM_TPA_TAX_ID
       'N/A',         -- CLM_TPA_PHONE
       'N/A',         -- CLM_TPA_ZIP
       'Claim TPA',   -- RoleCode
       'N/A',         -- CLM_TPA_COUNTRY
       'N/A',         -- CLM_TPA_STATE
       0              -- SourceSysKey
   );

   --select * from #DimTPA
		-- Loading logic
	ALTER TABLE #DimTPA ADD DataHash BINARY(20) NULL;
	--select * from #DimBroker
	UPDATE s
	SET DataHash = HASHBYTES('SHA1', 
	CONCAT(CLM_TPA_COMPANY_NAME
	  ,'|',CLM_TPA_ADDR_1 
      ,'|',CLM_TPA_ADDR_2 
      ,'|',CLM_TPA_ADDR_3 
      ,'|',CLM_TPA_CITY 
      ,'|',CLM_TPA_NAIC 
      ,'|',CLM_TPA_PARENT_KEY 
      ,'|',CLM_TPA_PROD_KEY 
      ,'|',CLM_TPA_STATUS_FLG 
      ,'|',CLM_TPA_TAX_ID 
      ,'|',CLM_TPA_PHONE 
      ,'|',CLM_TPA_ZIP 
      ,'|',CLM_TPA_PROD_NBR 
      ,'|',CLM_TPA_COUNTRY 
      ,'|',CLM_TPA_STATE 
	))
	FROM #DimTPA s

	DROP TABLE IF EXISTS #LoadOperation

	CREATE TABLE #LoadOperation
	(CLM_TPA_COMPANY_CD VARCHAR(200) COLLATE DATABASE_DEFAULT NULL
	,SourceSysKey smallint NULL
	,Operation CHAR(1) NOT NULL
	,UNIQUE (CLM_TPA_COMPANY_CD,SourceSysKey)
	)

	INSERT INTO #LoadOperation
		(CLM_TPA_COMPANY_CD
		,SourceSysKey
		,Operation
		)
	SELECT CLM_TPA_COMPANY_CD = COALESCE(t.CLM_TPA_COMPANY_CD COLLATE DATABASE_DEFAULT, s.CLM_TPA_COMPANY_CD COLLATE DATABASE_DEFAULT)
			,SourceSysKey = COALESCE(t.SourceSysKey, s.SourceSysKey)
			,Operation = CASE WHEN t.DimTPAID IS NULL THEN 'I' WHEN s.DataHash IS NULL THEN 'D' ELSE 'U' END
	FROM (
		SELECT t.*
		FROM assumed.DimTPA t
		WHERE t.EndDate = '31 Dec 9999'
		) t
	FULL JOIN #DimTPA s
		ON COALESCE(s.CLM_TPA_COMPANY_CD, '^&*') = COALESCE(t.CLM_TPA_COMPANY_CD, '^&*') COLLATE DATABASE_DEFAULT
		AND COALESCE(s.SourceSysKey, -1) = COALESCE(t.SourceSysKey, -1) 
		WHERE t.DataHash IS NULL
		OR s.DataHash IS NULL
		OR t.DataHash != s.DataHash

	BEGIN TRAN

	UPDATE t
	SET EndDate = p.ClosingValidTo
	FROM assumed.DimTPA t
	INNER JOIN #LoadOperation lo
		ON COALESCE(lo.CLM_TPA_COMPANY_CD, '^&*') = COALESCE(t.CLM_TPA_COMPANY_CD, '^&*')
		AND COALESCE(lo.SourceSysKey, -1) = COALESCE(t.SourceSysKey, -1) 
		AND lo.Operation = 'U'
	CROSS JOIN #Parameters p
	WHERE t.EndDate = '31 Dec 9999'

	INSERT INTO assumed.DimTPA
	([StartDate]
      ,[CLM_TPA_COMPANY_CD]
      ,[CLM_TPA_ADDR_1]
      ,[CLM_TPA_ADDR_2]
      ,[CLM_TPA_ADDR_3]
      ,[CLM_TPA_CITY]
      ,[CLM_TPA_COMPANY_NAME]
      ,[CLM_TPA_NAIC]
      ,[CLM_TPA_PARENT_KEY]
      ,[CLM_TPA_PROD_KEY]
      ,[CLM_TPA_STATUS_FLG]
      ,[CLM_TPA_TAX_ID]
      ,[CLM_TPA_PHONE]
      ,[CLM_TPA_ZIP]
      ,[CLM_TPA_PROD_NBR]
      ,[CLM_TPA_COUNTRY]
      ,[CLM_TPA_STATE]
	  ,[SourceSysKey]
      ,[DataHash]
		)
	SELECT StartDate = p.NewValidFrom
	  ,s.[CLM_TPA_COMPANY_CD]
      ,s.[CLM_TPA_ADDR_1]
      ,s.[CLM_TPA_ADDR_2]
      ,s.[CLM_TPA_ADDR_3]
      ,s.[CLM_TPA_CITY]
      ,s.[CLM_TPA_COMPANY_NAME]
      ,s.[CLM_TPA_NAIC]
      ,s.[CLM_TPA_PARENT_KEY]
      ,s.[CLM_TPA_PROD_KEY]
      ,s.[CLM_TPA_STATUS_FLG]
      ,s.[CLM_TPA_TAX_ID]
      ,s.[CLM_TPA_PHONE]
      ,s.[CLM_TPA_ZIP]
      ,s.[CLM_TPA_PROD_NBR]
      ,s.[CLM_TPA_COUNTRY]
      ,s.[CLM_TPA_STATE]
	  ,s.[SourceSysKey]
      ,s.[DataHash]
	FROM #DimTPA s
	INNER JOIN #LoadOperation lo
		ON COALESCE(lo.CLM_TPA_COMPANY_CD, '^&*') = COALESCE(s.CLM_TPA_COMPANY_CD, '^&*') COLLATE DATABASE_DEFAULT
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

