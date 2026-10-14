-- Database: EDW_PREPROD
-- Schema: assumed
-- Procedure: LoadDimDate


CREATE   PROCEDURE [assumed].[LoadDimDate]
AS
BEGIN
	BEGIN TRY
		DROP TABLE IF EXISTS #Parameters

		SELECT
			 ClosingEndDate	= DATEADD(NANOSECOND, -100, SYSDATETIME())
			,NewStartDate	= SYSDATETIME()
		INTO #Parameters

		-- Staging logic
		DROP TABLE IF EXISTS #DimDate

		;WITH DateSequence AS (
			SELECT CAST('1900-01-01' AS DATE) AS DateValue
			UNION ALL
			SELECT DATEADD(DAY, 1, DateValue)
			FROM DateSequence
			WHERE DateValue < DATEADD(YEAR, 60, GETDATE())
		)
		SELECT
			 Date				= d.DateValue
			,DateMonthStart		= DATEADD(DAY, 1 - DAY(d.DateValue), d.DateValue)
			,DateMonthEnd		= EOMONTH(d.DateValue)
			,DateText			= FORMAT(d.DateValue, 'MMM d yyyy')
			,DateMonthYearShort = FORMAT(d.DateValue, 'MMM yyyy')
			,DateMonthYearLong	= FORMAT(d.DateValue, 'MMMM yyyy')
			,DateDay			= DAY(d.DateValue)
			,DateMonthNumber	= MONTH(d.DateValue)
			,DateMonthShort		= FORMAT(d.DateValue, 'MMM')
			,DateMonthLong		= FORMAT(d.DateValue, 'MMMM')
			,DateYear			= YEAR(d.DateValue)
		INTO #DimDate
		FROM DateSequence AS d
		UNION ALL
		SELECT
			 Date				= NULL
			,DateMonthStart		= NULL
			,DateMonthEnd		= NULL
			,DateText			= 'Uncoded'
			,DateMonthYearShort = 'Uncoded'
			,DateMonthYearLong	= 'Uncoded'
			,DateDay			= NULL
			,DateMonthNumber	= NULL
			,DateMonthShort		= NULL
			,DateMonthLong		= 'Uncoded'
			,DateYear			= NULL
		UNION ALL
		SELECT
			 Date				= NULL
			,DateMonthStart		= NULL
			,DateMonthEnd		= NULL
			,DateText			= 'N/A'
			,DateMonthYearShort = 'N/A'
			,DateMonthYearLong	= 'N/A'
			,DateDay			= NULL
			,DateMonthNumber	= NULL
			,DateMonthShort		= NULL
			,DateMonthLong		= 'N/A'
			,DateYear			= NULL
		OPTION (MAXRECURSION 0);

		-- Loading logic
		ALTER TABLE #DimDate ADD DataHash BINARY(20) NULL

		UPDATE s
		SET DataHash = HASHBYTES('SHA1',CONCAT(CONVERT(DATE		,s.DateMonthStart)						
										, '|', CONVERT(DATE		,s.DateMonthEnd)						
										, '|', CONVERT(VARCHAR	,s.DateMonthYearShort)					
										, '|', CONVERT(VARCHAR	,s.DateMonthYearLong)
										, '|', CONVERT(TINYINT	,s.DateDay)
										, '|', CONVERT(TINYINT	,s.DateMonthNumber)	
										, '|', CONVERT(VARCHAR	,s.DateMonthShort)
										, '|', CONVERT(VARCHAR	,s.DateMonthLong)
										, '|', CONVERT(SMALLINT	,s.DateYear)
			))										
		FROM #DimDate s
		---------------------------------------------------------------------
		--#LoadOperation
		---------------------------------------------------------------------
		DROP TABLE IF EXISTS #LoadOperation

		CREATE TABLE #LoadOperation (
			 Date		DATE NULL
			,DateText	VARCHAR(11) COLLATE DATABASE_DEFAULT NOT NULL
			,Operation	CHAR(1) NOT NULL
			,UNIQUE (Date, DateText)
		)

		INSERT INTO #LoadOperation (
			 Date
			,DateText
			,Operation
		)
		SELECT
			 Date		= COALESCE(t.Date, s.Date)
			,DateText	= COALESCE(t.DateText COLLATE DATABASE_DEFAULT, s.DateText COLLATE DATABASE_DEFAULT)
			,Operation	= CASE WHEN t.DimDateID IS NULL THEN 'I' WHEN s.DataHash IS NULL THEN 'D' ELSE 'U' END
		FROM (SELECT t.*
				FROM assumed.DimDate t
			   WHERE t.EndDate = '9999-12-31')	 t
		FULL JOIN #DimDate	s	ON  COALESCE(s.Date, '1900-01-01') = COALESCE(t.Date, '1900-01-01')
								AND s.DateText = t.DateText COLLATE DATABASE_DEFAULT
		WHERE t.DataHash IS NULL
		   OR s.DataHash IS NULL
		   OR t.DataHash != s.DataHash
		---------------------------------------------------------------------
		--INSERT changes
		---------------------------------------------------------------------
		BEGIN TRAN

		UPDATE t
		   SET EndDate = p.ClosingEndDate
		  FROM assumed.DimDate		t
		 INNER JOIN #LoadOperation	lo	ON  COALESCE(lo.Date, '1900-01-01') = COALESCE(t.Date, '1900-01-01')
										AND lo.DateText = t.DateText
										AND lo.Operation = 'U'
		CROSS JOIN #Parameters p
		WHERE t.EndDate = '9999-12-31'

		INSERT INTO assumed.DimDate (
			 StartDate
			,Date
			,DateMonthStart
			,DateMonthEnd
			,DateText
			,DateMonthYearShort
			,DateMonthYearLong
			,DateDay
			,DateMonthNumber
			,DateMonthShort
			,DateMonthLong
			,DateYear
			,DataHash
		)
		SELECT
			 StartDate = p.NewStartDate
			,s.Date
			,s.DateMonthStart
			,s.DateMonthEnd
			,s.DateText
			,s.DateMonthYearShort
			,s.DateMonthYearLong
			,s.DateDay
			,s.DateMonthNumber
			,s.DateMonthShort
			,s.DateMonthLong
			,s.DateYear
			,s.DataHash
		 FROM #DimDate s
		CROSS JOIN #Parameters p
		INNER JOIN #LoadOperation lo	ON  COALESCE(lo.Date, '1900-01-01') = COALESCE(s.Date, '1900-01-01')
										AND lo.DateText = s.DateText COLLATE DATABASE_DEFAULT
										AND lo.Operation IN ('I', 'U')
		COMMIT
		---------------------------------------------------------------------
		--Logging
		---------------------------------------------------------------------
		DECLARE @ProcessName		VARCHAR(100)= OBJECT_SCHEMA_NAME(@@PROCID) + '.' + OBJECT_NAME(@@PROCID)
		DECLARE @RowsProcessed		BIGINT		= COALESCE((SELECT COUNT(0) FROM #LoadOperation WHERE Operation IN ('I', 'U')), 0)
		DECLARE @LastIdentity		BIGINT		= SCOPE_IDENTITY()
		DECLARE @ProcessingStarted	DATETIME	= (SELECT p.NewStartDate FROM #Parameters p)
		DECLARE @ProcessingEnded	DATETIME	= GETDATE()
		DECLARE @SourceDataDate		DATETIME	= (SELECT [sql_date] FROM ETL.dbo.[day] WHERE today = 1)

		EXEC ETL.dbo.update_etl_controller
			 @ps_process_name			= @ProcessName
			,@pn_rows_processed			= @RowsProcessed
			,@pdt_data_datetime			= @SourceDataDate
			,@pdt_process_start_datetime= @ProcessingStarted
			,@pdt_process_end_datetime	= @ProcessingEnded
			,@pn_error_number			= 0
			,@ps_comment				= NULL
			,@pn_max_processed_event_id = @LastIdentity
	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > 0
		BEGIN
			ROLLBACK
		END

		DECLARE @ErrorDescription	VARCHAR(8000)	= CONCAT('Error: ', ERROR_NUMBER(), ' - ', ERROR_MESSAGE(), '; ', 'Occurred in procedure: ' + ERROR_PROCEDURE() + ', ', 'Line ', ERROR_LINE())
		DECLARE @ErrorNumber		INT				= ERROR_NUMBER()
		DECLARE @ErrorMessage		VARCHAR(8000)	= ERROR_MESSAGE()
		DECLARE @ErrorSeverity		INT				= ERROR_SEVERITY()
		DECLARE @ErrorState			INT				= ERROR_STATE()
		DECLARE @ProcessNameC		VARCHAR(100)	= OBJECT_SCHEMA_NAME(@@PROCID) + '.' + OBJECT_NAME(@@PROCID)
		DECLARE @ProcessingStartedC DATETIME		= (SELECT p.NewStartDate FROM #Parameters p)
		DECLARE @ProcessingEndedC	DATETIME		= GETDATE()
		DECLARE @SourceDataDateC	DATETIME		= (SELECT [sql_date] FROM ETL.dbo.[day] WHERE today = 1)

		EXEC ETL.dbo.update_etl_controller
			 @ps_process_name			= @ProcessNameC
			,@pn_rows_processed			= 0
			,@pdt_data_datetime			= @SourceDataDateC
			,@pdt_process_start_datetime= @ProcessingStartedC
			,@pdt_process_end_datetime	= @ProcessingEndedC
			,@pn_error_number			= @ErrorNumber
			,@ps_comment				= @ErrorDescription
			,@pn_max_processed_event_id = 0

		EXEC ETL.dbo.insert_error_log
			 @process_name	= @ProcessNameC
			,@object_name	= 0
			,@user_message	= @ErrorDescription
			,@status		= 0
			,@remedy		= 'Contact EDW team'

		RAISERROR(@ErrorDescription, @ErrorSeverity, @ErrorState)
	END CATCH
END