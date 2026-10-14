-- Database: EDW_PREPROD
-- Schema: assumed
-- Procedure: LoadFactClaimAggregation

CREATE   PROCEDURE  [assumed].[LoadFactClaimAggregation]
	@FullReload BIT = 0  
AS
BEGIN


    BEGIN TRY
	DECLARE
        @v_start_date		DATETIME = GETDATE(),
		@row_count			BIGINT = 0
		
		BEGIN TRANSACTION

		IF @FullReload = 1 OR NOT EXISTS (SELECT TOP 1 1 FROM [assumed].[FactClaim_Aggregation])
		BEGIN

		TRUNCATE TABLE [assumed].[FactClaim_Aggregation]	
		
		SELECT ID = MIN(lc.FactClaimID)
		,lc.DimContractID
		,lc.Ceded_DimContractID
		,lc.DimClaimTransactionID
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
		,FIRV_IBNR_BEGIN =  SUM(CASE WHEN mm.MappedMeasure = 'FIRV_IBNR_BEGIN' THEN lc.Amount ELSE 0 END)
		,FIRV_IBNR_END =  SUM(CASE WHEN mm.MappedMeasure = 'FIRV_IBNR_END' THEN lc.Amount ELSE 0 END)
		,CEDED_FIRV_IBNR_BEGIN =  SUM(CASE WHEN mm.MappedMeasure = 'CEDED_FIRV_IBNR_BEGIN' THEN lc.Amount ELSE 0 END)
		,CEDED_FIRV_IBNR_END =  SUM(CASE WHEN mm.MappedMeasure = 'CEDED_FIRV_IBNR_END' THEN lc.Amount ELSE 0 END)		
		,FIRV_IBNR_BEGIN_USD =  SUM(CASE WHEN mm.MappedMeasure = 'FIRV_IBNR_BEGIN' THEN lc.AmountUSD ELSE 0 END)
		,FIRV_IBNR_END_USD =  SUM(CASE WHEN mm.MappedMeasure = 'FIRV_IBNR_END' THEN lc.AmountUSD ELSE 0 END)
		,CEDED_FIRV_IBNR_BEGIN_USD =  SUM(CASE WHEN mm.MappedMeasure = 'CEDED_FIRV_IBNR_BEGIN' THEN lc.AmountUSD ELSE 0 END)
		,CEDED_FIRV_IBNR_END_USD =  SUM(CASE WHEN mm.MappedMeasure = 'CEDED_FIRV_IBNR_END' THEN lc.AmountUSD ELSE 0 END)		
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
		,CreatedDate = MAX(lc.CreatedDate)
	into #FullLoad
	FROM EDW_PREPROD.assumed.FactClaim lc WITH (NOLOCK)
	CROSS JOIN (
		SELECT LatestProcessingDate = CAST(MAX(fc.CreatedDate) AS DATE)
		FROM EDW_PREPROD.assumed.FactClaim fc WITH (NOLOCK)
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
	  	  	
			
		

  INSERT INTO [assumed].[FactClaim_Aggregation]
	  (ID
	  ,[DimContractID]
      ,[Ceded_DimContractID]
      ,[DimClaimTransactionID]
      ,[Actual_DimAccountingPeriodID]
      ,[DimAccidentYearID]
      ,[Intended_DimAccountingID]
      ,[DimAdjustmentTypeID]
      ,[DimLineOfBusinessID]
      ,[Orig_DimCurrencyID]
      ,[Settl_DimCurrencyID]
      ,[OrigRpt1_DimExchangeRateID]
      ,[OrigRpt2_DimExchangeRateID]
      ,[SettlRpt1_DimExchangeRateID]
      ,[SettlRpt2_DimExchangeRateID]
      ,[TIRS_UW_ASSM_CEDED_NAME]
      ,[Summable_LOSS_PAID]
      ,[SUMMABLE_LOSS_PAID_USD]
      ,[SUMMABLE_LOSS_EXP_PAID]
      ,[SUMMABLE_LOSS_EXP_PAID_USD]
      ,[SUMMABLE_LAE]
      ,[SUMMABLE_LAE_USD]
      ,[SUMMABLE_CASH_LOSS_ADV_AMT]
      ,[SUMMABLE_CASH_LOSS_ADV_AMT_USD]
      ,[SUMMABLE_CASH_LOSS_REFUND]
      ,[SUMMABLE_CASH_LOSS_REFUND_USD]
      ,[SUMMABLE_funds_released_losses]
      ,[SUMMABLE_funds_released_losses_USD]
      ,[SUMMABLE_reinstatement_premium]
      ,[SUMMABLE_reinstatement_premium_USD]
      ,[SUMMABLE_OS_LOSS]
      ,[SUMMABLE_OS_LOSS_EXP]
      ,[SUMMABLE_OS_LOSS_USD]
      ,[SUMMABLE_OS_LOSS_EXP_USD]
      ,[Summable_Ceded_LOSS_PAID]
      ,[SUMMABLE_Ceded_LOSS_PAID_USD]
      ,[SUMMABLE_Ceded_LOSS_EXP_PAID]
      ,[SUMMABLE_Ceded_LOSS_EXP_PAID_USD]
      ,[SUMMABLE_Ceded_LAE]
      ,[SUMMABLE_Ceded_LAE_USD]
      ,[SUMMABLE_Ceded_CASH_LOSS_ADV_AMT]
      ,[SUMMABLE_Ceded_CASH_LOSS_ADV_AMT_USD]
      ,[SUMMABLE_Ceded_CASH_LOSS_REFUND]
      ,[SUMMABLE_Ceded_CASH_LOSS_REFUND_USD]
      ,[SUMMABLE_Ceded_funds_released_losses]
      ,[SUMMABLE_Ceded_funds_released_losses_USD]
      ,[SUMMABLE_Ceded_OS_LOSS]
      ,[SUMMABLE_Ceded_OS_LOSS_EXP]
      ,[SUMMABLE_Ceded_OS_LOSS_USD]
      ,[SUMMABLE_Ceded_OS_LOSS_EXP_USD]
      ,[SUMMABLE_Ceded_reinstatement_premium]
      ,[SUMMABLE_Ceded_reinstatement_premium_USD]
      ,[FIRV_IBNR_Begin]
      ,[Ceded_FIRV_IBNR_Begin]
      ,[FIRV_IBNR_End]
      ,[Ceded_FIRV_IBNR_End]
      ,[FIRV_IBNR_Begin_USD]
      ,[Ceded_FIRV_IBNR_Begin_USD]
      ,[FIRV_IBNR_End_USD]
      ,[Ceded_FIRV_IBNR_End_USD]
      ,[Summable_SETTL_LOSS_PAID]
      ,[Summable_SETTL_LAE]
      ,[DAILY_MOVEMENT_LOSS_PAID]
      ,[DAILY_MOVEMENT_LOSS_PAID_USD]
      ,[DAILY_MOVEMENT_LAE]
      ,[DAILY_MOVEMENT_LAE_USD]
      ,[DAILY_MOVEMENT_CASH_LOSS_ADV_AMT]
      ,[DAILY_MOVEMENT_CASH_LOSS_ADV_AMT_USD]
      ,[DAILY_MOVEMENT_CASH_LOSS_REFUND]
      ,[DAILY_MOVEMENT_CASH_LOSS_REFUND_USD]
      ,[DAILY_MOVEMENT_OS_LOSS]
      ,[DAILY_MOVEMENT_OS_LOSS_USD]
      ,[DAILY_MOVEMENT_OS_LOSS_EXP]
      ,[DAILY_MOVEMENT_OS_LOSS_EXP_USD]
      ,[CreatedDate]
      ,[LoadDate])

	SELECT ID
	  ,[DimContractID]
      ,[Ceded_DimContractID]
      ,[DimClaimTransactionID]
      ,[Actual_DimAccountingPeriodID]
      ,[DimAccidentYearID]
      ,[Intended_DimAccountingID]
      ,[DimAdjustmentTypeID]
      ,[DimLineOfBusinessID]
      ,[Orig_DimCurrencyID]
      ,[Settl_DimCurrencyID]
      ,[OrigRpt1_DimExchangeRateID]
      ,[OrigRpt2_DimExchangeRateID]
      ,[SettlRpt1_DimExchangeRateID]
      ,[SettlRpt2_DimExchangeRateID]
      ,[TIRS_UW_ASSM_CEDED_NAME]
      ,[Summable_LOSS_PAID]
      ,[SUMMABLE_LOSS_PAID_USD]
      ,[SUMMABLE_LOSS_EXP_PAID]
      ,[SUMMABLE_LOSS_EXP_PAID_USD]
      ,[SUMMABLE_LAE]
      ,[SUMMABLE_LAE_USD]
      ,[SUMMABLE_CASH_LOSS_ADV_AMT]
      ,[SUMMABLE_CASH_LOSS_ADV_AMT_USD]
      ,[SUMMABLE_CASH_LOSS_REFUND]
      ,[SUMMABLE_CASH_LOSS_REFUND_USD]
      ,[SUMMABLE_funds_released_losses]
      ,[SUMMABLE_funds_released_losses_USD]
      ,[SUMMABLE_reinstatement_premium]
      ,[SUMMABLE_reinstatement_premium_USD]
      ,[SUMMABLE_OS_LOSS]
      ,[SUMMABLE_OS_LOSS_EXP]
      ,[SUMMABLE_OS_LOSS_USD]
      ,[SUMMABLE_OS_LOSS_EXP_USD]
      ,[Summable_Ceded_LOSS_PAID]
      ,[SUMMABLE_Ceded_LOSS_PAID_USD]
      ,[SUMMABLE_Ceded_LOSS_EXP_PAID]
      ,[SUMMABLE_Ceded_LOSS_EXP_PAID_USD]
      ,[SUMMABLE_Ceded_LAE]
      ,[SUMMABLE_Ceded_LAE_USD]
      ,[SUMMABLE_Ceded_CASH_LOSS_ADV_AMT]
      ,[SUMMABLE_Ceded_CASH_LOSS_ADV_AMT_USD]
      ,[SUMMABLE_Ceded_CASH_LOSS_REFUND]
      ,[SUMMABLE_Ceded_CASH_LOSS_REFUND_USD]
      ,[SUMMABLE_Ceded_funds_released_losses]
      ,[SUMMABLE_Ceded_funds_released_losses_USD]
      ,[SUMMABLE_Ceded_OS_LOSS]
      ,[SUMMABLE_Ceded_OS_LOSS_EXP]
      ,[SUMMABLE_Ceded_OS_LOSS_USD]
      ,[SUMMABLE_Ceded_OS_LOSS_EXP_USD]
      ,[SUMMABLE_Ceded_reinstatement_premium]
      ,[SUMMABLE_Ceded_reinstatement_premium_USD]
      ,[FIRV_IBNR_Begin]
      ,[Ceded_FIRV_IBNR_Begin]
      ,[FIRV_IBNR_End]
      ,[Ceded_FIRV_IBNR_End]
      ,[FIRV_IBNR_Begin_USD]
      ,[Ceded_FIRV_IBNR_Begin_USD]
      ,[FIRV_IBNR_End_USD]
      ,[Ceded_FIRV_IBNR_End_USD]
      ,[Summable_SETTL_LOSS_PAID]
      ,[Summable_SETTL_LAE]
      ,[DAILY_MOVEMENT_LOSS_PAID]
      ,[DAILY_MOVEMENT_LOSS_PAID_USD]
      ,[DAILY_MOVEMENT_LAE]
      ,[DAILY_MOVEMENT_LAE_USD]
      ,[DAILY_MOVEMENT_CASH_LOSS_ADV_AMT]
      ,[DAILY_MOVEMENT_CASH_LOSS_ADV_AMT_USD]
      ,[DAILY_MOVEMENT_CASH_LOSS_REFUND]
      ,[DAILY_MOVEMENT_CASH_LOSS_REFUND_USD]
      ,[DAILY_MOVEMENT_OS_LOSS]
      ,[DAILY_MOVEMENT_OS_LOSS_USD]
      ,[DAILY_MOVEMENT_OS_LOSS_EXP]
      ,[DAILY_MOVEMENT_OS_LOSS_EXP_USD]
      ,[CreatedDate]
	  ,LoadDate = CAST(GETDATE() AS DATETIME) 	
	FROM #FullLoad
						
			
SET @row_count = @row_count+ROWCOUNT_BIG();	

			END
			 ELSE
					BEGIN


		   	  										-- Delete old data for last 2 months
										DELETE fa  FROM EDW_PREPROD.[assumed].[FactClaim_Aggregation] fa
										JOIN EDW_PREPROD.assumed.DimAccountingPeriod dap ON 
										fa.[Actual_DimAccountingPeriodID] = DAP.[DimAccountingPeriodID]
											--INNER JOIN EDW_PREPROD.assumed.DimMeasure dm
											--ON dm.DimMeasureID =fa.DimMeasureID
										WHERE dap.AccountingPeriodDate >= DATEADD(MONTH, -2, CAST(GETDATE() AS DATE));


										SELECT ID = MIN(lc.FactClaimID)
											,lc.DimContractID
											,lc.Ceded_DimContractID
											,lc.DimClaimTransactionID
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
											,FIRV_IBNR_BEGIN =  SUM(CASE WHEN mm.MappedMeasure = 'FIRV_IBNR_BEGIN' THEN lc.Amount ELSE 0 END)
											,FIRV_IBNR_END =  SUM(CASE WHEN mm.MappedMeasure = 'FIRV_IBNR_END' THEN lc.Amount ELSE 0 END)
											,CEDED_FIRV_IBNR_BEGIN =  SUM(CASE WHEN mm.MappedMeasure = 'CEDED_FIRV_IBNR_BEGIN' THEN lc.Amount ELSE 0 END)
											,CEDED_FIRV_IBNR_END =  SUM(CASE WHEN mm.MappedMeasure = 'CEDED_FIRV_IBNR_END' THEN lc.Amount ELSE 0 END)		
											,FIRV_IBNR_BEGIN_USD =  SUM(CASE WHEN mm.MappedMeasure = 'FIRV_IBNR_BEGIN' THEN lc.AmountUSD ELSE 0 END)
											,FIRV_IBNR_END_USD =  SUM(CASE WHEN mm.MappedMeasure = 'FIRV_IBNR_END' THEN lc.AmountUSD ELSE 0 END)
											,CEDED_FIRV_IBNR_BEGIN_USD =  SUM(CASE WHEN mm.MappedMeasure = 'CEDED_FIRV_IBNR_BEGIN' THEN lc.AmountUSD ELSE 0 END)
											,CEDED_FIRV_IBNR_END_USD =  SUM(CASE WHEN mm.MappedMeasure = 'CEDED_FIRV_IBNR_END' THEN lc.AmountUSD ELSE 0 END)		
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
											,CreatedDate = MAX(lc.CreatedDate)
											,LoadDate = CAST(GETDATE() AS DATETIME) 	
											into #IncrementalLoad
										FROM EDW_PREPROD.assumed.FactClaim lc WITH (NOLOCK)

										CROSS JOIN (
											SELECT LatestProcessingDate = CAST(MAX(fc.CreatedDate) AS DATE)
											FROM EDW_PREPROD.assumed.FactClaim fc WITH (NOLOCK)
											) lp
										INNER JOIN EDW_PREPROD.assumed.DimMeasure dm
											ON dm.DimMeasureID = lc.DimMeasureID
										INNER JOIN EDW_PREPROD.assumed.DimAccountingPeriod dap ON 
												lc.[Actual_DimAccountingPeriodID] = DAP.[DimAccountingPeriodID]
												--AND dap.AccountingPeriodDate >= DATEADD(MONTH, -2, CAST(GETDATE() AS DATE))
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
												where  dap.AccountingPeriodDate >= DATEADD(MONTH, -2, CAST(GETDATE() AS DATE))
															--WHERE lc.CreatedDate >= DATEADD(MONTH, -2, GETDATE())
												GROUP BY lc.DimContractID
													,lc.Ceded_DimContractID
													,lc.DimClaimTransactionID
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
													
											 -- Insert last 2 months data
			
										 INSERT INTO [assumed].[FactClaim_Aggregation]
											  (ID
										  ,[DimContractID]
										  ,[Ceded_DimContractID]
										  ,[DimClaimTransactionID]
										  ,[Actual_DimAccountingPeriodID]
										  ,[DimAccidentYearID]
										  ,[Intended_DimAccountingID]
										  ,[DimAdjustmentTypeID]
										  ,[DimLineOfBusinessID]
										  ,[Orig_DimCurrencyID]
										  ,[Settl_DimCurrencyID]
										  ,[OrigRpt1_DimExchangeRateID]
										  ,[OrigRpt2_DimExchangeRateID]
										  ,[SettlRpt1_DimExchangeRateID]
										  ,[SettlRpt2_DimExchangeRateID]
										  ,[TIRS_UW_ASSM_CEDED_NAME]
										  ,[Summable_LOSS_PAID]
										  ,[SUMMABLE_LOSS_PAID_USD]
										  ,[SUMMABLE_LOSS_EXP_PAID]
										  ,[SUMMABLE_LOSS_EXP_PAID_USD]
										  ,[SUMMABLE_LAE]
										  ,[SUMMABLE_LAE_USD]
										  ,[SUMMABLE_CASH_LOSS_ADV_AMT]
										  ,[SUMMABLE_CASH_LOSS_ADV_AMT_USD]
										  ,[SUMMABLE_CASH_LOSS_REFUND]
										  ,[SUMMABLE_CASH_LOSS_REFUND_USD]
										  ,[SUMMABLE_funds_released_losses]
										  ,[SUMMABLE_funds_released_losses_USD]
										  ,[SUMMABLE_reinstatement_premium]
										  ,[SUMMABLE_reinstatement_premium_USD]
										  ,[SUMMABLE_OS_LOSS]
										  ,[SUMMABLE_OS_LOSS_EXP]
										  ,[SUMMABLE_OS_LOSS_USD]
										  ,[SUMMABLE_OS_LOSS_EXP_USD]
										  ,[Summable_Ceded_LOSS_PAID]
										  ,[SUMMABLE_Ceded_LOSS_PAID_USD]
										  ,[SUMMABLE_Ceded_LOSS_EXP_PAID]
										  ,[SUMMABLE_Ceded_LOSS_EXP_PAID_USD]
										  ,[SUMMABLE_Ceded_LAE]
										  ,[SUMMABLE_Ceded_LAE_USD]
										  ,[SUMMABLE_Ceded_CASH_LOSS_ADV_AMT]
										  ,[SUMMABLE_Ceded_CASH_LOSS_ADV_AMT_USD]
										  ,[SUMMABLE_Ceded_CASH_LOSS_REFUND]
										  ,[SUMMABLE_Ceded_CASH_LOSS_REFUND_USD]
										  ,[SUMMABLE_Ceded_funds_released_losses]
										  ,[SUMMABLE_Ceded_funds_released_losses_USD]
										  ,[SUMMABLE_Ceded_OS_LOSS]
										  ,[SUMMABLE_Ceded_OS_LOSS_EXP]
										  ,[SUMMABLE_Ceded_OS_LOSS_USD]
										  ,[SUMMABLE_Ceded_OS_LOSS_EXP_USD]
										  ,[SUMMABLE_Ceded_reinstatement_premium]
										  ,[SUMMABLE_Ceded_reinstatement_premium_USD]
										  ,[FIRV_IBNR_Begin]
										  ,[Ceded_FIRV_IBNR_Begin]
										  ,[FIRV_IBNR_End]
										  ,[Ceded_FIRV_IBNR_End]
										  ,[FIRV_IBNR_Begin_USD]
										  ,[Ceded_FIRV_IBNR_Begin_USD]
										  ,[FIRV_IBNR_End_USD]
										  ,[Ceded_FIRV_IBNR_End_USD]
										  ,[Summable_SETTL_LOSS_PAID]
										  ,[Summable_SETTL_LAE]
										  ,[DAILY_MOVEMENT_LOSS_PAID]
										  ,[DAILY_MOVEMENT_LOSS_PAID_USD]
										  ,[DAILY_MOVEMENT_LAE]
										  ,[DAILY_MOVEMENT_LAE_USD]
										  ,[DAILY_MOVEMENT_CASH_LOSS_ADV_AMT]
										  ,[DAILY_MOVEMENT_CASH_LOSS_ADV_AMT_USD]
										  ,[DAILY_MOVEMENT_CASH_LOSS_REFUND]
										  ,[DAILY_MOVEMENT_CASH_LOSS_REFUND_USD]
										  ,[DAILY_MOVEMENT_OS_LOSS]
										  ,[DAILY_MOVEMENT_OS_LOSS_USD]
										  ,[DAILY_MOVEMENT_OS_LOSS_EXP]
										  ,[DAILY_MOVEMENT_OS_LOSS_EXP_USD]
										  ,[CreatedDate]
										  ,[LoadDate])


										  
										  SELECT ID
										  ,[DimContractID]
										  ,[Ceded_DimContractID]
										  ,[DimClaimTransactionID]
										  ,[Actual_DimAccountingPeriodID]
										  ,[DimAccidentYearID]
										  ,[Intended_DimAccountingID]
										  ,[DimAdjustmentTypeID]
										  ,[DimLineOfBusinessID]
										  ,[Orig_DimCurrencyID]
										  ,[Settl_DimCurrencyID]
										  ,[OrigRpt1_DimExchangeRateID]
										  ,[OrigRpt2_DimExchangeRateID]
										  ,[SettlRpt1_DimExchangeRateID]
										  ,[SettlRpt2_DimExchangeRateID]
										  ,[TIRS_UW_ASSM_CEDED_NAME]
										  ,[Summable_LOSS_PAID]
										  ,[SUMMABLE_LOSS_PAID_USD]
										  ,[SUMMABLE_LOSS_EXP_PAID]
										  ,[SUMMABLE_LOSS_EXP_PAID_USD]
										  ,[SUMMABLE_LAE]
										  ,[SUMMABLE_LAE_USD]
										  ,[SUMMABLE_CASH_LOSS_ADV_AMT]
										  ,[SUMMABLE_CASH_LOSS_ADV_AMT_USD]
										  ,[SUMMABLE_CASH_LOSS_REFUND]
										  ,[SUMMABLE_CASH_LOSS_REFUND_USD]
										  ,[SUMMABLE_funds_released_losses]
										  ,[SUMMABLE_funds_released_losses_USD]
										  ,[SUMMABLE_reinstatement_premium]
										  ,[SUMMABLE_reinstatement_premium_USD]
										  ,[SUMMABLE_OS_LOSS]
										  ,[SUMMABLE_OS_LOSS_EXP]
										  ,[SUMMABLE_OS_LOSS_USD]
										  ,[SUMMABLE_OS_LOSS_EXP_USD]
										  ,[Summable_Ceded_LOSS_PAID]
										  ,[SUMMABLE_Ceded_LOSS_PAID_USD]
										  ,[SUMMABLE_Ceded_LOSS_EXP_PAID]
										  ,[SUMMABLE_Ceded_LOSS_EXP_PAID_USD]
										  ,[SUMMABLE_Ceded_LAE]
										  ,[SUMMABLE_Ceded_LAE_USD]
										  ,[SUMMABLE_Ceded_CASH_LOSS_ADV_AMT]
										  ,[SUMMABLE_Ceded_CASH_LOSS_ADV_AMT_USD]
										  ,[SUMMABLE_Ceded_CASH_LOSS_REFUND]
										  ,[SUMMABLE_Ceded_CASH_LOSS_REFUND_USD]
										  ,[SUMMABLE_Ceded_funds_released_losses]
										  ,[SUMMABLE_Ceded_funds_released_losses_USD]
										  ,[SUMMABLE_Ceded_OS_LOSS]
										  ,[SUMMABLE_Ceded_OS_LOSS_EXP]
										  ,[SUMMABLE_Ceded_OS_LOSS_USD]
										  ,[SUMMABLE_Ceded_OS_LOSS_EXP_USD]
										  ,[SUMMABLE_Ceded_reinstatement_premium]
										  ,[SUMMABLE_Ceded_reinstatement_premium_USD]
										  ,[FIRV_IBNR_Begin]
										  ,[Ceded_FIRV_IBNR_Begin]
										  ,[FIRV_IBNR_End]
										  ,[Ceded_FIRV_IBNR_End]
										  ,[FIRV_IBNR_Begin_USD]
										  ,[Ceded_FIRV_IBNR_Begin_USD]
										  ,[FIRV_IBNR_End_USD]
										  ,[Ceded_FIRV_IBNR_End_USD]
										  ,[Summable_SETTL_LOSS_PAID]
										  ,[Summable_SETTL_LAE]
										  ,[DAILY_MOVEMENT_LOSS_PAID]
										  ,[DAILY_MOVEMENT_LOSS_PAID_USD]
										  ,[DAILY_MOVEMENT_LAE]
										  ,[DAILY_MOVEMENT_LAE_USD]
										  ,[DAILY_MOVEMENT_CASH_LOSS_ADV_AMT]
										  ,[DAILY_MOVEMENT_CASH_LOSS_ADV_AMT_USD]
										  ,[DAILY_MOVEMENT_CASH_LOSS_REFUND]
										  ,[DAILY_MOVEMENT_CASH_LOSS_REFUND_USD]
										  ,[DAILY_MOVEMENT_OS_LOSS]
										  ,[DAILY_MOVEMENT_OS_LOSS_USD]
										  ,[DAILY_MOVEMENT_OS_LOSS_EXP]
										  ,[DAILY_MOVEMENT_OS_LOSS_EXP_USD]
										  ,[CreatedDate]
										  ,LoadDate = CAST(GETDATE() AS DATETIME) 	
										  FROM #IncrementalLoad									  
									
			SET @row_count = @row_count+ROWCOUNT_BIG();	
			END

	        COMMIT
	       	DECLARE @ProcessName		VARCHAR(100)= OBJECT_SCHEMA_NAME(@@PROCID) + '.' + OBJECT_NAME(@@PROCID)
			DECLARE @LastIdentity		BIGINT		= SCOPE_IDENTITY()
			DECLARE @ProcessingStarted	DATETIME	= @v_start_date
			DECLARE @ProcessingEnded	DATETIME	= GETDATE()
			DECLARE @SourceDataDate		DATETIME	= (SELECT [sql_date] FROM ETL.dbo.[day] WHERE today = 1)
			DECLARE @RowsProcessed		BIGINT		= @row_count
			DECLARE @ps_comment			VARCHAR(100)= NULL;
	        EXEC ETL.dbo.update_etl_controller @ps_process_name = @ProcessName,
	                                           @pn_rows_processed = @RowsProcessed,
	                                           @pdt_data_datetime = @SourceDataDate,
	                                           @pdt_process_start_datetime = @ProcessingStarted,
	                                           @pdt_process_end_datetime = @ProcessingEnded,
	                                           @pn_error_number = 0,
	                                           @ps_comment = NULL,
	                                           @pn_max_processed_event_id = @LastIdentity
	    
		
		END TRY
		
	    BEGIN CATCH
	        IF @@TRANCOUNT > 0
	        BEGIN
	            ROLLBACK
	        END
	        DECLARE @ErrorDescription VARCHAR(8000)
	            = CONCAT(
	                        'Error: ',
	                        ERROR_NUMBER(),
	                        ' - ',
	                        ERROR_MESSAGE(),
	                        '; ',
	                        'Occurred in procedure: ' + ERROR_PROCEDURE() + ', ',
	                        'Line ',
	                        ERROR_LINE()
	                    )
	        DECLARE @ErrorNumber INT = ERROR_NUMBER()
	        DECLARE @ErrorMessage VARCHAR(8000) = ERROR_MESSAGE()
	        DECLARE @ErrorSeverity INT = ERROR_SEVERITY()
	        DECLARE @ErrorState INT = ERROR_STATE()
	        DECLARE @ProcessNameC VARCHAR(100) = OBJECT_SCHEMA_NAME(@@PROCID) + '.' + OBJECT_NAME(@@PROCID)
	        DECLARE @ProcessingStartedC	DATETIME	= @v_start_date
	        DECLARE @ProcessingEndedC DATETIME = GETDATE()
	        DECLARE @SourceDataDateC DATETIME = (
	                                                SELECT [sql_date] FROM ETL.dbo.[day] WHERE today = 1
	                                            )
	        EXEC ETL.dbo.update_etl_controller @ps_process_name = @ProcessNameC,
	                                           @pn_rows_processed = 0,
	                                           @pdt_data_datetime = @SourceDataDateC,
	                                           @pdt_process_start_datetime = @ProcessingStartedC,
	                                           @pdt_process_end_datetime = @ProcessingEndedC,
	                                           @pn_error_number = @ErrorNumber,
	                                           @ps_comment = @ErrorDescription,
	                                           @pn_max_processed_event_id = 0
	        EXEC ETL.dbo.insert_error_log @process_name = @ProcessNameC,
	                                      @object_name = 0,
	                                      @user_message = @ErrorDescription,
	                                      @status = 0,
	                                      @remedy = 'Contact EDW team'
	        RAISERROR(@ErrorMessage, @ErrorSeverity, @ErrorState)
    END CATCH
END

 
