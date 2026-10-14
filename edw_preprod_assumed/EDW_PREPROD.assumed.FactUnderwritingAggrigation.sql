-- Database: EDW_PREPROD
-- Schema: assumed
-- Procedure: FactUnderwritingAggrigation

CREATE PROCEDURE assumed.FactUnderwritingAggrigation
as
DROP TABLE iF EXISTS assumed.FactUnderwritingAggrigation

 SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS [ID],
        [f].[DimContractID],
        [f].[Ceded_DimContractID],
        [f].[Actual_DimAccountingPeriodID],
        f.Intended_DimAccountingPeriodID,
        [f].[Intended_DimAccountingID],
        [f].[DimAdjustmentTypeID],
        [f].[Orig_DimCurrencyID],
        [f].[DimLineOfBusinessID],
        [f].[OrigRpt1_DimExchangeRateID],
        [f].[OrigRpt2_DimExchangeRateID],
        [TIRS_UW_ASSM_CEDED_NAME] = CASE WHEN dm.Business = 'RI Assumed' THEN 'Assumed' WHEN dm.Business = 'RI Ceded' THEN 'Ceded' END,
        [SUMMABLE_WRTN_PREM_ALL_DOC_TYPES] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_WRTN_PREM_ALL_DOC_TYPES' THEN f.Amount ELSE 0 END),
        [SUMMABLE_WRTN_PREM_ALL_DOC_TYPES_USD] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_WRTN_PREM_ALL_DOC_TYPES' THEN f.AmountUSD ELSE 0 END),
        [SUMMABLE_WRTN_PREM_No_Claims_Rebate] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_WRTN_PREM_No_Claims_Rebate' THEN f.Amount ELSE 0 END),
        [SUMMABLE_WRTN_PREM_No_Claims_Rebate_USD] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_WRTN_PREM_No_Claims_Rebate' THEN f.AmountUSD ELSE 0 END),
        [SUMMABLE_WRTN_PREM_Reinstatement_Premium] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_WRTN_PREM_Reinstatement_Premium' THEN f.Amount ELSE 0 END),
        [SUMMABLE_WRTN_PREM_Reinstatement_Premium_USD] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_WRTN_PREM_Reinstatement_Premium' THEN f.AmountUSD ELSE 0 END),
        [SUMMABLE_UEPR] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_UEPR' THEN f.Amount ELSE 0 END),
        [SUMMABLE_UEPR_USD] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_UEPR' THEN f.AmountUSD ELSE 0 END),
        [SUMMABLE_CEDED_WRTN_PREM_ALL_DOC_TYPES] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_WRTN_PREM_ALL_DOC_TYPES' THEN f.Amount ELSE 0 END),
        [SUMMABLE_CEDED_WRTN_PREM_ALL_DOC_TYPES_USD] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_WRTN_PREM_ALL_DOC_TYPES' THEN f.AmountUSD ELSE 0 END),
        [SUMMABLE_CEDED_WRTN_PREM_No_Claims_Rebate] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_WRTN_PREM_No_Claims_Rebate' THEN f.Amount ELSE 0 END),
        [SUMMABLE_CEDED_WRTN_PREM_No_Claims_Rebate_USD] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_WRTN_PREM_No_Claims_Rebate' THEN f.AmountUSD ELSE 0 END),
        [SUMMABLE_CEDED_WRTN_PREM_Reinstatement_Premium] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_WRTN_PREM_Reinstatement_Premium' THEN f.Amount ELSE 0 END),
        [SUMMABLE_CEDED_WRTN_PREM_Reinstatement_Premium_USD] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_WRTN_PREM_Reinstatement_Premium' THEN f.AmountUSD ELSE 0 END),
        [SUMMABLE_CEDED_UEPR] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_UEPR' THEN f.Amount ELSE 0 END),
        [SUMMABLE_Brokerage] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_Brokerage' THEN f.Amount ELSE 0 END),
        [SUMMABLE_Brokerage_USD] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_Brokerage' THEN f.AmountUSD ELSE 0 END),
        [SUMMABLE_Commission] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_Commission' THEN f.Amount ELSE 0 END),
        [SUMMABLE_Commission_USD] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_Commission' THEN f.AmountUSD ELSE 0 END),
        [SUMMABLE_tax_nonrefund] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_tax_nonrefund' THEN f.Amount ELSE 0 END),
        [SUMMABLE_tax_nonrefund_USD] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_tax_nonrefund' THEN f.AmountUSD ELSE 0 END),
        [SUMMABLE_tax_on_prem] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_tax_on_prem' THEN f.Amount ELSE 0 END),
        [SUMMABLE_tax_on_prem_USD] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_tax_on_prem' THEN f.AmountUSD ELSE 0 END),
        [SUMMABLE_Tax_refund] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_Tax_refund' THEN f.Amount ELSE 0 END),
        [SUMMABLE_Tax_refund_USD] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_Tax_refund' THEN f.AmountUSD ELSE 0 END),
        [SUMMABLE_CEDED_Brokerage] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_Brokerage' THEN f.Amount ELSE 0 END),
        [SUMMABLE_CEDED_Brokerage_USD] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_Brokerage' THEN f.AmountUSD ELSE 0 END),
        [SUMMABLE_CEDED_Commission] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_Commission' THEN f.Amount ELSE 0 END),
        [SUMMABLE_CEDED_Commission_USD] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_Commission' THEN f.AmountUSD ELSE 0 END),
        [SUMMABLE_CEDED_tax_nonrefund] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_tax_nonrefund' THEN f.Amount ELSE 0 END),
        [SUMMABLE_CEDED_tax_nonrefund_USD] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_tax_nonrefund' THEN f.AmountUSD ELSE 0 END),
        [SUMMABLE_CEDED_tax_on_prem] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_tax_on_prem' THEN f.Amount ELSE 0 END),
        [SUMMABLE_CEDED_tax_on_prem_USD] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_tax_on_prem' THEN f.AmountUSD ELSE 0 END),
        [SUMMABLE_CEDED_Tax_refund] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_Tax_refund' THEN f.Amount ELSE 0 END),
        [SUMMABLE_CEDED_Tax_refund_USD] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_Tax_refund' THEN f.AmountUSD ELSE 0 END),
        [SUMMABLE_DAC] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_DAC' THEN f.Amount ELSE 0 END),
        [SUMMABLE_CEDED_DAC] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_DAC' THEN f.Amount ELSE 0 END),
        [SUMMABLE_Profit_Commission_Paid] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_Profit_Commission_Paid' THEN f.Amount ELSE 0 END),
        [SUMMABLE_Profit_Commission_Paid_USD] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_Profit_Commission_Paid' THEN f.AmountUSD ELSE 0 END),
        [SUMMABLE_CEDED_Profit_Commission_Paid] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_Profit_Commission_Paid' THEN f.Amount ELSE 0 END),
        [SUMMABLE_CEDED_Profit_Commission_Paid_USD] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_Profit_Commission_Paid' THEN f.AmountUSD ELSE 0 END),
        [SUMMABLE_Sliding_Scale_Commission] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_Sliding_Scale_Commission' THEN f.Amount ELSE 0 END),
        [SUMMABLE_Sliding_Scale_Commission_USD] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_Sliding_Scale_Commission' THEN f.AmountUSD ELSE 0 END),
        [SUMMABLE_CEDED_Sliding_Scale_Commission] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_Sliding_Scale_Commission' THEN f.Amount ELSE 0 END),
        [SUMMABLE_CEDED_Sliding_Scale_Commission_USD] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_Sliding_Scale_Commission' THEN f.AmountUSD ELSE 0 END),
        [SUMMABLE_Overrider_Commission] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_Overrider_Commission' THEN f.Amount ELSE 0 END),
        [SUMMABLE_Overrider_Commission_USD] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_Overrider_Commission' THEN f.AmountUSD ELSE 0 END),
        [SUMMABLE_CEDED_Overrider_Commission] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_Overrider_Commission' THEN f.Amount ELSE 0 END),
        [SUMMABLE_CEDED_Overrider_Commission_USD] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_Overrider_Commission' THEN f.AmountUSD ELSE 0 END),
        [SUMMABLE_Provisional_Commission] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_Provisional_Commission' THEN f.Amount ELSE 0 END),
        [SUMMABLE_Provisional_Commission_USD] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_Provisional_Commission' THEN f.AmountUSD ELSE 0 END),
        [SUMMABLE_CEDED_Provisional_Commission] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_Provisional_Commission' THEN f.Amount ELSE 0 END),
        [SUMMABLE_CEDED_Provisional_Commission_USD] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_Provisional_Commission' THEN f.AmountUSD ELSE 0 END),
        [SUMMABLE_Deferred_Commission] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_Deferred_Commission' THEN f.Amount ELSE 0 END),
        [SUMMABLE_Deferred_Commission_USD] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_Deferred_Commission' THEN f.AmountUSD ELSE 0 END),
        [SUMMABLE_CEDED_Deferred_Commission] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_Deferred_Commission' THEN f.Amount ELSE 0 END),
        [SUMMABLE_CEDED_Deferred_Commission_USD] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_Deferred_Commission' THEN f.AmountUSD ELSE 0 END),
        [SUMMABLE_int_funds_gross] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_int_funds_gross' THEN f.Amount ELSE 0 END),
        [SUMMABLE_int_funds_gross_USD] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_int_funds_gross' THEN f.AmountUSD ELSE 0 END),
        [SUMMABLE_CEDED_int_funds_gross] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_int_funds_gross' THEN f.Amount ELSE 0 END),
        [SUMMABLE_CEDED_int_funds_gross_USD] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_int_funds_gross' THEN f.AmountUSD ELSE 0 END),
        [SUMMABLE_int_funds_wth] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_int_funds_wth' THEN f.Amount ELSE 0 END),
        [SUMMABLE_int_funds_wth_USD] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_int_funds_wth' THEN f.AmountUSD ELSE 0 END),
        [SUMMABLE_CEDED_int_funds_wth] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_int_funds_wth' THEN f.Amount ELSE 0 END),
        [SUMMABLE_CEDED_int_funds_wth_USD] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_int_funds_wth' THEN f.AmountUSD ELSE 0 END),
        [SUMMABLE_fire_prevent_fund] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_fire_prevent_fund' THEN f.Amount ELSE 0 END),
        [SUMMABLE_fire_prevent_fund_USD] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_fire_prevent_fund' THEN f.AmountUSD ELSE 0 END),
        [SUMMABLE_CEDED_fire_prevent_fund] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_fire_prevent_fund' THEN f.Amount ELSE 0 END),
        [SUMMABLE_CEDED_fire_prevent_fund_USD] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_fire_prevent_fund' THEN f.AmountUSD ELSE 0 END),
        [SUMMABLE_xch_diff] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_xch_diff' THEN f.Amount ELSE 0 END),
        [SUMMABLE_xch_diff_USD] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_xch_diff' THEN f.AmountUSD ELSE 0 END),
        [SUMMABLE_CEDED_xch_diff] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_xch_diff' THEN f.Amount ELSE 0 END),
        [SUMMABLE_CEDED_xch_diff_USD] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_xch_diff' THEN f.AmountUSD ELSE 0 END),
        [SUMMABLE_NO_CLM_RBT] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_NO_CLM_RBT' THEN f.Amount ELSE 0 END),
        [SUMMABLE_NO_CLM_RBT_USD] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_NO_CLM_RBT' THEN f.AmountUSD ELSE 0 END),
        [SUMMABLE_CEDED_NO_CLM_RBT] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_NO_CLM_RBT' THEN f.Amount ELSE 0 END),
        [SUMMABLE_CEDED_NO_CLM_RBT_USD] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_NO_CLM_RBT' THEN f.AmountUSD ELSE 0 END),
        [SUMMABLE_UEPR_RPT_CURR1] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_UEPR_RPT_CURR1' THEN f.Amount ELSE 0 END),
        [SUMMABLE_UEPR_RPT_CURR2] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_UEPR_RPT_CURR2' THEN f.Amount ELSE 0 END),
        [SUMMABLE_DAC_RPT_CURR1] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_DAC_RPT_CURR1' THEN f.Amount ELSE 0 END), 
        [SUMMABLE_DAC_RPT_CURR2] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_DAC_RPT_CURR2' THEN f.Amount ELSE 0 END),
        [SUMMABLE_funds_withheld_premium] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_funds_withheld_premium' THEN f.Amount ELSE 0 END),
        [SUMMABLE_funds_withheld_premium_USD] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_funds_withheld_premium' THEN f.AmountUSD ELSE 0 END),
        [SUMMABLE_funds_released_premium] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_funds_released_premium' THEN f.Amount ELSE 0 END),
        [SUMMABLE_funds_released_premium_USD] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_funds_released_premium' THEN f.AmountUSD ELSE 0 END),
        --[SUMMABLE_FUNDS_RELEASED_LOSSES] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_FUNDS_RELEASED_LOSSES' THEN f.Amount ELSE 0 END),
        --[SUMMABLE_FUNDS_RELEASED_LOSSES_USD] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_FUNDS_RELEASED_LOSSES' THEN f.AmountUSD ELSE 0 END),
        [SUMMABLE_funds_withheld_losses] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_funds_withheld_losses' THEN f.Amount ELSE 0 END),
        [SUMMABLE_funds_withheld_losses_USD] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_funds_withheld_losses' THEN f.AmountUSD ELSE 0 END),
        [SUMMABLE_deferred_withheld] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_deferred_withheld' THEN f.Amount ELSE 0 END),
        [SUMMABLE_deferred_withheld_USD] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_deferred_withheld' THEN f.AmountUSD ELSE 0 END),
        [SUMMABLE_deferred_released] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_deferred_released' THEN f.Amount ELSE 0 END),
        [SUMMABLE_deferred_released_USD] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_deferred_released' THEN f.AmountUSD ELSE 0 END),
        [SUMMABLE_CEDED_funds_withheld_premium] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_funds_withheld_premium' THEN f.Amount ELSE 0 END),
        [SUMMABLE_CEDED_funds_withheld_premium_USD] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_funds_withheld_premium' THEN f.AmountUSD ELSE 0 END),
        [SUMMABLE_CEDED_funds_released_premium] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_funds_released_premium' THEN f.Amount ELSE 0 END),
        [SUMMABLE_CEDED_funds_released_premium_USD] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_funds_released_premium' THEN f.AmountUSD ELSE 0 END),
        [SUMMABLE_CEDED_funds_withheld_losses] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_funds_withheld_losses' THEN f.Amount ELSE 0 END),
        [SUMMABLE_CEDED_funds_withheld_losses_USD] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_funds_withheld_losses' THEN f.AmountUSD ELSE 0 END),
        [SUMMABLE_CEDED_deferred_withheld] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_deferred_withheld' THEN f.Amount ELSE 0 END),
        [SUMMABLE_CEDED_deferred_withheld_USD] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_deferred_withheld' THEN f.AmountUSD ELSE 0 END),
        [SUMMABLE_CEDED_deferred_released] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_deferred_released' THEN f.Amount ELSE 0 END),
        [SUMMABLE_CEDED_deferred_released_USD] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_deferred_released' THEN f.AmountUSD ELSE 0 END),
        [SUMMABLE_CEDED_UEPR_USD] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_UEPR' THEN f.AmountUSD ELSE 0 END),
        [SUMMABLE_DAC_USD] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_DAC' THEN f.AmountUSD ELSE 0 END),
        [SUMMABLE_CEDED_DAC_USD] = SUM(CASE WHEN mm.MappedMeasure = 'SUMMABLE_CEDED_DAC' THEN f.AmountUSD ELSE 0 END)
    into EDW_PREPROD.[assumed].[FactUnderwriting_aggrigation] 
	
	FROM [assumed].[FactUnderwriting] [f] WITH (NOLOCK)
    LEFT JOIN [assumed].DimMeasure dm
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
    GROUP BY [f].[DimContractID],
        [f].[Ceded_DimContractID],
        [f].[Actual_DimAccountingPeriodID],
        f.Intended_DimAccountingPeriodID,
        [f].[Intended_DimAccountingID],
        [f].[DimAdjustmentTypeID],
        [f].[Orig_DimCurrencyID],
        [f].[DimLineOfBusinessID],
        [f].[OrigRpt1_DimExchangeRateID],
        [f].[OrigRpt2_DimExchangeRateID],
        [dm].[Business]