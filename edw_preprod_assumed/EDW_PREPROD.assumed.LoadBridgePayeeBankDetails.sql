-- Database: EDW_PREPROD
-- Schema: assumed
-- Procedure: LoadBridgePayeeBankDetails

CREATE   PROCEDURE assumed.LoadBridgePayeeBankDetails
AS
BEGIN
	BEGIN TRY
		DROP TABLE IF EXISTS #Parameters

		SELECT ClosingEndDate = DATEADD(NANOSECOND, -100, SYSDATETIME())
			,NewStartDate = SYSDATETIME()
			,DimPayeeUncoded = (SELECT dp.DimPayeeID FROM EDW_PREPROD.assumed.DimPayee dp WHERE dp.PayeeName = 'Uncoded')
			,DimPayeeNA = (SELECT dp.DimPayeeID FROM EDW_PREPROD.assumed.DimPayee dp WHERE dp.PayeeName = 'N/A')
			,DimBankDetailsUncoded = (SELECT dp.DimBankDetailsID FROM EDW_PREPROD.assumed.DimBankDetails dp WHERE dp.Account = 'Uncoded')
			,DimBankDetailsNA = (SELECT dp.DimBankDetailsID FROM EDW_PREPROD.assumed.DimBankDetails dp WHERE dp.Account = 'N/A')
		INTO #Parameters

		-- Staging logic
		
		DROP TABLE IF EXISTS #BridgePayeeBankDetails
		
		SELECT DISTINCT PayeeCode = xpa.prod_br_key
			,BankDetailCode = xpa.account_key
		INTO #BridgePayeeBankDetails
		FROM SRC_TIRS_DB.dbo.xrf_prod_accounts xpa
		
		-- Loading logic
		ALTER TABLE #BridgePayeeBankDetails
			ADD	DimPayeeID			INT	NULL,
				DimBankDetailsID	INT	NULL,
				DataHash			BINARY(20) NULL
		
		UPDATE s
		SET DimPayeeID = CASE WHEN s.PayeeCode IS NULL THEN prm.DimPayeeNA ELSE COALESCE(d.DimPayeeID, prm.DimPayeeUncoded) END
		FROM #BridgePayeeBankDetails s
		CROSS JOIN #Parameters prm
		LEFT JOIN EDW_PREPROD.assumed.DimPayee d
			ON d.PayeeCode = s.PayeeCode
		
		UPDATE s
		SET DimBankDetailsID = CASE WHEN s.BankDetailCode IS NULL THEN prm.DimBankDetailsNA ELSE COALESCE(d.DimBankDetailsID, prm.DimBankDetailsUncoded) END
		FROM #BridgePayeeBankDetails s
		CROSS JOIN #Parameters prm
		LEFT JOIN EDW_PREPROD.assumed.DimBankDetails d
			ON d.BankDetailCode = s.BankDetailCode
		
		UPDATE s
		SET DataHash = HASHBYTES('SHA1', CONCAT_WS('|'
			,s.DimPayeeID
			,s.DimBankDetailsID))
		FROM #BridgePayeeBankDetails s

		DROP TABLE IF EXISTS #LoadOperation

		CREATE TABLE #LoadOperation
		(PayeeCode		INT NULL
		,BankDetailCode	INT NULL
		,Operation CHAR(1) NOT NULL
		,UNIQUE (PayeeCode, BankDetailCode)
		)

		INSERT INTO #LoadOperation
			(PayeeCode
			,BankDetailCode
			,Operation
			)
		SELECT PayeeCode = COALESCE(t.PayeeCode, s.PayeeCode)
			,BankDetailCode = COALESCE(t.BankDetailCode, s.BankDetailCode)
			,Operation = CASE WHEN t.BridgePayeeBankDetailsID IS NULL THEN 'I' WHEN s.DataHash IS NULL THEN 'D' WHEN t.DataHash != s.DataHash THEN 'U' END
		FROM (
			SELECT t.*
			FROM assumed.BridgePayeeBankDetails t
			WHERE t.EndDate = '31 Dec 9999'
			) t
		FULL JOIN #BridgePayeeBankDetails s
			ON COALESCE(s.PayeeCode, -1) = COALESCE(t.PayeeCode, -1)
			AND COALESCE(s.BankDetailCode, -1) = COALESCE(t.BankDetailCode, -1)
		WHERE t.DataHash IS NULL
			OR s.DataHash IS NULL
			OR t.DataHash != s.DataHash

		BEGIN TRAN

		UPDATE t
		SET EndDate = p.ClosingEndDate
		FROM assumed.BridgePayeeBankDetails t
		INNER JOIN #LoadOperation lo
			ON COALESCE(lo.PayeeCode, -1) = COALESCE(t.PayeeCode, -1)
			AND COALESCE(lo.BankDetailCode, -1) = COALESCE(t.BankDetailCode, -1)
			AND lo.Operation IN ('U', 'D')
		CROSS JOIN #Parameters p
		WHERE t.EndDate = '31 Dec 9999'

		INSERT INTO assumed.BridgePayeeBankDetails
			(StartDate
			,PayeeCode
			,BankDetailCode
			,DimPayeeID
			,DimBankDetailsID
			,DataHash
			)
		SELECT StartDate = p.NewStartDate
			,s.PayeeCode
			,s.BankDetailCode
			,s.DimPayeeID
			,s.DimBankDetailsID
			,s.DataHash
		FROM #BridgePayeeBankDetails s
		INNER JOIN #LoadOperation lo
			ON COALESCE(lo.PayeeCode, -1) = COALESCE(s.PayeeCode, -1)
			AND COALESCE(lo.BankDetailCode, -1) = COALESCE(s.BankDetailCode, -1)
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
