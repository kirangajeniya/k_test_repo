-- Database: EDW_PREPROD
-- Schema: assumed
-- Procedure: LoadDimMeasure

CREATE   PROCEDURE assumed.LoadDimMeasure
AS
BEGIN
	BEGIN TRY
		DROP TABLE IF EXISTS #Parameters

		SELECT ClosingEndDate = DATEADD(NANOSECOND, -100, SYSDATETIME())
			,NewStartDate = SYSDATETIME()
		INTO #Parameters

		-- Staging logic
		
		DROP TABLE IF EXISTS #DimMeasure
		
		SELECT x.MeasureCode
		,x.MeasureName
		,x.Entity
		,x.Business
		,x.CurrencyType
		,x.MeasureType
		,x.RevenueCode
		INTO #DimMeasure
		FROM (
		SELECT x.MeasureCode
		,COALESCE(x.MeasureName, CASE  WHEN x.Entity = 'Claim'AND x.Business ='RI Ceded' THEN   'Ceded_'+REPLACE(x.MeasureCode,'Summable_','')
    		ELSE REPLACE(x.MeasureCode,'Summable_','') END) AS MeasureName
		,x.Entity
		,x.Business
		,x.CurrencyType
		,x.MeasureType
		,x.RevenueCode
		FROM (
		VALUES('Uncoded'									, 'Uncoded'		, 'Uncoded'		, 'Uncoded'		, 'Uncoded'					, 'Uncoded', NULL)
			,('SUMMABLE_LAE'								, 'Claim'		, 'RI Assumed'	, 'Original'	, 'Loss Adjustment Expense'	, 'LAEPAID', NULL)
			,('SUMMABLE_LOSS_PAID'							, 'Claim'		, 'RI Assumed'	, 'Original'	, 'Loss Paid'				, 'LOSSPAID', NULL)
			,('SUMMABLE_LOSS_EXP_PAID'						, 'Claim'		, 'RI Assumed'	, 'Original'	, 'Loss Expense Paid'		, 'MUE', NULL)
			,('SUMMABLE_CASH_LOSS_ADV_AMT'					, 'Claim'		, 'RI Assumed'	, 'Original'	, 'Cash Loss Advance'		, 'LOSSPAID', NULL)
			,('SUMMABLE_CASH_LOSS_REFUND'					, 'Claim'		, 'RI Assumed'	, 'Original'	, 'Cash Loss Refund'		, 'LOSSPAID', NULL)
			,('SUMMABLE_FUNDS_RELEASED_LOSSES'				, 'Claim'		, 'RI Assumed'	, 'Original'	, 'Funds Released Losses'	, 'FundsHeld', NULL)
			,('SUMMABLE_REINSTATEMENT_PREMIUM'				, 'Claim'		, 'RI Assumed'	, 'Original'	, 'Reinstatement Premium'	, 'RIPR', NULL)
			,('SUMMABLE_OS_LOSS'							, 'Claim'		, 'RI Assumed'	, 'Original'	, 'Outstanding Loss'		, 'LOSSOSLR', NULL)
			,('SUMMABLE_OS_LOSS_EXP'						, 'Claim'		, 'RI Assumed'	, 'Original'	, 'Outstanding Loss Expense', 'LAEOSLR', NULL)
			,('SUMMABLE_LOSS_PAID'							, 'Claim'		, 'RI Ceded'	, 'Original'	, 'Loss Paid'				, 'LOSSPAID', NULL)
			,('SUMMABLE_LOSS_EXP_PAID'						, 'Claim'		, 'RI Ceded'	, 'Original'	, 'Loss Expense Paid'		, 'MUE', NULL)
			,('SUMMABLE_LAE'								, 'Claim'		, 'RI Ceded'	, 'Original'	, 'Loss Adjustment Expense'	, 'LAEPAID', NULL)
			,('SUMMABLE_CASH_LOSS_ADV_AMT'					, 'Claim'		, 'RI Ceded'	, 'Original'	, 'Cash Loss Advance'		, 'LOSSPAID', NULL)
			,('SUMMABLE_CASH_LOSS_REFUND'					, 'Claim'		, 'RI Ceded'	, 'Original'	, 'Cash Loss Refund'		, 'LOSSPAID', NULL)
			,('SUMMABLE_FUNDS_RELEASED_LOSSES'				, 'Claim'		, 'RI Ceded'	, 'Original'	, 'Funds Released Losses'	, 'FundsHeld', NULL)
			,('SUMMABLE_OS_LOSS'							, 'Claim'		, 'RI Ceded'	, 'Original'	, 'Outstanding Loss'		, 'LOSSOSLR', NULL)
			,('SUMMABLE_OS_LOSS_EXP'						, 'Claim'		, 'RI Ceded'	, 'Original'	, 'Outstanding Loss Expense', 'LAEOSLR', NULL)
			,('SUMMABLE_REINSTATEMENT_PREMIUM'				, 'Claim'		, 'RI Ceded'	, 'Original'	, 'Reinstatement Premium'	, 'RIPR', NULL)
			,('SUMMABLE_LOSS_PAID'							, 'Claim'		, 'RI Assumed'	, 'Settlement'	, 'Loss Paid'				, 'LOSSPAID', NULL)
			,('SUMMABLE_LAE'								, 'Claim'		, 'RI Assumed'	, 'Settlement'	, 'Loss Adjustment Expense'	, 'LAEPAID', NULL)
			,('FIRV_IBNR_BEGIN'								, 'Claim'		, 'RI Assumed'	, 'Original'	, 'FIRV IBNR Begin'	, 'N/A', 'FIRV_IBNR_BEGIN')
			,('FIRV_IBNR_END'								, 'Claim'		, 'RI Assumed'	, 'Original'	, 'FIRV IBNR End'	, 'N/A', 'FIRV_IBNR_END')
			,('FIRV_IBNR_BEGIN'								, 'Claim'		, 'RI Ceded'	, 'Original'	, 'FIRV IBNR Begin'	, 'N/A', 'CEDED_FIRV_IBNR_BEGIN')
			,('FIRV_IBNR_END'								, 'Claim'		, 'RI Ceded'	, 'Original'	, 'FIRV IBNR End'	, 'N/A', 'CEDED_FIRV_IBNR_END')
			------------------------------------------------------------------------------------------------------------
			,('SUMMABLE_xch_diff'							, 'Premium'		, 'RI Assumed', 'Original', 'Brokerage', 'BRK', NULL)
			,('SUMMABLE_NO_CLM_RBT'							, 'Premium'		, 'RI Assumed', 'Original', 'Premium', 'PRM', NULL)			
			,('SUMMABLE_WRTN_PREM_ALL_DOC_TYPES'			, 'Premium'		, 'RI Assumed', 'Original', 'Premium', 'PRM', NULL)
			,('SUMMABLE_WRTN_PREM_No_Claims_Rebate '			, 'Premium'		, 'RI Assumed', 'Original', 'Not used Atm ', 'PRM', NULL)
			,('SUMMABLE_WRTN_PREM_Reinstatement_Premium'	, 'Premium'		, 'RI Assumed', 'Original', 'Reinstatement Premium', 'RIPR', NULL)
			,('SUMMABLE_UEPR'								, 'Premium'		, 'RI Assumed', 'Original', 'UEPR', 'UEPR', NULL)
			,('SUMMABLE_Brokerage'							, 'Premium'		, 'RI Assumed', 'Original', 'Brokerage', 'BRK', NULL)
			,('SUMMABLE_Commission'							, 'Premium'		, 'RI Assumed', 'Original', 'Commission', 'COM', NULL)
			,('SUMMABLE_tax_nonrefund'						, 'Premium'		, 'RI Assumed', 'Original', 'Tax', 'Tax', NULL)
			,('SUMMABLE_tax_on_prem'						, 'Premium'		, 'RI Assumed', 'Original', 'Tax', 'Tax', NULL)
			,('SUMMABLE_Tax_refund'							, 'Premium'		, 'RI Assumed', 'Original', 'Tax', 'Tax', NULL)
			,('SUMMABLE_DAC'								, 'Premium'		, 'RI Assumed', 'Original', 'DAC', 'DAC', NULL)
			,('SUMMABLE_Profit_Commission_Paid'				, 'Premium'		, 'RI Assumed', 'Original', 'Profit Commission Payable', 'LR28', NULL)
			,('SUMMABLE_Sliding_Scale_Commission'			, 'Premium'		, 'RI Assumed', 'Original', 'Commission', 'COM', NULL)
			,('SUMMABLE_Overrider_Commission'				, 'Premium'		, 'RI Assumed', 'Original', 'Commission', 'COM', NULL)
			,('SUMMABLE_Provisional_Commission'				, 'Premium'		, 'RI Assumed', 'Original', 'Commission', 'COM', NULL)
			,('SUMMABLE_Deferred_Commission'				, 'Premium'		, 'RI Assumed', 'Original', 'Commission', 'COM', NULL)
			,('SUMMABLE_int_funds_gross'					, 'Premium'		, 'RI Assumed', 'Original', 'Interest', 'Interest', NULL)
			,('SUMMABLE_int_funds_wth'						, 'Premium'		, 'RI Assumed', 'Original', 'Interest', 'Interest', NULL)
			,('SUMMABLE_fire_prevent_fund'					, 'Premium'		, 'RI Assumed', 'Original', 'Brokerage', 'BRK', NULL)	
			,('SUMMABLE_funds_withheld_premium'				, 'Premium'		, 'RI Assumed', 'Original', 'FundHeld_Premium', 'FundsHeld', NULL)
			,('SUMMABLE_funds_released_premium'				, 'Premium'		, 'RI Assumed', 'Original', 'FundHeld_Premium', 'FundsHeld', NULL)
			,('SUMMABLE_funds_withheld_losses'				, 'Premium'		, 'RI Assumed', 'Original', 'FundHeld_Premium', 'FundsHeld', NULL)
			,('SUMMABLE_deferred_withheld'					, 'Premium'		, 'RI Assumed', 'Original', 'FundHeld_Premium', 'FundsHeld', NULL)
			,('SUMMABLE_deferred_released'					, 'Premium'		, 'RI Assumed', 'Original', 'FundHeld_Premium', 'FundsHeld', NULL)			
			,('SUMMABLE_UEPR_RPT_CURR1'			            , 'Premium'		, 'RI Assumed', 'Original', 'Unknown', 'Unknown', NULL)
			,('SUMMABLE_UEPR_RPT_CURR2'			            , 'Premium'		, 'RI Assumed', 'Original', 'Unknown', 'Unknown', NULL)
			,('SUMMABLE_DAC_RPT_CURR1'			            , 'Premium'		, 'RI Assumed', 'Original', 'Unknown', 'Unknown', NULL)
			,('SUMMABLE_DAC_RPT_CURR2'			            , 'Premium'		, 'RI Assumed', 'Original', 'Unknown', 'Unknown', NULL)
			,('SUMMABLE_FUNDS_RELEASED_LOSSES'				, 'Premium'		, 'RI Assumed', 'Original', 'Funds Released Losses', 'FundsHeld', NULL)
			,('SUMMABLE_CEDED_WRTN_PREM_ALL_DOC_TYPES'		, 'Premium'		, 'RI Ceded', 'Original', 'Premium', 'PRM', NULL)
			,('SUMMABLE_CEDED_WRTN_PREM_No_Claims_Rebate'	, 'Premium'		, 'RI Ceded', 'Original', 'Not used Atm ', 'PRM', NULL)
			,('SUMMABLE_CEDED_WRTN_PREM_Reinstatement_Premium', 'Premium'	, 'RI Ceded', 'Original', 'Reinstatement Premium', 'RIPR', NULL)
			,('SUMMABLE_CEDED_UEPR'							, 'Premium'		, 'RI Ceded', 'Original', 'UEPR', 'UEPR', NULL)
			,('SUMMABLE_CEDED_Brokerage'					, 'Premium'		, 'RI Ceded', 'Original', 'Brokerage', 'BRK', NULL)
			,('SUMMABLE_CEDED_Commission'					, 'Premium'		, 'RI Ceded', 'Original', 'Commission', 'COM', NULL)
			,('SUMMABLE_CEDED_tax_nonrefund'				, 'Premium'		, 'RI Ceded', 'Original', 'Tax', 'Tax', NULL)
			,('SUMMABLE_CEDED_tax_on_prem'					, 'Premium'		, 'RI Ceded', 'Original', 'Tax', 'Tax', NULL)
			,('SUMMABLE_CEDED_Tax_refund'					, 'Premium'		, 'RI Ceded', 'Original', 'Tax', 'Tax', NULL)
			,('SUMMABLE_CEDED_DAC'							, 'Premium'		, 'RI Ceded', 'Original', 'DAC', 'DAC', NULL)
			,('SUMMABLE_CEDED_Profit_Commission_Paid'		, 'Premium'		, 'RI Ceded', 'Original', 'Profit Commission Payable', 'LR28', NULL)
			,('SUMMABLE_CEDED_Sliding_Scale_Commission'		, 'Premium'		, 'RI Ceded', 'Original', 'Commission', 'COM', NULL)
			,('SUMMABLE_CEDED_Overrider_Commission'			, 'Premium'		, 'RI Ceded', 'Original', 'Commission', 'COM', NULL)
			,('SUMMABLE_CEDED_Provisional_Commission'		, 'Premium'		, 'RI Ceded', 'Original', 'Commission', 'COM', NULL)
			,('SUMMABLE_CEDED_Deferred_Commission'			, 'Premium'		, 'RI Ceded', 'Original', 'Commission', 'COM', NULL)
			,('SUMMABLE_CEDED_int_funds_gross'				, 'Premium'		, 'RI Ceded', 'Original', 'Interest', 'Interest', NULL)
			,('SUMMABLE_CEDED_int_funds_wth'				, 'Premium'		, 'RI Ceded', 'Original', 'Interest', 'Interest', NULL)
			,('SUMMABLE_CEDED_fire_prevent_fund'			, 'Premium'		, 'RI Ceded', 'Original', 'Brokerage', 'BRK', NULL)
			,('SUMMABLE_CEDED_xch_diff'						, 'Premium'		, 'RI Ceded', 'Original', 'Brokerage', 'BRK', NULL)
			,('SUMMABLE_CEDED_NO_CLM_RBT'					, 'Premium'		, 'RI Ceded', 'Original', 'Premium', 'PRM', NULL)
			,('SUMMABLE_CEDED_funds_withheld_premium'		, 'Premium'		, 'RI Ceded', 'Original', 'FundHeld_Premium', 'FundsHeld', NULL)
			,('SUMMABLE_CEDED_funds_released_premium'		, 'Premium'		, 'RI Ceded', 'Original', 'FundHeld_Premium', 'FundsHeld', NULL)
			,('SUMMABLE_CEDED_funds_withheld_losses'		, 'Premium'		, 'RI Ceded', 'Original', 'FundHeld_Premium', 'FundsHeld', NULL)
			,('SUMMABLE_CEDED_deferred_withheld'			, 'Premium'		, 'RI Ceded', 'Original', 'FundHeld_Premium', 'FundsHeld', NULL)
			,('SUMMABLE_CEDED_deferred_released'			, 'Premium'		, 'RI Ceded', 'Original', 'FundHeld_Premium', 'FundsHeld', NULL)
		) x (MeasureCode, Entity, Business, CurrencyType, MeasureType, RevenueCode, MeasureName)
		) x

		-- Loading logic
		ALTER TABLE #DimMeasure ADD DataHash BINARY(20) NULL		
		ALTER TABLE #DimMeasure ADD DataHashType1 BINARY(20) NULL

		UPDATE s
		SET DataHash = HASHBYTES('SHA1', CONCAT('', s.RevenueCode))
		FROM #DimMeasure s

		UPDATE s
		SET DataHashType1 = HASHBYTES('SHA1', CONCAT('', s.MeasureName))
		FROM #DimMeasure s

		DROP TABLE IF EXISTS #LoadOperation

		CREATE TABLE #LoadOperation
		(MeasureCode VARCHAR(50) COLLATE DATABASE_DEFAULT NOT NULL
		,Entity VARCHAR(15) COLLATE DATABASE_DEFAULT NOT NULL
		,Business VARCHAR(15) COLLATE DATABASE_DEFAULT NOT NULL
		,CurrencyType VARCHAR(15) COLLATE DATABASE_DEFAULT NOT NULL
		,MeasureType VARCHAR(40) COLLATE DATABASE_DEFAULT NOT NULL
		,Operation CHAR(1) NOT NULL
		,UNIQUE (MeasureCode, Entity, Business, CurrencyType, MeasureType)
		)

		INSERT INTO #LoadOperation
			(MeasureCode
			,Entity
			,Business
			,CurrencyType
			,MeasureType
			,Operation
			)
		SELECT MeasureCode = COALESCE(t.MeasureCode COLLATE DATABASE_DEFAULT, s.MeasureCode COLLATE DATABASE_DEFAULT)
			,Entity = COALESCE(t.Entity COLLATE DATABASE_DEFAULT, s.Entity COLLATE DATABASE_DEFAULT)
			,Business = COALESCE(t.Business COLLATE DATABASE_DEFAULT, s.Business COLLATE DATABASE_DEFAULT)
			,CurrencyType = COALESCE(t.CurrencyType COLLATE DATABASE_DEFAULT, s.CurrencyType COLLATE DATABASE_DEFAULT)
			,MeasureType = COALESCE(t.MeasureType COLLATE DATABASE_DEFAULT, s.MeasureType COLLATE DATABASE_DEFAULT)
			,Operation = CASE WHEN t.MeasureCode IS NULL THEN 'I' WHEN s.DataHash IS NULL THEN 'D' WHEN t.DataHash != s.DataHash AND t.DataHashType1 != s.DataHashType1 THEN 'U' WHEN t.DataHash != s.DataHash THEN '2' ELSE '1' END
		FROM (
			SELECT t.*
			FROM assumed.DimMeasure t
			WHERE t.EndDate = '31 Dec 9999'
			) t
		FULL JOIN #DimMeasure s
			ON s.MeasureCode = t.MeasureCode COLLATE DATABASE_DEFAULT
			AND s.Entity = t.Entity COLLATE DATABASE_DEFAULT
			AND s.Business = t.Business COLLATE DATABASE_DEFAULT
			AND s.CurrencyType = t.CurrencyType COLLATE DATABASE_DEFAULT
			AND s.MeasureType = t.MeasureType COLLATE DATABASE_DEFAULT
		WHERE t.DataHash IS NULL
			OR s.DataHash IS NULL
			OR t.DataHashType1 IS NULL
			OR s.DataHashType1 IS NULL
			OR t.DataHash != s.DataHash
			OR t.DataHashType1 != s.DataHashType1

		BEGIN TRAN

		UPDATE t
		SET UpdateDate = p.NewStartDate
			,MeasureName = s.MeasureName
			,DataHashType1 = s.DataHashType1
		FROM assumed.DimMeasure t
		INNER JOIN #LoadOperation lo
			ON COALESCE(lo.MeasureCode, '^&*') = COALESCE(t.MeasureCode, '^&*')
			AND COALESCE(lo.Entity, '^&*') = COALESCE(t.Entity, '^&*')
			AND COALESCE(lo.Business, '^&*') = COALESCE(t.Business, '^&*')
			AND COALESCE(lo.CurrencyType, '^&*') = COALESCE(t.CurrencyType, '^&*')
			AND COALESCE(lo.MeasureType, '^&*') = COALESCE(t.MeasureType, '^&*')
			AND lo.Operation IN ('U', '1')
		INNER JOIN #DimMeasure s
			ON COALESCE(s.MeasureCode, '^&*') = COALESCE(t.MeasureCode, '^&*')
			AND COALESCE(s.Entity, '^&*') = COALESCE(t.Entity, '^&*')
			AND COALESCE(s.Business, '^&*') = COALESCE(t.Business, '^&*')
			AND COALESCE(s.CurrencyType, '^&*') = COALESCE(t.CurrencyType, '^&*')
			AND COALESCE(s.MeasureType, '^&*') = COALESCE(t.MeasureType, '^&*')
		CROSS JOIN #Parameters p
		WHERE p.NewStartDate BETWEEN t.StartDate AND t.EndDate

		UPDATE t
		SET EndDate = p.ClosingEndDate
		FROM assumed.DimMeasure t
		INNER JOIN #LoadOperation lo
			ON lo.MeasureCode = t.MeasureCode
			AND lo.Entity = t.Entity
			AND lo.Business = t.Business
			AND lo.CurrencyType = t.CurrencyType
			AND lo.MeasureType = t.MeasureType
			AND lo.Operation IN ('U', '2')
		CROSS JOIN #Parameters p
		WHERE t.EndDate = '31 Dec 9999'

		INSERT INTO assumed.DimMeasure
			(StartDate
			,MeasureCode
			,Entity
			,Business
			,CurrencyType
			,MeasureType
			,RevenueCode
			,MeasureName
			,DataHash
			,DataHashType1
			)
		SELECT StartDate = p.NewStartDate
			,s.MeasureCode
			,s.Entity
			,s.Business
			,s.CurrencyType
			,s.MeasureType
			,s.RevenueCode
			,s.MeasureName
			,s.DataHash
			,s.DataHashType1
		FROM #DimMeasure s
		INNER JOIN #LoadOperation lo
			ON lo.MeasureCode = s.MeasureCode COLLATE DATABASE_DEFAULT
			AND lo.Entity = s.Entity COLLATE DATABASE_DEFAULT
			AND lo.Business = s.Business COLLATE DATABASE_DEFAULT
			AND lo.CurrencyType = s.CurrencyType COLLATE DATABASE_DEFAULT
			AND lo.MeasureType = s.MeasureType COLLATE DATABASE_DEFAULT
			AND lo.Operation IN ('I', 'U', '2')
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
