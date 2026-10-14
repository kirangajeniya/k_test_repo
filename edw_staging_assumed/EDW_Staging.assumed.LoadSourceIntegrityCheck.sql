-- Database: EDW_Staging
-- Schema: assumed
-- Procedure: LoadSourceIntegrityCheck

CREATE   PROCEDURE assumed.LoadSourceIntegrityCheck
AS
BEGIN
	BEGIN TRY
		DROP TABLE IF EXISTS #Parameters

		SELECT ClosingEndDate = DATEADD(NANOSECOND, -100, SYSDATETIME())
			,NewStartDate = SYSDATETIME()
		INTO #Parameters

		-- Staging logic
		
		DROP TABLE IF EXISTS #SourceIntegrityCheck
		
		SELECT TableName = 'SRC_TIRS_DB.dbo.acct_byline'
		    ,EntryCount = COUNT(0)
			,IntegrityOk = CAST(NULL AS BIT)
		INTO #SourceIntegrityCheck
		FROM SRC_TIRS_DB.dbo.acct_byline
		UNION ALL
		SELECT TableName = 'SRC_TIRS_DB.dbo.acct_doc'
		    ,EntryCount = COUNT(0)
			,IntegrityOk = CAST(NULL AS BIT)
		FROM SRC_TIRS_DB.dbo.acct_doc
		UNION ALL
		SELECT TableName = 'SRC_TIRS_DB.dbo.claim'
		    ,EntryCount = COUNT(0)
			,IntegrityOk = CAST(NULL AS BIT)
		FROM SRC_TIRS_DB.dbo.claim
		UNION ALL
		SELECT TableName = 'SRC_TIRS_DB.dbo.claim_trans'
		    ,EntryCount = COUNT(0)
			,IntegrityOk = CAST(NULL AS BIT)
		FROM SRC_TIRS_DB.dbo.claim_trans
		UNION ALL
		SELECT TableName = 'SRC_TIRS_DB.dbo.trty_master'
		    ,EntryCount = COUNT(0)
			,IntegrityOk = CAST(NULL AS BIT)
		FROM SRC_TIRS_DB.dbo.trty_master
		UNION ALL
		SELECT TableName = 'SRC_TIRS_DB.dbo.xrf_annl_stmt_line'
		    ,EntryCount = COUNT(0)
			,IntegrityOk = CAST(NULL AS BIT)
		FROM SRC_TIRS_DB.dbo.xrf_annl_stmt_line
		UNION ALL
		SELECT TableName = 'SRC_TIRS_DB.dbo.xrf_country'
			,EntryCount = COUNT(0)
			,IntegrityOk = CAST(NULL AS BIT)
		FROM SRC_TIRS_DB.dbo.xrf_country
		UNION ALL
		SELECT TableName = 'SRC_TIRS_DB.dbo.xrf_curr_cds'
		    ,EntryCount = COUNT(0)
			,IntegrityOk = CAST(NULL AS BIT)
		FROM SRC_TIRS_DB.dbo.xrf_curr_cds
		UNION ALL
		SELECT TableName = 'SRC_TIRS_DB.dbo.xrf_curr_names'
		    ,EntryCount = COUNT(0)
			,IntegrityOk = CAST(NULL AS BIT)
		FROM SRC_TIRS_DB.dbo.xrf_curr_names
		UNION ALL
		SELECT TableName = 'SRC_TIRS_DB.dbo.xrf_doc_type'
		    ,EntryCount = COUNT(0)
			,IntegrityOk = CAST(NULL AS BIT)
		FROM SRC_TIRS_DB.dbo.xrf_doc_type
		UNION ALL
		SELECT TableName = 'SRC_TIRS_DB.dbo.xrf_lob_cds'
		    ,EntryCount = COUNT(0)
			,IntegrityOk = CAST(NULL AS BIT)
		FROM SRC_TIRS_DB.dbo.xrf_lob_cds
		UNION ALL
		SELECT TableName = 'SRC_TIRS_DB.dbo.xrf_prod_accounts'
			,EntryCount = COUNT(0)
			,IntegrityOk = CAST(NULL AS BIT)
		FROM SRC_TIRS_DB.dbo.xrf_prod_accounts
		UNION ALL
		SELECT TableName = 'SRC_TIRS_DB.dbo.xrf_prod_branches'
			,EntryCount = COUNT(0)
			,IntegrityOk = CAST(NULL AS BIT)
		FROM SRC_TIRS_DB.dbo.xrf_prod_branches
		UNION ALL
		SELECT TableName = 'SRC_TIRS_DB.dbo.xrf_prod_names'
			,EntryCount = COUNT(0)
			,IntegrityOk = CAST(NULL AS BIT)
		FROM SRC_TIRS_DB.dbo.xrf_prod_names
		UNION ALL
		SELECT TableName = 'SRC_TIRS_DB.dbo.xrf_pymt_types'
		    ,EntryCount = COUNT(0)
			,IntegrityOk = CAST(NULL AS BIT)
		FROM SRC_TIRS_DB.dbo.xrf_pymt_types
		UNION ALL
		SELECT TableName = 'SRC_TIRS_DB.dbo.xrf_rpt_ofc'
		    ,EntryCount = COUNT(0)
			,IntegrityOk = CAST(NULL AS BIT)
		FROM SRC_TIRS_DB.dbo.xrf_rpt_ofc
		UNION ALL
		SELECT TableName = 'SRC_TIRS_DB.dbo.xrf_sub_dept_cds'
		    ,EntryCount = COUNT(0)
			,IntegrityOk = CAST(NULL AS BIT)
		FROM SRC_TIRS_DB.dbo.xrf_sub_dept_cds
		UNION ALL
		SELECT TableName = 'SRC_TIRS_DB.dbo.xrf_trans_cds'
		    ,EntryCount = COUNT(0)
			,IntegrityOk = CAST(NULL AS BIT)
		FROM SRC_TIRS_DB.dbo.xrf_trans_cds
		UNION ALL
		SELECT TableName = 'EDW_PREPROD.lloyds.tbl_ep_gp_llyds'
		    ,EntryCount = COUNT(0)
			,IntegrityOk = CAST(NULL AS BIT)
		FROM EDW_PREPROD.lloyds.tbl_ep_gp_llyds
		where businesstype='Assumed' AND PolicySource='Openbox'
		
		UPDATE s
		SET IntegrityOk = CASE WHEN s.EntryCount >= COALESCE(x.EntryCount, 0) THEN 1 ELSE 0 END
		FROM #SourceIntegrityCheck s
		LEFT JOIN (
			SELECT tic.TableName
				,tic.EntryCount
				,MostRecent = ROW_NUMBER() OVER (PARTITION BY tic.TableName ORDER BY tic.StartDate DESC)
			FROM assumed.SourceIntegrityCheck tic
			WHERE tic.IntegrityOk = 1
			) x
			ON x.MostRecent = 1
			AND x.TableName = s.TableName
		

		-- Loading logic
		ALTER TABLE #SourceIntegrityCheck ADD DataHash BINARY(20) NULL

		UPDATE s
		SET DataHash = HASHBYTES('SHA1', CONCAT(s.EntryCount
			, '|', s.IntegrityOk))
		FROM #SourceIntegrityCheck s

		DROP TABLE IF EXISTS #LoadOperation

		CREATE TABLE #LoadOperation
		(TableName VARCHAR(100) COLLATE DATABASE_DEFAULT NOT NULL
		,Operation CHAR(1) NOT NULL
		,UNIQUE (TableName)
		)

		INSERT INTO #LoadOperation
			(TableName
			,Operation
			)
		SELECT TableName = COALESCE(t.TableName COLLATE DATABASE_DEFAULT, s.TableName COLLATE DATABASE_DEFAULT)
			,Operation = CASE WHEN t.SourceIntegrityCheckID IS NULL THEN 'I' WHEN s.DataHash IS NULL THEN 'D' ELSE 'U' END
		FROM (
			SELECT t.*
			FROM assumed.SourceIntegrityCheck t
			WHERE t.EndDate = '31 Dec 9999'
			) t
		FULL JOIN #SourceIntegrityCheck s
			ON s.TableName = t.TableName COLLATE DATABASE_DEFAULT
		WHERE t.DataHash IS NULL
			OR s.DataHash IS NULL
			OR t.DataHash != s.DataHash

		BEGIN TRAN

		UPDATE t
		SET EndDate = p.ClosingEndDate
		FROM assumed.SourceIntegrityCheck t
		INNER JOIN #LoadOperation lo
			ON lo.TableName = t.TableName
			AND lo.Operation IN ('U', 'D')
		CROSS JOIN #Parameters p
		WHERE t.EndDate = '31 Dec 9999'

		INSERT INTO assumed.SourceIntegrityCheck
			(StartDate
			,TableName
			,EntryCount
			,IntegrityOk
			,DataHash
			)
		SELECT StartDate = p.NewStartDate
			,s.TableName
			,s.EntryCount
			,s.IntegrityOk
			,s.DataHash
		FROM #SourceIntegrityCheck s
		INNER JOIN #LoadOperation lo
			ON lo.TableName = s.TableName COLLATE DATABASE_DEFAULT
			AND lo.Operation IN ('I', 'U')
		CROSS JOIN #Parameters p

		COMMIT

		DECLARE @ProcessName VARCHAR(100) = OBJECT_SCHEMA_NAME(@@PROCID) + '.' + OBJECT_NAME(@@PROCID)
		DECLARE @RowsProcessed BIGINT = COALESCE((SELECT COUNT(0) FROM #LoadOperation WHERE Operation IN ('I', 'U', 'D')), 0)
		DECLARE @LastIdentity BIGINT = SCOPE_IDENTITY()
		DECLARE @ProcessingStarted DATETIME = (SELECT p.NewStartDate FROM #Parameters p)
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
		DECLARE @ProcessingStartedC DATETIME = (SELECT p.NewStartDate FROM #Parameters p)
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
