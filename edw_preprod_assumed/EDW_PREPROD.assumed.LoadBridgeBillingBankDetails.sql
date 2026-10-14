-- Database: EDW_PREPROD
-- Schema: assumed
-- Procedure: LoadBridgeBillingBankDetails


CREATE   PROCEDURE assumed.LoadBridgeBillingBankDetails
AS
BEGIN
	BEGIN TRY
		DROP TABLE IF EXISTS #Parameters

		SELECT ClosingEndDate = DATEADD(NANOSECOND, -100, SYSDATETIME())
			,NewStartDate = SYSDATETIME()
		INTO #Parameters

		-- Staging logic
		
		DROP TABLE IF EXISTS #BridgeBillingBankDetails
		
		SELECT db.DimBillingID
			,dbd.DimBankDetailsID
		INTO #BridgeBillingBankDetails
		FROM SRC_TIRS_DB.dbo.xrf_prod_accounts xpa
		INNER JOIN assumed.DimBankDetails dbd
			ON dbd.BankDetailCode = xpa.account_key
		INNER JOIN assumed.DimBilling db
			ON TRY_CAST(db.BILL_COMPANY_CD AS INT) = xpa.prod_br_key
			AND db.SourceSysKey = 4
			AND db.EndDate = '31 Dec 9999'
		
		        

		-- Loading logic
		ALTER TABLE #BridgeBillingBankDetails ADD DataHash BINARY(20) NULL

		UPDATE s
		SET DataHash = 0x0000000000000000000000000000000000000000
		FROM #BridgeBillingBankDetails s

		-- check/enforce uniqueness on the dimension source data
		CREATE UNIQUE INDEX assumed_BridgeBillingBankDetails_UK ON #BridgeBillingBankDetails (DimBillingID, DimBankDetailsID)

		DROP TABLE IF EXISTS #LoadOperation

		CREATE TABLE #LoadOperation
		(DimBillingID INT NOT NULL
		,DimBankDetailsID INT NOT NULL
		,Operation CHAR(1) NOT NULL
		,UNIQUE (DimBillingID, DimBankDetailsID)
		)

		INSERT INTO #LoadOperation
			(DimBillingID
			,DimBankDetailsID
			,Operation
			)
		SELECT DimBillingID = COALESCE(t.DimBillingID, s.DimBillingID)
			,DimBankDetailsID = COALESCE(t.DimBankDetailsID, s.DimBankDetailsID)
			,Operation = CASE WHEN t.BridgeBillingBankDetailsID IS NULL THEN 'I' WHEN s.DataHash IS NULL THEN 'D' ELSE 'U' END
		FROM (
			SELECT t.*
			FROM assumed.BridgeBillingBankDetails t
			WHERE t.EndDate = '31 Dec 9999'
			) t
		FULL JOIN #BridgeBillingBankDetails s
			ON s.DimBillingID = t.DimBillingID
			AND s.DimBankDetailsID = t.DimBankDetailsID
		WHERE t.DataHash IS NULL
			OR s.DataHash IS NULL
			OR t.DataHash != s.DataHash

		BEGIN TRAN

		UPDATE t
		SET EndDate = p.ClosingEndDate
		FROM assumed.BridgeBillingBankDetails t
		INNER JOIN #LoadOperation lo
			ON lo.DimBillingID = t.DimBillingID
			AND lo.DimBankDetailsID = t.DimBankDetailsID
			AND lo.Operation IN ('U', 'D')
		CROSS JOIN #Parameters p
		WHERE t.EndDate = '31 Dec 9999'

		INSERT INTO assumed.BridgeBillingBankDetails
			(StartDate
			,DimBillingID
			,DimBankDetailsID
			,DataHash
			)
		SELECT StartDate = p.NewStartDate
			,s.DimBillingID
			,s.DimBankDetailsID
			,s.DataHash
		FROM #BridgeBillingBankDetails s
		INNER JOIN #LoadOperation lo
			ON lo.DimBillingID = s.DimBillingID
			AND lo.DimBankDetailsID = s.DimBankDetailsID
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
