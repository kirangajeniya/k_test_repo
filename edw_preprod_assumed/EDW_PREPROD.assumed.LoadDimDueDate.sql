-- Database: EDW_PREPROD
-- Schema: assumed
-- Procedure: LoadDimDueDate


CREATE   PROCEDURE assumed.LoadDimDueDate
 AS
BEGIN
	BEGIN TRY
		DROP TABLE IF EXISTS #Parameters

		SELECT ClosingEndDate = DATEADD(NANOSECOND, -100, SYSDATETIME())
			,NewStartDate = SYSDATETIME()
		INTO #Parameters

		-- Staging logic
		
		DROP TABLE IF EXISTS #DimDueDate
		
		SELECT x.DueDate
			,DueDateMonthStart = DATEADD(DAY, 1 - DAY(x.DueDate), x.DueDate)
			,DueDateMonthEnd = EOMONTH(x.DueDate)
			,DueDateText = FORMAT(x.DueDate, 'MMM d yyyy')
			,DueDateMonthYearShort = FORMAT(x.DueDate, 'MMM yyyy')
			,DueDateMonthYearLong = FORMAT(x.DueDate, 'MMMM yyyy')
			,DueDateDay = DAY(x.DueDate)
			,DueDateMonthNumber = MONTH(x.DueDate)
			,DueDateMonthShort = FORMAT(x.DueDate, 'MMM')
			,DueDateMonthLong = FORMAT(x.DueDate, 'MMMM')
			,DueDateYear = YEAR(x.DueDate)
		INTO #DimDueDate
		FROM (
			SELECT DISTINCT DueDate = CAST(ad.due_dt AS DATE)
			FROM SRC_TIRS_DB.dbo.acct_doc ad
			WHERE ad.due_dt IS NOT NULL
			UNION
			SELECT DISTINCT DueDate = CAST(ct.entry_dt AS DATE)
			FROM SRC_TIRS_DB.dbo.claim_trans ct
			WHERE ct.entry_dt IS NOT NULL
			) x
		UNION ALL
		SELECT DueDate = NULL
			,DueDateMonthStart = NULL
			,DueDateMonthEnd = NULL
			,DueDateText = 'Uncoded'
			,DueDateMonthYearShort = 'Uncoded'
			,DueDateMonthYearLong = 'Uncoded'
			,DueDateDay = NULL
			,DueDateMonthNumber = NULL
			,DueDateMonthShort = NULL
			,DueDateMonthLong = 'Uncoded'
			,DueDateYear = NULL
		UNION ALL
		SELECT DueDate = NULL
			,DueDateMonthStart = NULL
			,DueDateMonthEnd = NULL
			,DueDateText = 'N/A'
			,DueDateMonthYearShort = 'N/A'
			,DueDateMonthYearLong = 'N/A'
			,DueDateDay = NULL
			,DueDateMonthNumber = NULL
			,DueDateMonthShort = NULL
			,DueDateMonthLong = 'N/A'
			,DueDateYear = NULL
		

		-- Loading logic
		ALTER TABLE #DimDueDate ADD DataHash BINARY(20) NULL

		UPDATE s
		SET DataHash = HASHBYTES('SHA1', CONCAT(s.DueDateMonthStart
			, '|', s.DueDateMonthEnd
			, '|', s.DueDateMonthYearShort
			, '|', s.DueDateMonthYearLong
			, '|', s.DueDateDay
			, '|', s.DueDateMonthNumber
			, '|', s.DueDateMonthShort
			, '|', s.DueDateMonthLong
			, '|', s.DueDateYear))
		FROM #DimDueDate s

		DROP TABLE IF EXISTS #LoadOperation

		CREATE TABLE #LoadOperation
		(DueDate DATE NULL
		,DueDateText VARCHAR(11) COLLATE DATABASE_DEFAULT NOT NULL
		,Operation CHAR(1) NOT NULL
		,UNIQUE (DueDate, DueDateText)
		)

		INSERT INTO #LoadOperation
			(DueDate
			,DueDateText
			,Operation
			)
		SELECT DueDate = COALESCE(t.DueDate, s.DueDate)
			,DueDateText = COALESCE(t.DueDateText COLLATE DATABASE_DEFAULT, s.DueDateText COLLATE DATABASE_DEFAULT)
			,Operation = CASE WHEN t.DimDueDateID IS NULL THEN 'I' WHEN s.DataHash IS NULL THEN 'D' ELSE 'U' END
		FROM (
			SELECT t.*
			FROM assumed.DimDueDate t
			WHERE t.EndDate = '31 Dec 9999'
			) t
		FULL JOIN #DimDueDate s
			ON COALESCE(s.DueDate, '1 Jan 1900') = COALESCE(t.DueDate, '1 Jan 1900')
			AND s.DueDateText = t.DueDateText COLLATE DATABASE_DEFAULT
		WHERE t.DataHash IS NULL
			OR s.DataHash IS NULL
			OR t.DataHash != s.DataHash

		BEGIN TRAN

		UPDATE t
		SET EndDate = p.ClosingEndDate
		FROM assumed.DimDueDate t
		INNER JOIN #LoadOperation lo
			ON COALESCE(lo.DueDate, '1 Jan 1900') = COALESCE(t.DueDate, '1 Jan 1900')
			AND lo.DueDateText = t.DueDateText
			AND lo.Operation = 'U'
		CROSS JOIN #Parameters p
		WHERE t.EndDate = '31 Dec 9999'

		INSERT INTO assumed.DimDueDate
			(StartDate
			,DueDate
			,DueDateMonthStart
			,DueDateMonthEnd
			,DueDateText
			,DueDateMonthYearShort
			,DueDateMonthYearLong
			,DueDateDay
			,DueDateMonthNumber
			,DueDateMonthShort
			,DueDateMonthLong
			,DueDateYear
			,DataHash
			)
		SELECT StartDate = p.NewStartDate
			,s.DueDate
			,s.DueDateMonthStart
			,s.DueDateMonthEnd
			,s.DueDateText
			,s.DueDateMonthYearShort
			,s.DueDateMonthYearLong
			,s.DueDateDay
			,s.DueDateMonthNumber
			,s.DueDateMonthShort
			,s.DueDateMonthLong
			,s.DueDateYear
			,s.DataHash
		FROM #DimDueDate s
		INNER JOIN #LoadOperation lo
			ON COALESCE(lo.DueDate, '1 Jan 1900') = COALESCE(s.DueDate, '1 Jan 1900')
			AND lo.DueDateText = s.DueDateText COLLATE DATABASE_DEFAULT
			AND lo.Operation IN ('I', 'U')
		CROSS JOIN #Parameters p

		COMMIT

		DECLARE @ProcessName VARCHAR(100) = OBJECT_SCHEMA_NAME(@@PROCID) + '.' + OBJECT_NAME(@@PROCID)
		DECLARE @RowsProcessed BIGINT = COALESCE((SELECT COUNT(0) FROM #LoadOperation WHERE Operation IN ('I', 'U')), 0)
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
