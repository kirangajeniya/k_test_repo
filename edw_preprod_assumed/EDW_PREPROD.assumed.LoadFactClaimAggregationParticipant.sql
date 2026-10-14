-- Database: EDW_PREPROD
-- Schema: assumed
-- Procedure: LoadFactClaimAggregationParticipant

CREATE   PROCEDURE assumed.LoadFactClaimAggregationParticipant
@fullLoad BIT = 0
AS
BEGIN
	BEGIN TRY
		/*
		assumed.LoadFactClaimAggregationParticipant 1

		DECLARE @fullLoad BIT = 0
		--*/

		DROP TABLE IF EXISTS #Parameters

		SELECT IncrementalLoad = ~@fullLoad & CAST(COALESCE((SELECT TOP 1 1 FROM assumed.FactClaimAggregationParticipant), 0) AS BIT)
			,LatestCreatedDate = (SELECT MAX(CreatedDate) FROM assumed.FactClaimAggregationParticipant)
			,LatestSourceCreatedDate = (SELECT MAX(CreatedDate) FROM assumed.FactClaim)
			,ProcessingStart = SYSDATETIME()
		INTO #Parameters

		DROP TABLE IF EXISTS #Filter

		SELECT dap.DimAccountingPeriodID
		INTO #Filter
		FROM assumed.DimAccountingPeriod dap
		INNER JOIN #Parameters prm
			ON prm.IncrementalLoad = 0
		UNION
		SELECT DISTINCT DimAccountingPeriodID = fc.Actual_DimAccountingPeriodID
		FROM assumed.FactClaim fc
		INNER JOIN #Parameters prm
			ON prm.IncrementalLoad = 1
			AND prm.LatestCreatedDate <= fc.CreatedDate
			AND prm.LatestSourceCreatedDate > prm.LatestCreatedDate

		BEGIN TRANSACTION

		IF (SELECT IncrementalLoad FROM #Parameters) = 1
		BEGIN
			DELETE fcap
			FROM assumed.FactClaimAggregationParticipant fcap
			INNER JOIN #Filter f
				ON f.DimAccountingPeriodID = fcap.Actual_DimAccountingPeriodID
		END
		ELSE
		BEGIN
			TRUNCATE TABLE assumed.FactClaimAggregationParticipant
		END

		INSERT INTO assumed.FactClaimAggregationParticipant
			(DimContractID
			,Ceded_DimContractID
			,DimClaimTransactionID
			,DimParticipantID
			,Actual_DimAccountingPeriodID
			,DimAccidentYearID
			,Intended_DimAccountingID
			,DimAdjustmentTypeID
			,DimLineOfBusinessID
			,Orig_DimCurrencyID
			,Settl_DimCurrencyID
			,OrigRpt1_DimExchangeRateID
			,OrigRpt2_DimExchangeRateID
			,SettlRpt1_DimExchangeRateID
			,SettlRpt2_DimExchangeRateID
			,CreatedDate
			,ID
			,TIRS_UW_ASSM_CEDED_NAME
			,SUMMABLE_LOSS_PAID
			,SUMMABLE_LOSS_PAID_USD
			,SUMMABLE_LOSS_EXP_PAID
			,SUMMABLE_LOSS_EXP_PAID_USD
			,SUMMABLE_LAE
			,SUMMABLE_LAE_USD
			,SUMMABLE_CASH_LOSS_ADV_AMT
			,SUMMABLE_CASH_LOSS_ADV_AMT_USD
			,SUMMABLE_CASH_LOSS_REFUND
			,SUMMABLE_CASH_LOSS_REFUND_USD
			,SUMMABLE_OS_LOSS
			,SUMMABLE_OS_LOSS_EXP
			,SUMMABLE_OS_LOSS_USD
			,SUMMABLE_OS_LOSS_EXP_USD
			,SUMMABLE_Ceded_LOSS_PAID
			,SUMMABLE_Ceded_LOSS_PAID_USD
			,SUMMABLE_Ceded_LOSS_EXP_PAID
			,SUMMABLE_Ceded_LOSS_EXP_PAID_USD
			,SUMMABLE_Ceded_LAE
			,SUMMABLE_Ceded_LAE_USD
			,SUMMABLE_Ceded_CASH_LOSS_ADV_AMT
			,SUMMABLE_Ceded_CASH_LOSS_ADV_AMT_USD
			,SUMMABLE_Ceded_CASH_LOSS_REFUND
			,SUMMABLE_Ceded_CASH_LOSS_REFUND_USD
			,SUMMABLE_Ceded_OS_LOSS
			,SUMMABLE_Ceded_OS_LOSS_EXP
			,SUMMABLE_Ceded_OS_LOSS_USD
			,SUMMABLE_Ceded_OS_LOSS_EXP_USD
			,SUMMABLE_funds_released_losses
			,SUMMABLE_funds_released_losses_USD
			,SUMMABLE_CEDED_funds_released_losses
			,SUMMABLE_CEDED_funds_released_losses_USD
			,SUMMABLE_reinstatement_premium
			,SUMMABLE_reinstatement_premium_USD
			,SUMMABLE_CEDED_reinstatement_premium
			,SUMMABLE_CEDED_reinstatement_premium_USD
			,SUMMABLE_SETTL_LOSS_PAID
			,SUMMABLE_SETTL_LAE
			,DAILY_MOVEMENT_LOSS_PAID
			,DAILY_MOVEMENT_LOSS_PAID_USD
			,DAILY_MOVEMENT_LAE
			,DAILY_MOVEMENT_LAE_USD
			,DAILY_MOVEMENT_CASH_LOSS_ADV_AMT
			,DAILY_MOVEMENT_CASH_LOSS_ADV_AMT_USD
			,DAILY_MOVEMENT_CASH_LOSS_REFUND
			,DAILY_MOVEMENT_CASH_LOSS_REFUND_USD
			,DAILY_MOVEMENT_OS_LOSS
			,DAILY_MOVEMENT_OS_LOSS_USD
			,DAILY_MOVEMENT_OS_LOSS_EXP
			,DAILY_MOVEMENT_OS_LOSS_EXP_USD
			)
		SELECT lc.DimContractID
			,lc.Ceded_DimContractID
			,lc.DimClaimTransactionID
			,lc.DimParticipantID
			,lc.Actual_DimAccountingPeriodID
			,lc.DimAccidentYearID
			,lc.Intended_DimAccountingID
			,lc.DimAdjustmentTypeID
			,lc.DimLineOfBusinessID
			,lc.Orig_DimCurrencyID
			,lc.Settl_DimCurrencyID
			,lc.OrigRpt1_DimExchangeRateID
			,lc.OrigRpt2_DimExchangeRateID
			,lc.SettlRpt1_DimExchangeRateID
			,lc.SettlRpt2_DimExchangeRateID
			,CreatedDate = MAX(lc.CreatedDate)
			,ID = MIN(lc.FactClaimID)
			,TIRS_UW_ASSM_CEDED_NAME = CASE WHEN dm.Business = 'RI Assumed' THEN 'Assumed' WHEN dm.Business = 'RI Ceded' THEN 'Ceded' END
			,SUMMABLE_LOSS_PAID = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_LOSS_PAID' THEN lc.Amount ELSE 0 END)
			,SUMMABLE_LOSS_PAID_USD = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_LOSS_PAID' THEN lc.AmountUSD ELSE 0 END)
			,SUMMABLE_LOSS_EXP_PAID = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_LOSS_EXP_PAID' THEN lc.Amount ELSE 0 END)
			,SUMMABLE_LOSS_EXP_PAID_USD = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_LOSS_EXP_PAID' THEN lc.AmountUSD ELSE 0 END)
			,SUMMABLE_LAE = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_LAE' THEN lc.Amount ELSE 0 END)
			,SUMMABLE_LAE_USD = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_LAE' THEN lc.AmountUSD ELSE 0 END)
			,SUMMABLE_CASH_LOSS_ADV_AMT = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CASH_LOSS_ADV_AMT' THEN lc.Amount ELSE 0 END)
			,SUMMABLE_CASH_LOSS_ADV_AMT_USD = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CASH_LOSS_ADV_AMT' THEN lc.AmountUSD ELSE 0 END)
			,SUMMABLE_CASH_LOSS_REFUND = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CASH_LOSS_REFUND' THEN lc.Amount ELSE 0 END)
			,SUMMABLE_CASH_LOSS_REFUND_USD = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CASH_LOSS_REFUND' THEN lc.AmountUSD ELSE 0 END)
			,SUMMABLE_OS_LOSS = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_OS_LOSS' THEN lc.Amount ELSE 0 END)
			,SUMMABLE_OS_LOSS_EXP = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_OS_LOSS_EXP' THEN lc.Amount ELSE 0 END)
			,SUMMABLE_OS_LOSS_USD = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_OS_LOSS' THEN lc.AmountUSD ELSE 0 END)
			,SUMMABLE_OS_LOSS_EXP_USD = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_OS_LOSS_EXP' THEN lc.AmountUSD ELSE 0 END)
			,SUMMABLE_Ceded_LOSS_PAID = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_LOSS_PAID' THEN lc.Amount ELSE 0 END)
			,SUMMABLE_Ceded_LOSS_PAID_USD = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_LOSS_PAID' THEN lc.AmountUSD ELSE 0 END)
			,SUMMABLE_Ceded_LOSS_EXP_PAID = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_LOSS_EXP_PAID' THEN lc.Amount ELSE 0 END)
			,SUMMABLE_Ceded_LOSS_EXP_PAID_USD = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_LOSS_EXP_PAID' THEN lc.AmountUSD ELSE 0 END)
			,SUMMABLE_Ceded_LAE = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_LAE' THEN lc.Amount ELSE 0 END)
			,SUMMABLE_Ceded_LAE_USD = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_LAE' THEN lc.AmountUSD ELSE 0 END)
			,SUMMABLE_Ceded_CASH_LOSS_ADV_AMT = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_CASH_LOSS_ADV_AMT' THEN lc.Amount ELSE 0 END)
			,SUMMABLE_Ceded_CASH_LOSS_ADV_AMT_USD = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_CASH_LOSS_ADV_AMT' THEN lc.AmountUSD ELSE 0 END)
			,SUMMABLE_Ceded_CASH_LOSS_REFUND = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_CASH_LOSS_REFUND' THEN lc.Amount ELSE 0 END)
			,SUMMABLE_Ceded_CASH_LOSS_REFUND_USD = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_CASH_LOSS_REFUND' THEN lc.AmountUSD ELSE 0 END)
			,SUMMABLE_Ceded_OS_LOSS = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_OS_LOSS' THEN lc.Amount ELSE 0 END)
			,SUMMABLE_Ceded_OS_LOSS_EXP = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_OS_LOSS_EXP' THEN lc.Amount ELSE 0 END)
			,SUMMABLE_Ceded_OS_LOSS_USD = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_OS_LOSS' THEN lc.AmountUSD ELSE 0 END)
			,SUMMABLE_Ceded_OS_LOSS_EXP_USD = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_OS_LOSS_EXP' THEN lc.AmountUSD ELSE 0 END)
			,SUMMABLE_funds_released_losses = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_FUNDS_RELEASED_LOSSES' THEN lc.Amount ELSE 0 END)
			,SUMMABLE_funds_released_losses_USD = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_FUNDS_RELEASED_LOSSES' THEN lc.AmountUSD ELSE 0 END)
			,SUMMABLE_CEDED_funds_released_losses = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_FUNDS_RELEASED_LOSSES' THEN lc.Amount ELSE 0 END)
			,SUMMABLE_CEDED_funds_released_losses_USD = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_FUNDS_RELEASED_LOSSES' THEN lc.AmountUSD ELSE 0 END)
			,SUMMABLE_reinstatement_premium = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_REINSTATEMENT_PREMIUM' THEN lc.Amount ELSE 0 END)
			,SUMMABLE_reinstatement_premium_USD = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_REINSTATEMENT_PREMIUM' THEN lc.AmountUSD ELSE 0 END)
			,SUMMABLE_CEDED_reinstatement_premium = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_REINSTATEMENT_PREMIUM' THEN lc.Amount ELSE 0 END)
			,SUMMABLE_CEDED_reinstatement_premium_USD = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_REINSTATEMENT_PREMIUM' THEN lc.AmountUSD ELSE 0 END)
			,SUMMABLE_SETTL_LOSS_PAID = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_SETTL_LOSS_PAID' THEN lc.Amount ELSE 0 END)
			,SUMMABLE_SETTL_LAE = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_SETTL_LAE' THEN lc.Amount ELSE 0 END)
			,DAILY_MOVEMENT_LOSS_PAID = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_LOSS_PAID' AND CAST(lc.CreatedDate AS DATE) = lp.LatestProcessingDate THEN lc.Amount ELSE 0 END)
			,DAILY_MOVEMENT_LOSS_PAID_USD = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_LOSS_PAID' AND CAST(lc.CreatedDate AS DATE) = lp.LatestProcessingDate THEN lc.AmountUSD ELSE 0 END)
			,DAILY_MOVEMENT_LAE = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_LAE' AND CAST(lc.CreatedDate AS DATE) = lp.LatestProcessingDate THEN lc.Amount ELSE 0 END)
			,DAILY_MOVEMENT_LAE_USD = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_LAE' AND CAST(lc.CreatedDate AS DATE) = lp.LatestProcessingDate THEN lc.AmountUSD ELSE 0 END)
			,DAILY_MOVEMENT_CASH_LOSS_ADV_AMT = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CASH_LOSS_ADV_AMT' AND CAST(lc.CreatedDate AS DATE) = lp.LatestProcessingDate THEN lc.Amount ELSE 0 END)
			,DAILY_MOVEMENT_CASH_LOSS_ADV_AMT_USD = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CASH_LOSS_ADV_AMT' AND CAST(lc.CreatedDate AS DATE) = lp.LatestProcessingDate THEN lc.AmountUSD ELSE 0 END)
			,DAILY_MOVEMENT_CASH_LOSS_REFUND = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CASH_LOSS_REFUND' AND CAST(lc.CreatedDate AS DATE) = lp.LatestProcessingDate THEN lc.Amount ELSE 0 END)
			,DAILY_MOVEMENT_CASH_LOSS_REFUND_USD = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CASH_LOSS_REFUND' AND CAST(lc.CreatedDate AS DATE) = lp.LatestProcessingDate THEN lc.AmountUSD ELSE 0 END)
			,DAILY_MOVEMENT_OS_LOSS = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_OS_LOSS' AND CAST(lc.CreatedDate AS DATE) = lp.LatestProcessingDate THEN lc.Amount ELSE 0 END)
			,DAILY_MOVEMENT_OS_LOSS_USD = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_OS_LOSS' AND CAST(lc.CreatedDate AS DATE) = lp.LatestProcessingDate THEN lc.AmountUSD ELSE 0 END)
			,DAILY_MOVEMENT_OS_LOSS_EXP = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_OS_LOSS_EXP' AND CAST(lc.CreatedDate AS DATE) = lp.LatestProcessingDate THEN lc.Amount ELSE 0 END)
			,DAILY_MOVEMENT_OS_LOSS_EXP_USD = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_OS_LOSS_EXP' AND CAST(lc.CreatedDate AS DATE) = lp.LatestProcessingDate THEN lc.AmountUSD ELSE 0 END)
		FROM EDW_PREPROD.assumed.FactClaim lc
		INNER JOIN #Filter f
			ON f.DimAccountingPeriodID = lc.Actual_DimAccountingPeriodID
		CROSS JOIN (
			SELECT LatestProcessingDate = CAST(MAX(fc.CreatedDate) AS DATE)
			FROM EDW_PREPROD.assumed.FactClaim fc
			) lp
		INNER JOIN EDW_PREPROD.assumed.DimMeasure dm
			ON dm.DimMeasureID = lc.DimMeasureID
		INNER JOIN (
			VALUES('SUMMABLE_LOSS_PAID', 'Claim', 'RI Assumed', 'Original', 'Loss Paid')
				,('SUMMABLE_LOSS_EXP_PAID', 'Claim', 'RI Assumed', 'Original', 'Loss Expense Paid')
				,('SUMMABLE_LAE', 'Claim', 'RI Assumed', 'Original', 'Loss Adjustment Expense')
				,('SUMMABLE_CASH_LOSS_ADV_AMT', 'Claim', 'RI Assumed', 'Original', 'Cash Loss Advance')
				,('SUMMABLE_CASH_LOSS_REFUND', 'Claim', 'RI Assumed', 'Original', 'Cash Loss Refund')
				,('SUMMABLE_FUNDS_RELEASED_LOSSES', 'Claim', 'RI Assumed', 'Original', 'Funds Released Losses')
				,('SUMMABLE_REINSTATEMENT_PREMIUM', 'Claim', 'RI Assumed', 'Original', 'Reinstatement Premium')
				,('SUMMABLE_OS_LOSS', 'Claim', 'RI Assumed', 'Original', 'Outstanding Loss')
				,('SUMMABLE_OS_LOSS_EXP', 'Claim', 'RI Assumed', 'Original', 'Outstanding Loss Expense')
				,('SUMMABLE_CEDED_LOSS_PAID', 'Claim', 'RI Ceded', 'Original', 'Loss Paid')
				,('SUMMABLE_CEDED_LOSS_EXP_PAID', 'Claim', 'RI Ceded', 'Original', 'Loss Expense Paid')
				,('SUMMABLE_CEDED_LAE', 'Claim', 'RI Ceded', 'Original', 'Loss Adjustment Expense')
				,('SUMMABLE_CEDED_CASH_LOSS_ADV_AMT', 'Claim', 'RI Ceded', 'Original', 'Cash Loss Advance')
				,('SUMMABLE_CEDED_CASH_LOSS_REFUND', 'Claim', 'RI Ceded', 'Original', 'Cash Loss Refund')
				,('SUMMABLE_CEDED_FUNDS_RELEASED_LOSSES', 'Claim', 'RI Ceded', 'Original', 'Funds Released Losses')
				,('SUMMABLE_CEDED_OS_LOSS', 'Claim', 'RI Ceded', 'Original', 'Outstanding Loss')
				,('SUMMABLE_CEDED_OS_LOSS_EXP', 'Claim', 'RI Ceded', 'Original', 'Outstanding Loss Expense')
				,('SUMMABLE_CEDED_REINSTATEMENT_PREMIUM', 'Claim', 'RI Ceded', 'Original', 'Reinstatement Premium')
				,('SUMMABLE_SETTL_LOSS_PAID', 'Claim', 'RI Assumed', 'Settlement', 'Loss Paid')
				,('SUMMABLE_SETTL_LAE', 'Claim', 'RI Assumed', 'Settlement', 'Loss Adjustment Expense')
		
				,('FIRV_IBNR_BEGIN','Claim','RI Assumed', 'Original', 'FIRV IBNR Begin')
				,('FIRV_IBNR_END','Claim','RI Assumed', 'Original', 'FIRV IBNR End')
				,('CEDED_FIRV_IBNR_BEGIN','Claim','RI Ceded','Original','FIRV IBNR Begin')
				,('CEDED_FIRV_IBNR_END','Claim','RI Ceded','Original','FIRV IBNR End')
		
		) mm (MappedMeasure, Entity, Business, CurrencyType, MeasureType)
			ON mm.Entity = dm.Entity
			AND mm.Business = dm.Business
			AND mm.CurrencyType = dm.CurrencyType
			AND mm.MeasureType = dm.MeasureType
		GROUP BY lc.DimContractID
			,lc.Ceded_DimContractID
			,lc.DimClaimTransactionID
			,lc.DimParticipantID
			,lc.Actual_DimAccountingPeriodID
			,lc.DimAccidentYearID
			,lc.Intended_DimAccountingID
			,lc.DimAdjustmentTypeID
			,lc.DimLineOfBusinessID
			,lc.Orig_DimCurrencyID
			,lc.Settl_DimCurrencyID
			,lc.OrigRpt1_DimExchangeRateID
			,lc.OrigRpt2_DimExchangeRateID
			,lc.SettlRpt1_DimExchangeRateID
			,lc.SettlRpt2_DimExchangeRateID
			,dm.Business
			,lc.CreatedDate
		OPTION (MAXDOP 1)

		DECLARE @RowsProcessed BIGINT = @@ROWCOUNT

		COMMIT

		DECLARE @ProcessName VARCHAR(100) = OBJECT_SCHEMA_NAME(@@PROCID) + '.' + OBJECT_NAME(@@PROCID)
		DECLARE @LastIdentity BIGINT = SCOPE_IDENTITY()
		DECLARE @ProcessingStarted DATETIME = (SELECT p.ProcessingStart FROM #Parameters p)
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
		DECLARE @ProcessingStartedC DATETIME = (SELECT p.ProcessingStart FROM #Parameters p)
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
