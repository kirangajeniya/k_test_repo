-- Database: EDW_PREPROD
-- Schema: assumed
-- Procedure: LoadFactUnderwritingAggregationParticipant

CREATE   PROCEDURE assumed.LoadFactUnderwritingAggregationParticipant
@fullLoad BIT = 0
AS
BEGIN
	BEGIN TRY
		/*
		DECLARE @fullLoad BIT = 0
		--*/

		DROP TABLE IF EXISTS #Parameters

		SELECT IncrementalLoad = ~@fullLoad & CAST(COALESCE((SELECT TOP 1 1 FROM assumed.FactUnderwritingAggregationParticipant), 0) AS BIT)
			,LatestCreatedDate = (SELECT MAX(CreatedDate) FROM assumed.FactUnderwritingAggregationParticipant)
			,ProcessingStart = SYSDATETIME()
		INTO #Parameters

		DROP TABLE IF EXISTS #Filter

		SELECT dap.DimAccountingPeriodID
		INTO #Filter
		FROM assumed.DimAccountingPeriod dap
		INNER JOIN #Parameters prm
			ON prm.IncrementalLoad = 0
		UNION
		SELECT DISTINCT DimAccountingPeriodID = fu.Actual_DimAccountingPeriodID
		FROM assumed.FactUnderwriting fu
		INNER JOIN #Parameters prm
			ON prm.IncrementalLoad = 1
			AND prm.LatestCreatedDate < fu.CreatedDate

		BEGIN TRANSACTION

		IF (SELECT IncrementalLoad FROM #Parameters) = 1
		BEGIN
			DELETE fuap
			FROM assumed.FactUnderwritingAggregationParticipant fuap
			INNER JOIN #Filter f
				ON f.DimAccountingPeriodID = fuap.Actual_DimAccountingPeriodID
		END
		ELSE
		BEGIN
			TRUNCATE TABLE assumed.FactUnderwritingAggregationParticipant
		END

		INSERT INTO assumed.FactUnderwritingAggregationParticipant
			(ID
			,DimContractID
			,Ceded_DimContractID
			,Actual_DimAccountingPeriodID
			,Intended_DimAccountingID
			,DimAdjustmentTypeID
			,Orig_DimCurrencyID
			,DimLineOfBusinessID
			,DimParticipantID
			,OrigRpt1_DimExchangeRateID
			,OrigRpt2_DimExchangeRateID
			,SourceSystemKey
			,CreatedDate
			,TIRS_UW_ASSM_CEDED_NAME
			,SUMMABLE_WRTN_PREM_ALL_DOC_TYPES
			,SUMMABLE_WRTN_PREM_ALL_DOC_TYPES_USD
			,SUMMABLE_WRTN_PREM_No_Claims_Rebate
			,SUMMABLE_WRTN_PREM_No_Claims_Rebate_USD
			,SUMMABLE_WRTN_PREM_Reinstatement_Premium
			,SUMMABLE_WRTN_PREM_Reinstatement_Premium_USD
			,SUMMABLE_UEPR
			,SUMMABLE_UEPR_USD
			,SUMMABLE_CEDED_WRTN_PREM_ALL_DOC_TYPES
			,SUMMABLE_CEDED_WRTN_PREM_ALL_DOC_TYPES_USD
			,SUMMABLE_CEDED_WRTN_PREM_No_Claims_Rebate
			,SUMMABLE_CEDED_WRTN_PREM_No_Claims_Rebate_USD
			,SUMMABLE_CEDED_WRTN_PREM_Reinstatement_Premium
			,SUMMABLE_CEDED_WRTN_PREM_Reinstatement_Premium_USD
			,SUMMABLE_CEDED_UEPR
			,SUMMABLE_Brokerage
			,SUMMABLE_Brokerage_USD
			,SUMMABLE_Commission
			,SUMMABLE_Commission_USD
			,SUMMABLE_tax_nonrefund
			,SUMMABLE_tax_nonrefund_USD
			,SUMMABLE_tax_on_prem
			,SUMMABLE_tax_on_prem_USD
			,SUMMABLE_Tax_refund
			,SUMMABLE_Tax_refund_USD
			,SUMMABLE_CEDED_Brokerage
			,SUMMABLE_CEDED_Brokerage_USD
			,SUMMABLE_CEDED_Commission
			,SUMMABLE_CEDED_Commission_USD
			,SUMMABLE_CEDED_tax_nonrefund
			,SUMMABLE_CEDED_tax_nonrefund_USD
			,SUMMABLE_CEDED_tax_on_prem
			,SUMMABLE_CEDED_tax_on_prem_USD
			,SUMMABLE_CEDED_Tax_refund
			,SUMMABLE_CEDED_Tax_refund_USD
			,SUMMABLE_DAC
			,SUMMABLE_CEDED_DAC
			,SUMMABLE_Profit_Commission_Paid
			,SUMMABLE_Profit_Commission_Paid_USD
			,SUMMABLE_CEDED_Profit_Commission_Paid
			,SUMMABLE_CEDED_Profit_Commission_Paid_USD
			,SUMMABLE_Sliding_Scale_Commission
			,SUMMABLE_Sliding_Scale_Commission_USD
			,SUMMABLE_CEDED_Sliding_Scale_Commission
			,SUMMABLE_CEDED_Sliding_Scale_Commission_USD
			,SUMMABLE_Overrider_Commission
			,SUMMABLE_Overrider_Commission_USD
			,SUMMABLE_CEDED_Overrider_Commission
			,SUMMABLE_CEDED_Overrider_Commission_USD
			,SUMMABLE_Provisional_Commission
			,SUMMABLE_Provisional_Commission_USD
			,SUMMABLE_CEDED_Provisional_Commission
			,SUMMABLE_CEDED_Provisional_Commission_USD
			,SUMMABLE_Deferred_Commission
			,SUMMABLE_Deferred_Commission_USD
			,SUMMABLE_CEDED_Deferred_Commission
			,SUMMABLE_CEDED_Deferred_Commission_USD
			,SUMMABLE_int_funds_gross
			,SUMMABLE_int_funds_gross_USD
			,SUMMABLE_CEDED_int_funds_gross
			,SUMMABLE_CEDED_int_funds_gross_USD
			,SUMMABLE_int_funds_wth
			,SUMMABLE_int_funds_wth_USD
			,SUMMABLE_CEDED_int_funds_wth
			,SUMMABLE_CEDED_int_funds_wth_USD
			,SUMMABLE_fire_prevent_fund
			,SUMMABLE_fire_prevent_fund_USD
			,SUMMABLE_CEDED_fire_prevent_fund
			,SUMMABLE_CEDED_fire_prevent_fund_USD
			,SUMMABLE_xch_diff
			,SUMMABLE_xch_diff_USD
			,SUMMABLE_CEDED_xch_diff
			,SUMMABLE_CEDED_xch_diff_USD
			,SUMMABLE_NO_CLM_RBT
			,SUMMABLE_NO_CLM_RBT_USD
			,SUMMABLE_CEDED_NO_CLM_RBT
			,SUMMABLE_CEDED_NO_CLM_RBT_USD
			,SUMMABLE_UEPR_RPT_CURR1
			,SUMMABLE_UEPR_RPT_CURR2
			,SUMMABLE_DAC_RPT_CURR1
			,SUMMABLE_DAC_RPT_CURR2
			,SUMMABLE_funds_withheld_premium
			,SUMMABLE_funds_withheld_premium_USD
			,SUMMABLE_funds_released_premium
			,SUMMABLE_funds_released_premium_USD
			,SUMMABLE_funds_withheld_losses
			,SUMMABLE_funds_withheld_losses_USD
			,SUMMABLE_deferred_withheld
			,SUMMABLE_deferred_withheld_USD
			,SUMMABLE_deferred_released
			,SUMMABLE_deferred_released_USD
			,SUMMABLE_CEDED_funds_withheld_premium
			,SUMMABLE_CEDED_funds_withheld_premium_USD
			,SUMMABLE_CEDED_funds_released_premium
			,SUMMABLE_CEDED_funds_released_premium_USD
			,SUMMABLE_CEDED_funds_withheld_losses
			,SUMMABLE_CEDED_funds_withheld_losses_USD
			,SUMMABLE_CEDED_deferred_withheld
			,SUMMABLE_CEDED_deferred_withheld_USD
			,SUMMABLE_CEDED_deferred_released
			,SUMMABLE_CEDED_deferred_released_USD
			,SUMMABLE_CEDED_UEPR_USD
			,SUMMABLE_DAC_USD
			,SUMMABLE_CEDED_DAC_USD
			)
		SELECT MIN(f.FactUnderwritingID) ID,
			f.DimContractID,
			f.Ceded_DimContractID,
			f.Actual_DimAccountingPeriodID,
			f.Intended_DimAccountingID,
			f.DimAdjustmentTypeID,
			f.Orig_DimCurrencyID,
			f.DimLineOfBusinessID,
			f.DimParticipantID,
			f.OrigRpt1_DimExchangeRateID,
			f.OrigRpt2_DimExchangeRateID,
			SourceSystemKey = MAX(f.SourceSystemKey),
			CreatedDate = MAX(f.CreatedDate),
			TIRS_UW_ASSM_CEDED_NAME = CASE WHEN dm.Business = 'RI Assumed' THEN 'Assumed' WHEN dm.Business = 'RI Ceded' THEN 'Ceded' END,
			SUMMABLE_WRTN_PREM_ALL_DOC_TYPES = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_WRTN_PREM_ALL_DOC_TYPES' THEN f.Amount ELSE 0 END),
			SUMMABLE_WRTN_PREM_ALL_DOC_TYPES_USD = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_WRTN_PREM_ALL_DOC_TYPES' THEN f.AmountUSD ELSE 0 END),
			SUMMABLE_WRTN_PREM_No_Claims_Rebate = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_WRTN_PREM_No_Claims_Rebate' THEN f.Amount ELSE 0 END),
			SUMMABLE_WRTN_PREM_No_Claims_Rebate_USD = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_WRTN_PREM_No_Claims_Rebate' THEN f.AmountUSD ELSE 0 END),
			SUMMABLE_WRTN_PREM_Reinstatement_Premium = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_WRTN_PREM_Reinstatement_Premium' THEN f.Amount ELSE 0 END),
			SUMMABLE_WRTN_PREM_Reinstatement_Premium_USD = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_WRTN_PREM_Reinstatement_Premium' THEN f.AmountUSD ELSE 0 END),
			SUMMABLE_UEPR = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_UEPR' THEN f.Amount ELSE 0 END),
			SUMMABLE_UEPR_USD = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_UEPR' THEN f.AmountUSD ELSE 0 END),
			SUMMABLE_CEDED_WRTN_PREM_ALL_DOC_TYPES = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_WRTN_PREM_ALL_DOC_TYPES' THEN f.Amount ELSE 0 END),
			SUMMABLE_CEDED_WRTN_PREM_ALL_DOC_TYPES_USD = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_WRTN_PREM_ALL_DOC_TYPES' THEN f.AmountUSD ELSE 0 END),
			SUMMABLE_CEDED_WRTN_PREM_No_Claims_Rebate = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_WRTN_PREM_No_Claims_Rebate' THEN f.Amount ELSE 0 END),
			SUMMABLE_CEDED_WRTN_PREM_No_Claims_Rebate_USD = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_WRTN_PREM_No_Claims_Rebate' THEN f.AmountUSD ELSE 0 END),
			SUMMABLE_CEDED_WRTN_PREM_Reinstatement_Premium = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_WRTN_PREM_Reinstatement_Premium' THEN f.Amount ELSE 0 END),
			SUMMABLE_CEDED_WRTN_PREM_Reinstatement_Premium_USD = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_WRTN_PREM_Reinstatement_Premium' THEN f.AmountUSD ELSE 0 END),
			SUMMABLE_CEDED_UEPR = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_UEPR' THEN f.Amount ELSE 0 END),
			SUMMABLE_Brokerage = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_Brokerage' THEN f.Amount ELSE 0 END),
			SUMMABLE_Brokerage_USD = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_Brokerage' THEN f.AmountUSD ELSE 0 END),
			SUMMABLE_Commission = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_Commission' THEN f.Amount ELSE 0 END),
			SUMMABLE_Commission_USD = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_Commission' THEN f.AmountUSD ELSE 0 END),
			SUMMABLE_tax_nonrefund = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_tax_nonrefund' THEN f.Amount ELSE 0 END),
			SUMMABLE_tax_nonrefund_USD = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_tax_nonrefund' THEN f.AmountUSD ELSE 0 END),
			SUMMABLE_tax_on_prem = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_tax_on_prem' THEN f.Amount ELSE 0 END),
			SUMMABLE_tax_on_prem_USD = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_tax_on_prem' THEN f.AmountUSD ELSE 0 END),
			SUMMABLE_Tax_refund = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_Tax_refund' THEN f.Amount ELSE 0 END),
			SUMMABLE_Tax_refund_USD = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_Tax_refund' THEN f.AmountUSD ELSE 0 END),
			SUMMABLE_CEDED_Brokerage = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_Brokerage' THEN f.Amount ELSE 0 END),
			SUMMABLE_CEDED_Brokerage_USD = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_Brokerage' THEN f.AmountUSD ELSE 0 END),
			SUMMABLE_CEDED_Commission = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_Commission' THEN f.Amount ELSE 0 END),
			SUMMABLE_CEDED_Commission_USD = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_Commission' THEN f.AmountUSD ELSE 0 END),
			SUMMABLE_CEDED_tax_nonrefund = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_tax_nonrefund' THEN f.Amount ELSE 0 END),
			SUMMABLE_CEDED_tax_nonrefund_USD = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_tax_nonrefund' THEN f.AmountUSD ELSE 0 END),
			SUMMABLE_CEDED_tax_on_prem = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_tax_on_prem' THEN f.Amount ELSE 0 END),
			SUMMABLE_CEDED_tax_on_prem_USD = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_tax_on_prem' THEN f.AmountUSD ELSE 0 END),
			SUMMABLE_CEDED_Tax_refund = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_Tax_refund' THEN f.Amount ELSE 0 END),
			SUMMABLE_CEDED_Tax_refund_USD = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_Tax_refund' THEN f.AmountUSD ELSE 0 END),
			SUMMABLE_DAC = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_DAC' THEN f.Amount ELSE 0 END),
			SUMMABLE_CEDED_DAC = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_DAC' THEN f.Amount ELSE 0 END),
			SUMMABLE_Profit_Commission_Paid = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_Profit_Commission_Paid' THEN f.Amount ELSE 0 END),
			SUMMABLE_Profit_Commission_Paid_USD = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_Profit_Commission_Paid' THEN f.AmountUSD ELSE 0 END),
			SUMMABLE_CEDED_Profit_Commission_Paid = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_Profit_Commission_Paid' THEN f.Amount ELSE 0 END),
			SUMMABLE_CEDED_Profit_Commission_Paid_USD = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_Profit_Commission_Paid' THEN f.AmountUSD ELSE 0 END),
			SUMMABLE_Sliding_Scale_Commission = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_Sliding_Scale_Commission' THEN f.Amount ELSE 0 END),
			SUMMABLE_Sliding_Scale_Commission_USD = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_Sliding_Scale_Commission' THEN f.AmountUSD ELSE 0 END),
			SUMMABLE_CEDED_Sliding_Scale_Commission = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_Sliding_Scale_Commission' THEN f.Amount ELSE 0 END),
			SUMMABLE_CEDED_Sliding_Scale_Commission_USD = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_Sliding_Scale_Commission' THEN f.AmountUSD ELSE 0 END),
			SUMMABLE_Overrider_Commission = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_Overrider_Commission' THEN f.Amount ELSE 0 END),
			SUMMABLE_Overrider_Commission_USD = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_Overrider_Commission' THEN f.AmountUSD ELSE 0 END),
			SUMMABLE_CEDED_Overrider_Commission = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_Overrider_Commission' THEN f.Amount ELSE 0 END),
			SUMMABLE_CEDED_Overrider_Commission_USD = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_Overrider_Commission' THEN f.AmountUSD ELSE 0 END),
			SUMMABLE_Provisional_Commission = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_Provisional_Commission' THEN f.Amount ELSE 0 END),
			SUMMABLE_Provisional_Commission_USD = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_Provisional_Commission' THEN f.AmountUSD ELSE 0 END),
			SUMMABLE_CEDED_Provisional_Commission = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_Provisional_Commission' THEN f.Amount ELSE 0 END),
			SUMMABLE_CEDED_Provisional_Commission_USD = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_Provisional_Commission' THEN f.AmountUSD ELSE 0 END),
			SUMMABLE_Deferred_Commission = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_Deferred_Commission' THEN f.Amount ELSE 0 END),
			SUMMABLE_Deferred_Commission_USD = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_Deferred_Commission' THEN f.AmountUSD ELSE 0 END),
			SUMMABLE_CEDED_Deferred_Commission = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_Deferred_Commission' THEN f.Amount ELSE 0 END),
			SUMMABLE_CEDED_Deferred_Commission_USD = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_Deferred_Commission' THEN f.AmountUSD ELSE 0 END),
			SUMMABLE_int_funds_gross = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_int_funds_gross' THEN f.Amount ELSE 0 END),
			SUMMABLE_int_funds_gross_USD = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_int_funds_gross' THEN f.AmountUSD ELSE 0 END),
			SUMMABLE_CEDED_int_funds_gross = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_int_funds_gross' THEN f.Amount ELSE 0 END),
			SUMMABLE_CEDED_int_funds_gross_USD = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_int_funds_gross' THEN f.AmountUSD ELSE 0 END),
			SUMMABLE_int_funds_wth = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_int_funds_wth' THEN f.Amount ELSE 0 END),
			SUMMABLE_int_funds_wth_USD = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_int_funds_wth' THEN f.AmountUSD ELSE 0 END),
			SUMMABLE_CEDED_int_funds_wth = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_int_funds_wth' THEN f.Amount ELSE 0 END),
			SUMMABLE_CEDED_int_funds_wth_USD = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_int_funds_wth' THEN f.AmountUSD ELSE 0 END),
			SUMMABLE_fire_prevent_fund = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_fire_prevent_fund' THEN f.Amount ELSE 0 END),
			SUMMABLE_fire_prevent_fund_USD = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_fire_prevent_fund' THEN f.AmountUSD ELSE 0 END),
			SUMMABLE_CEDED_fire_prevent_fund = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_fire_prevent_fund' THEN f.Amount ELSE 0 END),
			SUMMABLE_CEDED_fire_prevent_fund_USD = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_fire_prevent_fund' THEN f.AmountUSD ELSE 0 END),
			SUMMABLE_xch_diff = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_xch_diff' THEN f.Amount ELSE 0 END),
			SUMMABLE_xch_diff_USD = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_xch_diff' THEN f.AmountUSD ELSE 0 END),
			SUMMABLE_CEDED_xch_diff = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_xch_diff' THEN f.Amount ELSE 0 END),
			SUMMABLE_CEDED_xch_diff_USD = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_xch_diff' THEN f.AmountUSD ELSE 0 END),
			SUMMABLE_NO_CLM_RBT = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_NO_CLM_RBT' THEN f.Amount ELSE 0 END),
			SUMMABLE_NO_CLM_RBT_USD = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_NO_CLM_RBT' THEN f.AmountUSD ELSE 0 END),
			SUMMABLE_CEDED_NO_CLM_RBT = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_NO_CLM_RBT' THEN f.Amount ELSE 0 END),
			SUMMABLE_CEDED_NO_CLM_RBT_USD = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_NO_CLM_RBT' THEN f.AmountUSD ELSE 0 END),
			SUMMABLE_UEPR_RPT_CURR1 = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_UEPR_RPT_CURR1' THEN f.Amount ELSE 0 END),
			SUMMABLE_UEPR_RPT_CURR2 = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_UEPR_RPT_CURR2' THEN f.Amount ELSE 0 END),
			SUMMABLE_DAC_RPT_CURR1 = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_DAC_RPT_CURR1' THEN f.Amount ELSE 0 END), 
			SUMMABLE_DAC_RPT_CURR2 = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_DAC_RPT_CURR2' THEN f.Amount ELSE 0 END),
			SUMMABLE_funds_withheld_premium = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_funds_withheld_premium' THEN f.Amount ELSE 0 END),
			SUMMABLE_funds_withheld_premium_USD = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_funds_withheld_premium' THEN f.AmountUSD ELSE 0 END),
			SUMMABLE_funds_released_premium = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_funds_released_premium' THEN f.Amount ELSE 0 END),
			SUMMABLE_funds_released_premium_USD = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_funds_released_premium' THEN f.AmountUSD ELSE 0 END),
			SUMMABLE_funds_withheld_losses = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_funds_withheld_losses' THEN f.Amount ELSE 0 END),
			SUMMABLE_funds_withheld_losses_USD = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_funds_withheld_losses' THEN f.AmountUSD ELSE 0 END),
			SUMMABLE_deferred_withheld = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_deferred_withheld' THEN f.Amount ELSE 0 END),
			SUMMABLE_deferred_withheld_USD = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_deferred_withheld' THEN f.AmountUSD ELSE 0 END),
			SUMMABLE_deferred_released = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_deferred_released' THEN f.Amount ELSE 0 END),
			SUMMABLE_deferred_released_USD = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_deferred_released' THEN f.AmountUSD ELSE 0 END),
			SUMMABLE_CEDED_funds_withheld_premium = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_funds_withheld_premium' THEN f.Amount ELSE 0 END),
			SUMMABLE_CEDED_funds_withheld_premium_USD = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_funds_withheld_premium' THEN f.AmountUSD ELSE 0 END),
			SUMMABLE_CEDED_funds_released_premium = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_funds_released_premium' THEN f.Amount ELSE 0 END),
			SUMMABLE_CEDED_funds_released_premium_USD = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_funds_released_premium' THEN f.AmountUSD ELSE 0 END),
			SUMMABLE_CEDED_funds_withheld_losses = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_funds_withheld_losses' THEN f.Amount ELSE 0 END),
			SUMMABLE_CEDED_funds_withheld_losses_USD = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_funds_withheld_losses' THEN f.AmountUSD ELSE 0 END),
			SUMMABLE_CEDED_deferred_withheld = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_deferred_withheld' THEN f.Amount ELSE 0 END),
			SUMMABLE_CEDED_deferred_withheld_USD = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_deferred_withheld' THEN f.AmountUSD ELSE 0 END),
			SUMMABLE_CEDED_deferred_released = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_deferred_released' THEN f.Amount ELSE 0 END),
			SUMMABLE_CEDED_deferred_released_USD = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_deferred_released' THEN f.AmountUSD ELSE 0 END),
			SUMMABLE_CEDED_UEPR_USD = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_UEPR' THEN f.AmountUSD ELSE 0 END),
			SUMMABLE_DAC_USD = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_DAC' THEN f.AmountUSD ELSE 0 END),
			SUMMABLE_CEDED_DAC_USD = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_DAC' THEN f.AmountUSD ELSE 0 END)
		FROM assumed.FactUnderwriting f
		INNER JOIN #Filter flt
			ON flt.DimAccountingPeriodID = f.Actual_DimAccountingPeriodID
		LEFT JOIN assumed.DimMeasure dm
			ON dm.DimMeasureID = f.DimMeasureID
		LEFT JOIN (
			VALUES      ('RI Assumed', 'Original', 'Premium', 'SUMMABLE_WRTN_PREM_ALL_DOC_TYPES'),
						('RI Assumed', 'Original', 'Not used Atm ', 'SUMMABLE_WRTN_PREM_No_Claims_Rebate'),
						('RI Assumed', 'Original', 'Reinstatement Premium', 'SUMMABLE_WRTN_PREM_Reinstatement_Premium'),
						('RI Assumed', 'Original', 'UEPR', 'SUMMABLE_UEPR'),
						('RI Assumed', 'Original', 'Brokerage', 'SUMMABLE_Brokerage'),
						('RI Assumed', 'Original', 'Commission', 'SUMMABLE_Commission'),
						('RI Assumed', 'Original', 'Tax', 'SUMMABLE_tax_nonrefund'),
						('RI Assumed', 'Original', 'Tax', 'SUMMABLE_tax_on_prem'),
						('RI Assumed', 'Original', 'Tax', 'SUMMABLE_Tax_refund'),
						('RI Assumed', 'Original', 'DAC', 'SUMMABLE_DAC'),
						('RI Assumed', 'Original', 'Profit Commission Payable', 'SUMMABLE_Profit_Commission_Paid'),
						('RI Assumed', 'Original', 'Commission', 'SUMMABLE_Sliding_Scale_Commission'),
						('RI Assumed', 'Original', 'Commission', 'SUMMABLE_Overrider_Commission'),
						('RI Assumed', 'Original', 'Commission', 'SUMMABLE_Provisional_Commission'),
						('RI Assumed', 'Original', 'Commission', 'SUMMABLE_Deferred_Commission'),
						('RI Assumed', 'Original', 'Interest', 'SUMMABLE_int_funds_gross'),
						('RI Assumed', 'Original', 'Interest', 'SUMMABLE_int_funds_wth'),
						('RI Assumed', 'Original', 'Brokerage', 'SUMMABLE_fire_prevent_fund'),
						('RI Assumed', 'Original', 'Brokerage', 'SUMMABLE_xch_diff'),
						('RI Assumed', 'Original', 'Premium', 'SUMMABLE_NO_CLM_RBT'),
						('RI Assumed', 'Original', 'FundHeld_Premium', 'SUMMABLE_funds_withheld_premium'),
						--('RI Assumed', 'Original', 'FundHeld_Premium', 'SUMMABLE_FUNDS_RELEASED_LOSSES'),
						('RI Assumed', 'Original', 'FundHeld_Premium', 'SUMMABLE_funds_released_premium'),
						('RI Assumed', 'Original', 'FundHeld_Premium', 'SUMMABLE_funds_withheld_losses'),
						('RI Assumed', 'Original', 'FundHeld_Premium', 'SUMMABLE_deferred_withheld'),
						('RI Assumed', 'Original', 'FundHeld_Premium', 'SUMMABLE_deferred_released'),
						('RI Assumed', 'Original', 'Unknown', 'SUMMABLE_UEPR_RPT_CURR1'),
						('RI Assumed', 'Original', 'Unknown', 'SUMMABLE_UEPR_RPT_CURR2'),
						('RI Assumed', 'Original', 'Unknown', 'SUMMABLE_DAC_RPT_CURR1'),
						('RI Assumed', 'Original', 'Unknown', 'SUMMABLE_DAC_RPT_CURR2'),
						('RI Ceded', 'Original', 'Premium', 'SUMMABLE_CEDED_WRTN_PREM_ALL_DOC_TYPES'),
						('RI Ceded', 'Original', 'Not used Atm ', 'SUMMABLE_CEDED_WRTN_PREM_No_Claims_Rebate'),
						('RI Ceded', 'Original', 'Reinstatement Premium', 'SUMMABLE_CEDED_WRTN_PREM_Reinstatement_Premium'),
						('RI Ceded', 'Original', 'UEPR', 'SUMMABLE_CEDED_UEPR'),
						('RI Ceded', 'Original', 'Brokerage', 'SUMMABLE_CEDED_Brokerage'),
						('RI Ceded', 'Original', 'Commission', 'SUMMABLE_CEDED_Commission'),
						('RI Ceded', 'Original', 'Tax', 'SUMMABLE_CEDED_tax_nonrefund'),
						('RI Ceded', 'Original', 'Tax', 'SUMMABLE_CEDED_tax_on_prem'),
						('RI Ceded', 'Original', 'Tax', 'SUMMABLE_CEDED_Tax_refund'),
						('RI Ceded', 'Original', 'DAC', 'SUMMABLE_CEDED_DAC'),
						('RI Ceded', 'Original', 'Profit Commission Payable', 'SUMMABLE_CEDED_Profit_Commission_Paid'),
						('RI Ceded', 'Original', 'Commission', 'SUMMABLE_CEDED_Sliding_Scale_Commission'),
						('RI Ceded', 'Original', 'Commission', 'SUMMABLE_CEDED_Overrider_Commission'),
						('RI Ceded', 'Original', 'Commission', 'SUMMABLE_CEDED_Provisional_Commission'),
						('RI Ceded', 'Original', 'Commission', 'SUMMABLE_CEDED_Deferred_Commission'),
						('RI Ceded', 'Original', 'Interest', 'SUMMABLE_CEDED_int_funds_gross'),
						('RI Ceded', 'Original', 'Interest', 'SUMMABLE_CEDED_int_funds_wth'),
						('RI Ceded', 'Original', 'Brokerage', 'SUMMABLE_CEDED_fire_prevent_fund'),
						('RI Ceded', 'Original', 'Brokerage', 'SUMMABLE_CEDED_xch_diff'),
						('RI Ceded', 'Original', 'Premium', 'SUMMABLE_CEDED_NO_CLM_RBT'),
						('RI Ceded', 'Original', 'FundHeld_Premium', 'SUMMABLE_CEDED_funds_withheld_premium'),
						('RI Ceded', 'Original', 'FundHeld_Premium', 'SUMMABLE_CEDED_funds_released_premium'),
						--('RI Ceded', 'Original', 'FundHeld_Premium', 'SUMMABLE_FUNDS_RELEASED_LOSSES'),                    
						('RI Ceded', 'Original', 'FundHeld_Premium', 'SUMMABLE_CEDED_funds_withheld_losses'),
						('RI Ceded', 'Original', 'FundHeld_Premium', 'SUMMABLE_CEDED_deferred_withheld'),
						('RI Ceded', 'Original', 'FundHeld_Premium', 'SUMMABLE_CEDED_deferred_released')
			) mm(Business, CurrencyType, MeasureType, MappedMeasure)
			ON 'Premium' = dm.Entity
				AND mm.Business = dm.Business
				AND mm.CurrencyType = dm.CurrencyType
				AND mm.MeasureType = dm.MeasureType
				AND mm.MappedMeasure = dm.MeasureCode
		GROUP BY f.DimContractID,
			f.Ceded_DimContractID,
			f.Actual_DimAccountingPeriodID,
			f.Intended_DimAccountingID,
			f.DimAdjustmentTypeID,
			f.Orig_DimCurrencyID,
			f.DimLineOfBusinessID,
			f.OrigRpt1_DimExchangeRateID,
			f.OrigRpt2_DimExchangeRateID,
			f.DimParticipantID,
			dm.Business
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
