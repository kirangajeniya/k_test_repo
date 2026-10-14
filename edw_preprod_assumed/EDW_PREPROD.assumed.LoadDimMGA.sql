-- Database: EDW_PREPROD
-- Schema: assumed
-- Procedure: LoadDimMGA

CREATE
	

 PROCEDURE [assumed].[LoadDimMGA]
AS
BEGIN
	BEGIN TRY
		SET NOCOUNT ON

		DROP TABLE IF EXISTS #Parameters

		DROP TABLE IF EXISTS #DimMGA;

		SELECT ClosingValidTo = DATEADD(NANOSECOND, - 100, SYSDATETIME())
			,NewValidFrom = SYSDATETIME()
		INTO #Parameters

		-- Staging logic
		SELECT tumc.MGA_COMPANY_CD
			,tumc.MGA_COMPANY_NAME
			,tumc.MGA_ADDR_1
			,tumc.MGA_ADDR_2
			,tumc.MGA_ADDR_3
			,tumc.MGA_CITY
			,tumc.MGA_NAIC
			,tumc.MGA_PARENT_KEY
			,tumc.MGA_PROD_KEY
			,tumc.MGA_PROD_NBR
			,tumc.MGA_STATUS_FLG
			,tumc.MGA_TAX_ID
			,tumc.MGA_PHONE
			,tumc.MGA_ZIP
			,tumc.MGA_COUNTRY
			,ISNULL(NULLIF(LTRIM(RTRIM(tumc.MGA_STATE)), ''), 'NA') AS MGA_STATE --MGA_STATE
			,4 AS SourceSysKey
			,SourceCreatedDate = COALESCE(dm.SourceCreatedDate, xpb.touch_dt)
		INTO #DimMGA
		FROM SRC_TIRS_DB.SSIS.vw_TIRS_UW_MGACompany tumc
		LEFT JOIN SRC_TIRS_DB.dbo.xrf_prod_branches xpb
			ON xpb.prod_br_key = tumc.MGA_COMPANY_CD
		LEFT JOIN assumed.DimMGA dm
			ON dm.MGA_COMPANY_CD = tumc.MGA_COMPANY_CD COLLATE DATABASE_DEFAULT
				AND dm.EndDate = '31 Dec 9999'
				AND dm.SourceSysKey = 4

		INSERT INTO #DimMGA (
			MGA_COMPANY_CD
			,MGA_COMPANY_NAME
			,MGA_ADDR_1
			,MGA_ADDR_2
			,MGA_ADDR_3
			,MGA_CITY
			,MGA_NAIC
			,MGA_PARENT_KEY
			,MGA_PROD_KEY
			,MGA_PROD_NBR
			,MGA_STATUS_FLG
			,MGA_TAX_ID
			,MGA_PHONE
			,MGA_ZIP
			,MGA_COUNTRY
			,MGA_STATE
			,SourceSysKey
			,SourceCreatedDate
		)
		VALUES
			-- Default "Uncoded" Record
			(
			'Uncoded' -- MGA_COMPANY_CD
			,'Uncoded' -- MGA_COMPANY_NAME
			,'Uncoded' -- MGA_ADDR_1
			,'Uncoded' -- MGA_ADDR_2
			,'Uncoded' -- MGA_ADDR_3
			,'Uncoded' -- MGA_CITY
			,'Uncoded' -- MGA_NAIC
			,'0' -- MGA_PARENT_KEY
			,'0' -- MGA_PROD_KEY
			,'0' -- MGA_PROD_NBR
			,'0' -- MGA_STATUS_FLG
			,'0' -- MGA_TAX_ID
			,'Uncoded' -- MGA_PHONE
			,'Uncoded' -- MGA_ZIP
			,'Uncoded' -- MGA_COUNTRY
			,'Uncoded' -- MGA_STATE
			,0 -- SourceSysKey
			,NULL -- SourceCreatedDate 
		)
			,
			-- Default "N/A" Record
			(
			'N/A' -- MGA_COMPANY_CD
			,'N/A' -- MGA_COMPANY_NAME
			,'N/A' -- MGA_ADDR_1
			,'N/A' -- MGA_ADDR_2
			,'N/A' -- MGA_ADDR_3
			,'N/A' -- MGA_CITY
			,'N/A' -- MGA_NAIC
			,'0' -- MGA_PARENT_KEY
			,'0' -- MGA_PROD_KEY
			,'0' -- MGA_PROD_NBR
			,'0' -- MGA_STATUS_FLG
			,'0' -- MGA_TAX_ID
			,'N/A' -- MGA_PHONE
			,'N/A' -- MGA_ZIP
			,'N/A' -- MGA_COUNTRY
			,'N/A' -- MGA_STATE
			,0 -- SourceSysKey
			,NULL -- SourceCreatedDate 
		);

		-- Loading logic
		ALTER TABLE #DimMGA ADD DataHash BINARY (20) NULL;

		ALTER TABLE #DimMGA ADD DataHashType1 BINARY (20) NULL;

		UPDATE s
		SET DataHash = HASHBYTES('SHA1', CONCAT_WS (
					'|'
					,s.MGA_COMPANY_NAME
					,s.MGA_ADDR_1
					,s.MGA_ADDR_2
					,s.MGA_ADDR_3
					,s.MGA_CITY
					,s.MGA_NAIC
					,s.MGA_PARENT_KEY
					,s.MGA_PROD_KEY
					,s.MGA_PROD_NBR
					,s.MGA_STATUS_FLG
					,s.MGA_TAX_ID
					,s.MGA_PHONE
					,s.MGA_ZIP
					,s.MGA_COUNTRY
					,s.MGA_STATE
				))
			,DataHashType1 = HASHBYTES('SHA1', CONCAT (
					''
					,s.SourceCreatedDate
				))
		FROM #DimMGA s

		DROP TABLE IF EXISTS #LoadOperation

		CREATE TABLE #LoadOperation (
			MGA_COMPANY_CD VARCHAR(200) COLLATE DATABASE_DEFAULT NULL
			,SourceSysKey SMALLINT NULL
			,Operation CHAR(1) NOT NULL
			,UNIQUE (
				MGA_COMPANY_CD
				,SourceSysKey
			)
		)

		INSERT INTO #LoadOperation (
			MGA_COMPANY_CD
			,SourceSysKey
			,Operation
		)
		SELECT MGA_COMPANY_CD = COALESCE(t.MGA_COMPANY_CD COLLATE DATABASE_DEFAULT, s.MGA_COMPANY_CD COLLATE DATABASE_DEFAULT)
			,SourceSysKey = COALESCE(t.SourceSysKey, s.SourceSysKey)
			,Operation = CASE WHEN t.DimMGAID IS NULL THEN 'I' WHEN s.DataHash IS NULL THEN 'D' WHEN t.DataHash != s.DataHash
					AND t.DataHashType1 != s.DataHashType1 THEN 'U' WHEN t.DataHash != s.DataHash THEN '2' ELSE '1' END
		FROM (
			SELECT t.*
			FROM assumed.DimMGA t
			WHERE t.EndDate = '31 Dec 9999'
		) t
		FULL JOIN #DimMGA s
			ON COALESCE(s.MGA_COMPANY_CD, '^&*') = COALESCE(t.MGA_COMPANY_CD, '^&*') COLLATE DATABASE_DEFAULT
				AND COALESCE(s.SourceSysKey, - 1) = COALESCE(t.SourceSysKey, - 1)
		WHERE t.DataHash IS NULL
			OR s.DataHash IS NULL
			OR t.DataHash != s.DataHash
			OR t.DataHashType1 != s.DataHashType1
			OR t.DataHashType1 IS NULL

		BEGIN TRANSACTION

		-- Type1 update
		UPDATE t
		SET SourceCreatedDate = s.SourceCreatedDate
			,DataHashType1 = s.DataHashType1
			,UpdateDate = p.NewValidFrom
		FROM assumed.DimMGA t
		INNER JOIN #LoadOperation lo
			ON COALESCE(lo.MGA_COMPANY_CD, '^&*') = COALESCE(t.MGA_COMPANY_CD, '^&*') COLLATE DATABASE_DEFAULT
				AND COALESCE(lo.SourceSysKey, - 1) = COALESCE(t.SourceSysKey, - 1)
				AND lo.Operation IN ('U', '1')
		INNER JOIN #DimMGA s
			ON COALESCE(s.MGA_COMPANY_CD, '^&*') = COALESCE(t.MGA_COMPANY_CD, '^&*') COLLATE DATABASE_DEFAULT
				AND COALESCE(s.SourceSysKey, - 1) = COALESCE(t.SourceSysKey, - 1)
		CROSS JOIN #Parameters p
		WHERE p.NewValidFrom BETWEEN t.StartDate
				AND t.EndDate

		-- Type2 update
		UPDATE t
		SET EndDate = p.ClosingValidTo
		FROM assumed.DimMGA t
		INNER JOIN #LoadOperation lo
			ON COALESCE(lo.MGA_COMPANY_CD, '^&*') = COALESCE(t.MGA_COMPANY_CD, '^&*')
				AND COALESCE(lo.SourceSysKey, - 1) = COALESCE(t.SourceSysKey, - 1)
				AND lo.Operation IN ('U', '2')
		CROSS JOIN #Parameters p
		WHERE t.EndDate = '31 Dec 9999'

		INSERT INTO assumed.DimMGA (
			[StartDate]
			,[MGA_COMPANY_CD]
			,[MGA_ADDR_1]
			,[MGA_ADDR_2]
			,[MGA_ADDR_3]
			,[MGA_CITY]
			,[MGA_COMPANY_NAME]
			,[MGA_NAIC]
			,[MGA_PARENT_KEY]
			,[MGA_PROD_KEY]
			,[MGA_STATUS_FLG]
			,[MGA_TAX_ID]
			,[MGA_PHONE]
			,[MGA_ZIP]
			,[MGA_PROD_NBR]
			,[MGA_COUNTRY]
			,[MGA_STATE]
			,[SourceSysKey]
			,[DataHash]
			,[DataHashType1]
			,[SourceCreatedDate]
			,[UpdateDate]
		)
		SELECT StartDate = p.NewValidFrom
			,s.[MGA_COMPANY_CD]
			,s.[MGA_ADDR_1]
			,s.[MGA_ADDR_2]
			,s.[MGA_ADDR_3]
			,s.[MGA_CITY]
			,s.[MGA_COMPANY_NAME]
			,s.[MGA_NAIC]
			,s.[MGA_PARENT_KEY]
			,s.[MGA_PROD_KEY]
			,s.[MGA_STATUS_FLG]
			,s.[MGA_TAX_ID]
			,s.[MGA_PHONE]
			,s.[MGA_ZIP]
			,s.[MGA_PROD_NBR]
			,s.[MGA_COUNTRY]
			,s.[MGA_STATE]
			,s.[SourceSysKey]
			,s.[DataHash]
			,s.[DataHashType1]
			,s.[SourceCreatedDate]
			,UpdateDate = p.NewValidFrom
		FROM #DimMGA s
		INNER JOIN #LoadOperation lo
			ON COALESCE(lo.MGA_COMPANY_CD, '^&*') = COALESCE(s.MGA_COMPANY_CD, '^&*') COLLATE DATABASE_DEFAULT
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
