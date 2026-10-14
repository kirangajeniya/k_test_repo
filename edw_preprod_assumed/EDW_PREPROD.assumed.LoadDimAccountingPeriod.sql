-- Database: EDW_PREPROD
-- Schema: assumed
-- Procedure: LoadDimAccountingPeriod

CREATE   PROCEDURE assumed.LoadDimAccountingPeriod
AS
BEGIN
	BEGIN TRY
		DROP TABLE IF EXISTS #Parameters

		SELECT ClosingEndDate = DATEADD(NANOSECOND, -100, SYSDATETIME())
			,NewStartDate = SYSDATETIME()
		INTO #Parameters

		-- Staging logic
		
		DROP TABLE IF EXISTS #DimAccountingPeriod
		
		SELECT AccountingPeriodDate = '1 Jan 1900'
			,AccountingStartDate = '1 Jan 1900'
			,AccountingEndDate = '1 Jan 1900'
			,AccountingYear = 1900
			,AccountingMonthNum = 1
			,AccountingYearMonth = 'Uncoded'
		INTO #DimAccountingPeriod
		UNION ALL
		SELECT x.AccountingPeriodDate
			,x.AccountingStartDate
			,x.AccountingEndDate
			,AccountingYear = YEAR(x.AccountingPeriodDate)
			,AccountingMonthNum = MONTH(x.AccountingPeriodDate)
			,AccountingYearMonth = CONVERT(VARCHAR(7), x.AccountingPeriodDate, 120)
		FROM (
			SELECT AccountingPeriodDate = CAST(ap.accounting_period_date AS DATE)
				,AccountingStartDate = CAST(DATEADD(DAY, 1, LAG(ap.accounting_period_close_date) OVER (ORDER BY ap.accounting_period_key)) AS DATE)
				,AccountingEndDate = CAST(ap.accounting_period_close_date AS DATE)
			FROM Insight.dbo.accounting_periods ap
			) x
		WHERE x.AccountingStartDate IS NOT NULL
		

		-- Loading logic
		ALTER TABLE #DimAccountingPeriod ADD DataHash BINARY(20) NULL

		UPDATE s
		SET DataHash = HASHBYTES('SHA1', CONCAT(s.AccountingStartDate
			, '|', s.AccountingEndDate
			, '|', s.AccountingYear
			, '|', s.AccountingMonthNum
			, '|', s.AccountingYearMonth))
		FROM #DimAccountingPeriod s

		DROP TABLE IF EXISTS #LoadOperation

		CREATE TABLE #LoadOperation
		(AccountingPeriodDate DATE NOT NULL
		,Operation CHAR(1) NOT NULL
		,UNIQUE (AccountingPeriodDate)
		)

		INSERT INTO #LoadOperation
			(AccountingPeriodDate
			,Operation
			)
		SELECT AccountingPeriodDate = COALESCE(t.AccountingPeriodDate, s.AccountingPeriodDate)
			,Operation = CASE WHEN t.DimAccountingPeriodID IS NULL THEN 'I' WHEN s.DataHash IS NULL THEN 'D' ELSE 'U' END
		FROM (
			SELECT t.*
			FROM assumed.DimAccountingPeriod t
			WHERE t.EndDate = '31 Dec 9999'
			) t
		FULL JOIN #DimAccountingPeriod s
			ON s.AccountingPeriodDate = t.AccountingPeriodDate
		WHERE t.DataHash IS NULL
			OR s.DataHash IS NULL
			OR t.DataHash != s.DataHash

		BEGIN TRAN

		UPDATE t
		SET EndDate = p.ClosingEndDate
		FROM assumed.DimAccountingPeriod t
		INNER JOIN #LoadOperation lo
			ON lo.AccountingPeriodDate = t.AccountingPeriodDate
			AND lo.Operation = 'U'
		CROSS JOIN #Parameters p
		WHERE t.EndDate = '31 Dec 9999'

		INSERT INTO assumed.DimAccountingPeriod
			(StartDate
			,AccountingPeriodDate
			,AccountingStartDate
			,AccountingEndDate
			,AccountingYear
			,AccountingMonthNum
			,AccountingYearMonth
			,DataHash
			)
		SELECT StartDate = p.NewStartDate
			,s.AccountingPeriodDate
			,s.AccountingStartDate
			,s.AccountingEndDate
			,s.AccountingYear
			,s.AccountingMonthNum
			,s.AccountingYearMonth
			,s.DataHash
		FROM #DimAccountingPeriod s
		INNER JOIN #LoadOperation lo
			ON lo.AccountingPeriodDate = s.AccountingPeriodDate
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
