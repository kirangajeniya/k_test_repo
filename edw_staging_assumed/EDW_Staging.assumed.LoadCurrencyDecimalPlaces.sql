-- Database: EDW_Staging
-- Schema: assumed
-- Procedure: LoadCurrencyDecimalPlaces

CREATE   PROCEDURE assumed.LoadCurrencyDecimalPlaces
AS
BEGIN
	BEGIN TRY
		DROP TABLE IF EXISTS #Parameters

		SELECT
		     ClosingEndDate = DATEADD(NANOSECOND, -100, SYSDATETIME())
			,NewStartDate	= SYSDATETIME()
		INTO #Parameters

		-----------------------------------------------------------------
		-- Currency's list for spetial ROUNDING		
		-----------------------------------------------------------------
		DROP TABLE IF EXISTS #CurrencyDecPlaces

		SELECT
			 x.CurrencyCode
			,x.DecPlaces
		INTO #CurrencyDecPlaces
		FROM (
			VALUES 
			 ('CVE' ,0)
			,('GNF', 0)
			,('IDR', 0)
			,('JPY', 0)
			,('KMF', 0)
			,('KRW', 0)
			,('PYG', 0)
			,('RWF', 0)
			,('UGX', 0)
			,('VND', 0)
			,('VUV', 0)
			,('XAF', 0)
			,('XOF', 0)
			,('XPF', 0)
			) x (CurrencyCode, DecPlaces)

		-----------------------------------------------------------------
		-- Loading logic
		-----------------------------------------------------------------
		ALTER TABLE #CurrencyDecPlaces ADD DataHash BINARY(20) NULL

		UPDATE s
		   SET DataHash = HASHBYTES('SHA1', CONCAT(s.DecPlaces,'|'))
		  FROM #CurrencyDecPlaces s

		DROP TABLE IF EXISTS #LoadOperation

		CREATE TABLE #LoadOperation
		(CurrencyCode	VARCHAR(100) COLLATE DATABASE_DEFAULT NOT NULL
		,Operation		CHAR(1) NOT NULL
		,UNIQUE (CurrencyCode)
		)

		INSERT INTO #LoadOperation
			(CurrencyCode
			,Operation
			)
		SELECT
			 CurrencyCode	= COALESCE(t.CurrencyCode COLLATE DATABASE_DEFAULT, s.CurrencyCode COLLATE DATABASE_DEFAULT)
			,Operation		= CASE	WHEN t.CurrencyDecimalPlacesID IS NULL
									THEN 'I'
									WHEN s.DataHash IS NULL
									THEN 'D'
									ELSE 'U' END
		FROM (SELECT *
			    FROM assumed.CurrencyDecimalPlaces
			   WHERE EndDate = '31 Dec 9999' )	AS t
		FULL JOIN #CurrencyDecPlaces			AS s	ON s.CurrencyCode = t.CurrencyCode COLLATE DATABASE_DEFAULT
		WHERE
			t.DataHash IS NULL
			OR s.DataHash IS NULL
			OR t.DataHash != s.DataHash
		-----------------------------------------------------------------
		---Data actualization in assumed.CurrencyDecimalPlaces
		-----------------------------------------------------------------
		BEGIN TRAN
		--Close row
		UPDATE t
		   SET EndDate = p.ClosingEndDate
		  FROM assumed.CurrencyDecimalPlaces	AS t
		 INNER JOIN #LoadOperation				AS lo	ON  lo.CurrencyCode = t.CurrencyCode
														AND lo.Operation IN ('U', 'D')
		CROSS JOIN #Parameters p
		WHERE t.EndDate = '31 Dec 9999'

		--Insert new row
		INSERT INTO assumed.CurrencyDecimalPlaces
			(StartDate
			,CurrencyCode
			,DecPlaces
			,DataHash
			)
		SELECT
			 StartDate = p.NewStartDate
			,s.CurrencyCode
			,s.DecPlaces
			,s.DataHash
		 FROM #CurrencyDecPlaces		AS s
		CROSS JOIN #Parameters			AS p
		INNER JOIN #LoadOperation		AS lo	ON  lo.CurrencyCode = s.CurrencyCode COLLATE DATABASE_DEFAULT
												AND lo.Operation IN ('I', 'U')
		COMMIT
		-----------------------------------------------------------------
		--Logging
		-----------------------------------------------------------------
		DECLARE @ProcessName		VARCHAR(100)= OBJECT_SCHEMA_NAME(@@PROCID) + '.' + OBJECT_NAME(@@PROCID)
		DECLARE @RowsProcessed		BIGINT		= COALESCE((SELECT COUNT(0) FROM #LoadOperation WHERE Operation IN ('I', 'U', 'D')), 0)
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
