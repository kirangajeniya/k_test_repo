-- Database: EDW_PREPROD
-- Schema: assumed
-- Procedure: LoadDimSchdlCompanyName

CREATE
	

 PROCEDURE [assumed].[LoadDimSchdlCompanyName]
AS
BEGIN
	BEGIN TRY
		DROP TABLE IF EXISTS #Parameters

		DROP TABLE IF EXISTS #DimSchdlCompanyName;

		SELECT ClosingValidTo = DATEADD(NANOSECOND, - 100, SYSDATETIME())
			,NewValidFrom = SYSDATETIME()
		INTO #Parameters

		-- Staging logic
		SELECT tusfc.SCHDL_COMPANY_CD
			,tusfc.SCHDL_COMPANY_NAME
			,tusfc.SCHDL_ADDR_1
			,tusfc.SCHDL_ADDR_2
			,tusfc.SCHDL_ADDR_3
			,tusfc.SCHDL_CITY
			,tusfc.SCHDL_NAIC
			,tusfc.SCHDL_PARENT_KEY
			,tusfc.SCHDL_PROD_KEY
			,tusfc.SCHDL_PROD_NBR
			,tusfc.SCHDL_STATUS_FLG
			,tusfc.SCHDL_TAX_ID
			,tusfc.SCHDL_PHONE
			,tusfc.SCHDL_ZIP
			,tusfc.SCHDL_COUNTRY
			,ISNULL(NULLIF(LTRIM(RTRIM(tusfc.SCHDL_STATE)), ''), 'NA') AS SCHDL_STATE
			,4 AS SourceSysKey
			,SourceCreatedDate = COALESCE(dscn.SourceCreatedDate, xpb.touch_dt)
		INTO #DimSchdlCompanyName
		FROM SRC_TIRS_DB.SSIS.vw_TIRS_UW_ScheduleFCompany tusfc
		LEFT JOIN SRC_TIRS_DB.dbo.xrf_prod_branches xpb
			ON xpb.prod_br_key = tusfc.SCHDL_COMPANY_CD
		LEFT JOIN assumed.DimSchdlCompanyName dscn
			ON dscn.SCHDL_COMPANY_CD = tusfc.SCHDL_COMPANY_CD COLLATE DATABASE_DEFAULT
				AND dscn.EndDate = '9999-12-31'
				AND dscn.SourceSysKey = 4

		INSERT INTO #DimSchdlCompanyName (
			SCHDL_COMPANY_CD
			,SCHDL_COMPANY_NAME
			,SCHDL_ADDR_1
			,SCHDL_ADDR_2
			,SCHDL_ADDR_3
			,SCHDL_CITY
			,SCHDL_NAIC
			,SCHDL_PARENT_KEY
			,SCHDL_PROD_KEY
			,SCHDL_PROD_NBR
			,SCHDL_STATUS_FLG
			,SCHDL_TAX_ID
			,SCHDL_PHONE
			,SCHDL_ZIP
			,SCHDL_COUNTRY
			,SCHDL_STATE
			,SourceSysKey
			,SourceCreatedDate
		)
		VALUES (
			'Uncoded' -- SCHDL_COMPANY_CD
			,'Uncoded' -- SCHDL_COMPANY_NAME
			,'Uncoded' -- SCHDL_ADDR_1
			,'Uncoded' -- SCHDL_ADDR_2
			,'Uncoded' -- SCHDL_ADDR_3
			,'Uncoded' -- SCHDL_CITY
			,'Uncoded' -- SCHDL_NAIC
			,'0' -- SCHDL_PARENT_KEY
			,'0' -- SCHDL_PROD_KEY
			,'0' -- SCHDL_PROD_NBR
			,'0' -- SCHDL_STATUS_FLG
			,'0' -- SCHDL_TAX_ID
			,'Uncoded' -- SCHDL_PHONE
			,'Uncoded' -- SCHDL_ZIP
			,'Uncoded' -- SCHDL_COUNTRY
			,'Uncoded' -- SCHDL_STATE
			,0 -- SourceSysKey
			,NULL -- SourceCreatedDate 
		)
			,(
			'N/A' -- SCHDL_COMPANY_CD
			,'N/A' -- SCHDL_COMPANY_NAME
			,'N/A' -- SCHDL_ADDR_1
			,'N/A' -- SCHDL_ADDR_2
			,'N/A' -- SCHDL_ADDR_3
			,'N/A' -- SCHDL_CITY
			,'N/A' -- SCHDL_NAIC
			,'0' -- SCHDL_PARENT_KEY
			,'0' -- SCHDL_PROD_KEY
			,'0' -- SCHDL_PROD_NBR
			,'0' -- SCHDL_STATUS_FLG
			,'0' -- SCHDL_TAX_ID
			,'N/A' -- SCHDL_PHONE
			,'N/A' -- SCHDL_ZIP
			,'N/A' -- SCHDL_COUNTRY
			,'N/A' -- SCHDL_STATE
			,0 -- SourceSysKey
			,NULL -- SourceCreatedDate 
		);

		-- Loading logic
		ALTER TABLE #DimSchdlCompanyName ADD DataHash BINARY (20) NULL;

		ALTER TABLE #DimSchdlCompanyName ADD DataHashType1 BINARY (20) NULL;

		--select * from #DimBroker
		UPDATE s
		SET DataHash = HASHBYTES('SHA1', CONCAT_WS ('|'
					,SCHDL_COMPANY_NAME
					,s.SCHDL_ADDR_1
					,s.SCHDL_ADDR_2
					,s.SCHDL_ADDR_3
					,s.SCHDL_CITY
					,s.SCHDL_NAIC
					,s.SCHDL_PARENT_KEY
					,s.SCHDL_PROD_KEY
					,s.SCHDL_STATUS_FLG
					,s.SCHDL_TAX_ID
					,s.SCHDL_PHONE
					,s.SCHDL_ZIP
					,s.SCHDL_PROD_NBR
					,s.SCHDL_COUNTRY
					,s.SCHDL_STATE
				))
			,DataHashType1 = HASHBYTES('SHA1', CONCAT (
					''
					,SourceCreatedDate
				))
		FROM #DimSchdlCompanyName s

		DROP TABLE IF EXISTS #LoadOperation

		CREATE TABLE #LoadOperation (
			SCHDL_COMPANY_CD VARCHAR(200) COLLATE DATABASE_DEFAULT NULL
			,SourceSysKey SMALLINT NULL
			,Operation CHAR(1) NOT NULL
			,UNIQUE (
				SCHDL_COMPANY_CD
				,SourceSysKey
			)
		)

		INSERT INTO #LoadOperation (
			SCHDL_COMPANY_CD
			,SourceSysKey
			,Operation
		)
		SELECT SCHDL_COMPANY_CD = COALESCE(t.SCHDL_COMPANY_CD COLLATE DATABASE_DEFAULT, s.SCHDL_COMPANY_CD COLLATE DATABASE_DEFAULT)
			,SourceSysKey = COALESCE(t.SourceSysKey, s.SourceSysKey)
			,Operation = CASE WHEN t.DimSchdlCompanyNameID IS NULL THEN 'I' WHEN s.DataHash IS NULL THEN 'D' WHEN t.DataHash != s.DataHash
					AND t.DataHashType1 != s.DataHashType1 THEN 'U' WHEN t.DataHash != s.DataHash THEN '2' ELSE '1' END
		FROM (
			SELECT t.*
			FROM assumed.DimSchdlCompanyName t
			WHERE t.EndDate = '31 Dec 9999'
		) t
		FULL JOIN #DimSchdlCompanyName s
			ON COALESCE(s.SCHDL_COMPANY_CD, '^&*') = COALESCE(t.SCHDL_COMPANY_CD, '^&*') COLLATE DATABASE_DEFAULT
				AND COALESCE(s.SourceSysKey, - 1) = COALESCE(t.SourceSysKey, - 1)
		WHERE t.DataHash IS NULL
			OR s.DataHash IS NULL
			OR t.DataHash != s.DataHash
			OR t.DataHashType1 != s.DataHashType1
			OR t.DataHashType1 IS NULL

		BEGIN TRANSACTION

		-- Type1
		UPDATE t
		SET SourceCreatedDate = s.SourceCreatedDate
			,DataHashType1 = s.DataHashType1
			,UpdateDate = p.NewValidFrom
		FROM assumed.DimSchdlCompanyName t
		INNER JOIN #LoadOperation lo
			ON COALESCE(lo.SCHDL_COMPANY_CD, '^&*') = COALESCE(t.SCHDL_COMPANY_CD, '^&*') COLLATE DATABASE_DEFAULT
				AND COALESCE(lo.SourceSysKey, - 1) = COALESCE(t.SourceSysKey, - 1)
				AND lo.Operation IN ('U', '1')
		INNER JOIN #DimSchdlCompanyName s
			ON COALESCE(s.SCHDL_COMPANY_CD, '^&*') = COALESCE(t.SCHDL_COMPANY_CD, '^&*') COLLATE DATABASE_DEFAULT
				AND COALESCE(s.SourceSysKey, - 1) = COALESCE(t.SourceSysKey, - 1)
		CROSS JOIN #Parameters p
		WHERE p.NewValidFrom BETWEEN t.StartDate
				AND t.EndDate

		-- Type2
		UPDATE t
		SET EndDate = p.ClosingValidTo
		FROM assumed.DimSchdlCompanyName t
		INNER JOIN #LoadOperation lo
			ON COALESCE(lo.SCHDL_COMPANY_CD, '^&*') = COALESCE(t.SCHDL_COMPANY_CD, '^&*')
				AND COALESCE(lo.SourceSysKey, - 1) = COALESCE(t.SourceSysKey, - 1)
				AND lo.Operation IN ('U', '2')
		CROSS JOIN #Parameters p
		WHERE t.EndDate = '31 Dec 9999'

		INSERT INTO assumed.DimSchdlCompanyName (
			[StartDate]
			,[SCHDL_COMPANY_CD]
			,[SCHDL_ADDR_1]
			,[SCHDL_ADDR_2]
			,[SCHDL_ADDR_3]
			,[SCHDL_CITY]
			,[SCHDL_COMPANY_NAME]
			,[SCHDL_NAIC]
			,[SCHDL_PARENT_KEY]
			,[SCHDL_PROD_KEY]
			,[SCHDL_STATUS_FLG]
			,[SCHDL_TAX_ID]
			,[SCHDL_PHONE]
			,[SCHDL_ZIP]
			,[SCHDL_PROD_NBR]
			,[SCHDL_COUNTRY]
			,[SCHDL_STATE]
			,[SourceSysKey]
			,[DataHash]
			,[DataHashType1]
			,[SourceCreatedDate]
			,[UpdateDate]
		)
		SELECT StartDate = p.NewValidFrom
			,s.[SCHDL_COMPANY_CD]
			,s.[SCHDL_ADDR_1]
			,s.[SCHDL_ADDR_2]
			,s.[SCHDL_ADDR_3]
			,s.[SCHDL_CITY]
			,s.[SCHDL_COMPANY_NAME]
			,s.[SCHDL_NAIC]
			,s.[SCHDL_PARENT_KEY]
			,s.[SCHDL_PROD_KEY]
			,s.[SCHDL_STATUS_FLG]
			,s.[SCHDL_TAX_ID]
			,s.[SCHDL_PHONE]
			,s.[SCHDL_ZIP]
			,s.[SCHDL_PROD_NBR]
			,s.[SCHDL_COUNTRY]
			,s.[SCHDL_STATE]
			,s.[SourceSysKey]
			,s.[DataHash]
			,s.[DataHashType1]
			,s.[SourceCreatedDate]
			,UpdateDate = p.NewValidFrom
		FROM #DimSchdlCompanyName s
		INNER JOIN #LoadOperation lo
			ON COALESCE(lo.SCHDL_COMPANY_CD, '^&*') = COALESCE(s.SCHDL_COMPANY_CD, '^&*') COLLATE DATABASE_DEFAULT
				AND COALESCE(lo.SourceSysKey, - 1) = COALESCE(s.SourceSysKey, - 1)
				AND lo.Operation IN ('I', 'U', '2')
		CROSS JOIN #Parameters p

		COMMIT

		DECLARE @ProcessName VARCHAR(100) = OBJECT_SCHEMA_NAME(@@PROCID) + '.' + OBJECT_NAME(@@PROCID)
		DECLARE @RowsProcessed BIGINT = COALESCE((
					SELECT COUNT(0)
					FROM #LoadOperation
					WHERE Operation IN ('I', 'U', '1', '2')
				), 0)
		DECLARE @LastIdentity BIGINT = SCOPE_IDENTITY()
		DECLARE @ProcessingStarted DATETIME = (
				SELECT p.NewValidFrom
				FROM #Parameters p
			)
		DECLARE @ProcessingEnded DATETIME = GETDATE()
		DECLARE @SourceDataDate DATETIME = (
				SELECT [sql_date]
				FROM ETL.dbo.[day]
				WHERE today = 1
			)

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

		DECLARE @ErrorDescription VARCHAR(8000) = CONCAT (
				'Error: '
				,ERROR_NUMBER()
				,' - '
				,ERROR_MESSAGE()
				,'; '
				,'Occurred in procedure: ' + ERROR_PROCEDURE() + ', '
				,'Line '
				,ERROR_LINE()
			)
		DECLARE @ErrorNumber INT = ERROR_NUMBER()
		DECLARE @ErrorMessage VARCHAR(8000) = ERROR_MESSAGE()
		DECLARE @ErrorSeverity INT = ERROR_SEVERITY()
		DECLARE @ErrorState INT = ERROR_STATE()
		DECLARE @ProcessNameC VARCHAR(100) = OBJECT_SCHEMA_NAME(@@PROCID) + '.' + OBJECT_NAME(@@PROCID)
		DECLARE @ProcessingStartedC DATETIME = (
				SELECT p.NewValidFrom
				FROM #Parameters p
			)
		DECLARE @ProcessingEndedC DATETIME = GETDATE()
		DECLARE @SourceDataDateC DATETIME = (
				SELECT [sql_date]
				FROM ETL.dbo.[day]
				WHERE today = 1
			)

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

		RAISERROR (
				@ErrorMessage
				,@ErrorSeverity
				,@ErrorState
			)
	END CATCH
END
