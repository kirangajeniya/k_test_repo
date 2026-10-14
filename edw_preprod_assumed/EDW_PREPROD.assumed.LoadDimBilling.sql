-- Database: EDW_PREPROD
-- Schema: assumed
-- Procedure: LoadDimBilling

CREATE
	

 PROCEDURE [assumed].[LoadDimBilling]
AS
BEGIN
	BEGIN TRY
		DROP TABLE IF EXISTS #Parameters

		DROP TABLE IF EXISTS #DimBilling;

		SELECT ClosingValidTo = DATEADD(NANOSECOND, - 100, SYSDATETIME())
			,NewValidFrom = SYSDATETIME()
		INTO #Parameters

		DROP TABLE IF EXISTS #TIRSBillingCompany

		SELECT DISTINCT bill_company_cd = tm.bill_co_br_key
		INTO #TIRSBillingCompany
		FROM SRC_TIRS_DB.dbo.acct_doc ad
		INNER JOIN SRC_TIRS_DB.dbo.trty_master tm
			ON tm.trty_key = ad.trty_key
		UNION
		SELECT DISTINCT bill_company_cd = brkr_br_key
		FROM SRC_TIRS_DB.dbo.acct_doc ad
		INNER JOIN SRC_TIRS_DB.dbo.trty_participant tp
			ON tp.trty_key = ad.ceded_trty_key

		-- Staging logic
		SELECT *
		INTO #DimBilling
		FROM (
			-- TIRS data
			SELECT BILL_COMPANY_CD = CAST(tbc.bill_company_cd AS varchar(10))
				,BILL_COMPANY_NAME = COALESCE(tubc.BILL_COMPANY_NAME, xpn.full_nm, 'Uncoded')
				,BILL_ADDR_1 = COALESCE(tubc.BILL_ADDR_1, NULLIF(xpb.addr_1, ''), 'Uncoded')
				,BILL_ADDR_2 = COALESCE(tubc.BILL_ADDR_2, NULLIF(xpb.addr_2, ''), 'Uncoded')
				,BILL_ADDR_3 = COALESCE(tubc.BILL_ADDR_3, NULLIF(xpb.addr_3, ''), 'Uncoded')
				,BILL_CITY = COALESCE(tubc.BILL_CITY, NULLIF(xpb.city, ''), 'Uncoded')
				,BILL_NAIC = COALESCE(tubc.BILL_NAIC, NULLIF(xpn.naic_no, ''), '-9999')
				,BILL_PARENT_KEY = COALESCE(tubc.BILL_PARENT_KEY, xpn.parent_key, -9999)
				,BILL_PROD_KEY = COALESCE(tubc.BILL_PROD_KEY, xpn.prod_key, -9999)
				,BILL_PROD_NBR = COALESCE(tubc.BILL_PROD_NBR, NULLIF(xpn.prod_no, ''), '-9999')
				,BILL_STATUS_FLG = COALESCE(tubc.BILL_STATUS_FLG, xpb.status_flg, '')
				,BILL_TAX_ID = COALESCE(tubc.BILL_TAX_ID, NULLIF(xpn.tax_id, ''), '-9999')
				,BILL_PHONE = COALESCE(tubc.BILL_PHONE, NULLIF(xpb.telephone, ''), '-9999')
				,BILL_ZIP = COALESCE(tubc.BILL_ZIP, NULLIF(xpb.zip_cd, ''), '-9999')
				,BILL_COUNTRY = COALESCE(tubc.BILL_COUNTRY, xc.desc_txt, 'Uncoded')
				,ISNULL(NULLIF(LTRIM(RTRIM(tubc.BILL_STATE)), ''), 'NA') AS BILL_STATE
				,4 AS SourceSysKey
				,SourceCreatedDate = COALESCE(db.SourceCreatedDate, xpb.touch_dt)
			FROM #TIRSBillingCompany tbc
			LEFT JOIN SRC_TIRS_DB.SSIS.vw_TIRS_UW_BillingCompany tubc
				ON tubc.BILL_COMPANY_CD = tbc.bill_company_cd
			LEFT JOIN (
				SRC_TIRS_DB.dbo.xrf_prod_branches xpb
				INNER JOIN SRC_TIRS_DB.dbo.xrf_prod_names xpn
					ON xpn.prod_key = xpb.prod_key
				INNER JOIN SRC_TIRS_DB.dbo.xrf_country xc
					ON xc.country_cd = xpb.country_cd
				)
				ON xpb.prod_br_key = tbc.bill_company_cd
			LEFT JOIN assumed.DimBilling db
				ON db.BILL_COMPANY_CD = tbc.bill_company_cd
					AND db.EndDate = '9999-12-31'
					AND db.SourceSysKey = 4
			
			UNION
			
			--OPENBOX DATA
			SELECT BILL_COMPANY_CD
				,BILL_COMPANY_NAME
				,BILL_ADDR_1
				,BILL_ADDR_2
				,BILL_ADDR_3
				,BILL_CITY
				,BILL_NAIC
				,BILL_PARENT_KEY
				,BILL_PROD_KEY
				,BILL_PROD_NBR
				,BILL_STATUS_FLG
				,BILL_TAX_ID
				,BILL_PHONE
				,BILL_ZIP
				,BILL_COUNTRY
				,BILL_STATE
				,SourceSysKey
				,SourceCreatedDate = NULL
			FROM (
				SELECT MC.BILL_COMPANY_CD COLLATE DATABASE_DEFAULT AS BILL_COMPANY_CD
					,MC.BILL_COMPANY_NAME COLLATE DATABASE_DEFAULT AS BILL_COMPANY_NAME
					,MC.BILL_ADDR_1 COLLATE DATABASE_DEFAULT AS BILL_ADDR_1
					,MC.BILL_ADDR_2 COLLATE DATABASE_DEFAULT AS BILL_ADDR_2
					,MC.BILL_ADDR_3 COLLATE DATABASE_DEFAULT AS BILL_ADDR_3
					,MC.BILL_CITY COLLATE DATABASE_DEFAULT AS BILL_CITY
					,MC.BILL_NAIC COLLATE DATABASE_DEFAULT AS BILL_NAIC
					,MC.BILL_PARENT_KEY COLLATE DATABASE_DEFAULT AS BILL_PARENT_KEY
					,MC.BILL_PROD_KEY COLLATE DATABASE_DEFAULT AS BILL_PROD_KEY
					,MC.BILL_PROD_NBR COLLATE DATABASE_DEFAULT AS BILL_PROD_NBR
					,MC.BILL_STATUS_FLG COLLATE DATABASE_DEFAULT AS BILL_STATUS_FLG
					,MC.BILL_TAX_ID COLLATE DATABASE_DEFAULT AS BILL_TAX_ID
					,MC.BILL_PHONE COLLATE DATABASE_DEFAULT AS BILL_PHONE
					,MC.BILL_ZIP COLLATE DATABASE_DEFAULT AS BILL_ZIP
					,'N/A' AS BILL_COUNTRY
					,'NA' AS BILL_STATE
					,1 AS SourceSysKey
					,row_number() OVER (
						PARTITION BY bill_company_cd ORDER BY coalesce(insert_datetime, '1900-01-01') DESC
					) AS Latest
				FROM EDW_PREPROD.dbo.MAP_CONTRACT MC WITH (NOLOCK)
				WHERE MC.PLCY_SRC = 'openbox'
					AND END_DATE = '9999-12-31'
					AND CNTRCT_SEC = '$NOOID'
					AND MC.BILL_COMPANY_NAME <> 'Not classified at this level'
			) ob
			WHERE ob.Latest = 1
			
			UNION ALL
			
			SELECT BILL_COMPANY_CD = 'Uncoded'
				,BILL_COMPANY_NAME = 'Uncoded'
				,BILL_ADDR_1 = 'Uncoded'
				,BILL_ADDR_2 = 'Uncoded'
				,BILL_ADDR_3 = 'Uncoded'
				,BILL_CITY = 'Uncoded'
				,BILL_NAIC = 'Uncoded'
				,BILL_PARENT_KEY = '0'
				,BILL_PROD_KEY = '0'
				,BILL_PROD_NBR = 'Uncoded'
				,BILL_STATUS_FLG = 'Uncoded'
				,BILL_TAX_ID = '0'
				,BILL_PHONE = 'Uncoded'
				,BILL_ZIP = 'Uncoded'
				,BILL_COUNTRY = 'Uncoded'
				,BILL_STATE = 'Uncoded'
				,SourceSysKey = 0
				,SourceCreatedDate = NULL
			
			UNION ALL
			
			SELECT BILL_COMPANY_CD = 'N/A'
				,BILL_COMPANY_NAME = 'N/A'
				,BILL_ADDR_1 = 'N/A'
				,BILL_ADDR_2 = 'N/A'
				,BILL_ADDR_3 = 'N/A'
				,BILL_CITY = 'N/A'
				,BILL_NAIC = 'N/A'
				,BILL_PARENT_KEY = '0'
				,BILL_PROD_KEY = '0'
				,BILL_PROD_NBR = 'N/A'
				,BILL_STATUS_FLG = 'N/A'
				,BILL_TAX_ID = '0'
				,BILL_PHONE = 'N/A'
				,BILL_ZIP = 'N/A'
				,BILL_COUNTRY = 'N/A'
				,BILL_STATE = 'N/A'
				,SourceSysKey = 0
				,SourceCreatedDate = NULL
		) Billing

		-- Loading logic
		ALTER TABLE #DimBilling ADD DataHash BINARY (20) NULL;

		ALTER TABLE #DimBilling ADD DataHashType1 BINARY (20) NULL;

		UPDATE s
		SET DataHash = HASHBYTES('SHA1', CONCAT_WS (
					'|'
					,BILL_COMPANY_NAME
					,s.BILL_ADDR_1
					,s.BILL_ADDR_2
					,s.BILL_ADDR_3
					,s.BILL_CITY
					,s.BILL_NAIC
					,s.BILL_PARENT_KEY
					,s.BILL_PROD_KEY
					,s.BILL_STATUS_FLG
					,s.BILL_TAX_ID
					,s.BILL_PHONE
					,s.BILL_ZIP
					,s.BILL_PROD_NBR
					,s.BILL_COUNTRY
					,s.BILL_STATE
				))
			,DataHashType1 = HASHBYTES('SHA1', CONCAT (
					''
					,SourceCreatedDate
				))
		FROM #DimBilling s

		DROP TABLE IF EXISTS #LoadOperation

		CREATE TABLE #LoadOperation (
			BILL_COMPANY_CD VARCHAR(200) COLLATE DATABASE_DEFAULT NULL
			,SourceSysKey SMALLINT NULL
			,Operation CHAR(1) NOT NULL
			,UNIQUE (
				BILL_COMPANY_CD
				,SourceSysKey
			)
		)

		INSERT INTO #LoadOperation (
			BILL_COMPANY_CD
			,SourceSysKey
			,Operation
		)
		SELECT BILL_COMPANY_CD = COALESCE(t.BILL_COMPANY_CD COLLATE DATABASE_DEFAULT, s.BILL_COMPANY_CD COLLATE DATABASE_DEFAULT)
			,SourceSysKey = COALESCE(t.SourceSysKey, s.SourceSysKey)
			,Operation = CASE WHEN t.DimBillingID IS NULL THEN 'I' WHEN s.DataHash IS NULL THEN 'D' WHEN t.DataHash != s.DataHash
					AND t.DataHashType1 != s.DataHashType1 THEN 'U' WHEN t.DataHash != s.DataHash THEN '2' ELSE '1' END
		FROM (
			SELECT t.*
			FROM assumed.DimBilling t
			WHERE t.EndDate = '31 Dec 9999'
		) t
		FULL JOIN #DimBilling s
			ON COALESCE(s.BILL_COMPANY_CD, '^&*') = COALESCE(t.BILL_COMPANY_CD, '^&*') COLLATE DATABASE_DEFAULT
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
		FROM assumed.DimBilling t
		INNER JOIN #LoadOperation lo
			ON COALESCE(lo.BILL_COMPANY_CD, '^&*') = COALESCE(t.BILL_COMPANY_CD, '^&*')
				AND COALESCE(lo.SourceSysKey, - 1) = COALESCE(t.SourceSysKey, - 1)
				AND lo.Operation IN ('U', '1')
		INNER JOIN #DimBilling s
			ON COALESCE(s.BILL_COMPANY_CD, '^&*') = COALESCE(t.BILL_COMPANY_CD, '^&*')
				AND COALESCE(s.SourceSysKey, - 1) = COALESCE(t.SourceSysKey, - 1)
		CROSS JOIN #Parameters p
		WHERE p.NewValidFrom BETWEEN t.StartDate
				AND t.EndDate

		-- Type2 Update
		UPDATE t
		SET EndDate = p.ClosingValidTo
		FROM assumed.DimBilling t
		INNER JOIN #LoadOperation lo
			ON COALESCE(lo.BILL_COMPANY_CD, '^&*') = COALESCE(t.BILL_COMPANY_CD, '^&*')
				AND COALESCE(lo.SourceSysKey, - 1) = COALESCE(t.SourceSysKey, - 1)
				AND lo.Operation IN ('U', '2')
		CROSS JOIN #Parameters p
		WHERE t.EndDate = '31 Dec 9999'

		INSERT INTO assumed.DimBilling (
			[StartDate]
			,[BILL_COMPANY_CD]
			,[BILL_ADDR_1]
			,[BILL_ADDR_2]
			,[BILL_ADDR_3]
			,[BILL_CITY]
			,[BILL_COMPANY_NAME]
			,[BILL_NAIC]
			,[BILL_PARENT_KEY]
			,[BILL_PROD_KEY]
			,[BILL_STATUS_FLG]
			,[BILL_TAX_ID]
			,[BILL_PHONE]
			,[BILL_ZIP]
			,[BILL_PROD_NBR]
			,[BILL_COUNTRY]
			,[BILL_STATE]
			,[SourceSysKey]
			,[DataHash]
			,[SourceCreatedDate]
			,[UpdateDate]
			,[DataHashType1]
		)
		SELECT StartDate = p.NewValidFrom
			,s.[BILL_COMPANY_CD]
			,s.[BILL_ADDR_1]
			,s.[BILL_ADDR_2]
			,s.[BILL_ADDR_3]
			,s.[BILL_CITY]
			,s.[BILL_COMPANY_NAME]
			,s.[BILL_NAIC]
			,s.[BILL_PARENT_KEY]
			,s.[BILL_PROD_KEY]
			,s.[BILL_STATUS_FLG]
			,s.[BILL_TAX_ID]
			,s.[BILL_PHONE]
			,s.[BILL_ZIP]
			,s.[BILL_PROD_NBR]
			,s.[BILL_COUNTRY]
			,s.[BILL_STATE]
			,s.[SourceSysKey]
			,s.[DataHash]
			,s.[SourceCreatedDate]
			,[UpdateDate] = p.NewValidFrom
			,s.[DataHashType1]
		FROM #DimBilling s
		INNER JOIN #LoadOperation lo
			ON COALESCE(lo.BILL_COMPANY_CD, '^&*') = COALESCE(s.BILL_COMPANY_CD, '^&*') COLLATE DATABASE_DEFAULT
				AND COALESCE(lo.SourceSysKey, - 1) = COALESCE(s.SourceSysKey, - 1)
				AND lo.Operation IN ('I', 'U', '2')
		CROSS JOIN #Parameters p

		COMMIT

		DECLARE @ProcessName VARCHAR(100) = OBJECT_SCHEMA_NAME(@@PROCID) + '.' + OBJECT_NAME(@@PROCID)
		DECLARE @RowsProcessed BIGINT = COALESCE((
					SELECT COUNT(0)
					FROM #LoadOperation
					WHERE Operation IN ('I', 'U')
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
