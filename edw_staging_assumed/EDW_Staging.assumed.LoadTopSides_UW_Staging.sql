-- Database: EDW_Staging
-- Schema: assumed
-- Procedure: LoadTopSides_UW_Staging

CREATE   PROCEDURE [assumed].[LoadTopSides_UW_Staging]
AS
BEGIN TRY
	SET NOCOUNT ON
	SET ANSI_WARNINGS OFF 

	DECLARE @v_ProcessName			VARCHAR(100)= OBJECT_SCHEMA_NAME(@@PROCID) + '.' + OBJECT_NAME(@@PROCID)
	DECLARE @v_LastIdentity			BIGINT		= SCOPE_IDENTITY()
	DECLARE @v_ProcessingStarted	DATETIME	= GETDATE()
	DECLARE @v_ProcessingEnded		DATETIME	= GETDATE()
	DECLARE @v_SourceDataDate		DATE		= (SELECT [sql_date] FROM ETL.dbo.[day] WHERE today = 1)
	DECLARE @v_RowsProcessed		BIGINT		= 0
	DECLARE @v_Comment				VARCHAR(MAX)= 'IntegritySourceSetCheck='+CONVERT(VARCHAR,(SELECT EDW_Staging.assumed.Get_IntegritySourceSetCheck() ))

	IF (SELECT EDW_Staging.assumed.Get_IntegritySourceSetCheck() ) = 0
	BEGIN
	-------------------------------------------------------
	-- Update etl_controller, flag SUCCESS
	-------------------------------------------------------
		EXEC ETL.dbo.update_etl_controller 
				@ps_process_name			= @v_ProcessName
			,@pn_rows_processed			= @v_RowsProcessed
			,@pdt_data_datetime			= @v_SourceDataDate
			,@pdt_process_start_datetime= @v_ProcessingStarted
			,@pdt_process_end_datetime	= @v_ProcessingEnded
			,@pn_error_number			= 0
			,@ps_comment				= @v_Comment
			,@pn_max_processed_event_id = @v_LastIdentity
		RETURN
	END

	----------------------------------------------------------------
	--#Parameters
	----------------------------------------------------------------
	DROP TABLE IF EXISTS #Parameters

	SELECT ClosingValidTo = DATEADD(NANOSECOND, -100, SYSDATETIME())
			,NewValidFrom = SYSDATETIME()
	INTO #Parameters

	----------------------------------------------------------------
	--#TopSides_UW_Stage
	----------------------------------------------------------------
	DROP TABLE IF EXISTS #TopSides_UW_Stage

	SELECT
 		 [TREATY_NBR]
		,[UNDERWRITING_YEAR]
		,[CONTRACT_NBR]
		,[CEDED_CONTRACT_NBR]
		,[Source]
		,[TIRS_ORIG_CURR_CD]
		,[TIRS_ORIG_CURR_NAME]
		,[lob_name]
		,[reg_date]
		,[aslob]
		,[solvency_II_regulatory_key]
		,[AdjustmentType]
		,[TIRS_UW_ASSM_CEDED_NAME]
		,[SUMMABLE_WRTN_PREM_ALL_DOC_TYPES]
		,[SUMMABLE_WRTN_PREM_ALL_DOC_TYPES_USD]
		,[SUMMABLE_CEDED_WRTN_PREM_ALL_DOC_TYPES]
		,[SUMMABLE_CEDED_WRTN_PREM_ALL_DOC_TYPES_USD]
		,[SUMMABLE_WRTN_PREM_No_Claims_Rebate]
		,[SUMMABLE_WRTN_PREM_No_Claims_Rebate_USD]
		,[SUMMABLE_CEDED_WRTN_PREM_No_Claims_Rebate]
		,[SUMMABLE_CEDED_WRTN_PREM_No_Claims_Rebate_USD]
		,[SUMMABLE_WRTN_PREM_Reinstatement_Premium]
		,[SUMMABLE_WRTN_PREM_Reinstatement_Premium_USD]
		,[SUMMABLE_CEDED_WRTN_PREM_Reinstatement_Premium]
		,[SUMMABLE_CEDED_WRTN_PREM_Reinstatement_Premium_USD]
		,[SUMMABLE_Brokerage]
		,[SUMMABLE_Brokerage_USD]
		,[SUMMABLE_CEDED_Brokerage]
		,[SUMMABLE_CEDED_Brokerage_USD]
		,[SUMMABLE_Commission]
		,[SUMMABLE_Commission_USD]
		,[SUMMABLE_CEDED_Commission]
		,[SUMMABLE_CEDED_Commission_USD]
		,[SUMMABLE_tax_nonrefund]
		,[SUMMABLE_tax_nonrefund_USD]
		,[SUMMABLE_CEDED_tax_nonrefund]
		,[SUMMABLE_CEDED_tax_nonrefund_USD]
		,[SUMMABLE_tax_on_prem]
		,[SUMMABLE_tax_on_prem_USD]
		,[SUMMABLE_CEDED_tax_on_prem]
		,[SUMMABLE_CEDED_tax_on_prem_USD]
		,[SUMMABLE_tax_refund]
		,[SUMMABLE_tax_refund_USD]
		,[SUMMABLE_CEDED_tax_refund]
		,[SUMMABLE_CEDED_tax_refund_USD]
		,[SUMMABLE_Profit_Commission_Paid]
		,[SUMMABLE_Profit_Commission_Paid_USD]
		,[SUMMABLE_CEDED_Profit_Commission_Paid]
		,[SUMMABLE_CEDED_Profit_Commission_Paid_USD]
		,[SUMMABLE_Sliding_Scale_Commission]
		,[SUMMABLE_Sliding_Scale_Commission_USD]
		,[SUMMABLE_CEDED_Sliding_Scale_Commission]
		,[SUMMABLE_CEDED_Sliding_Scale_Commission_USD]
		,[SUMMABLE_Overrider_Commission]
		,[SUMMABLE_Overrider_Commission_USD]
		,[SUMMABLE_CEDED_Overrider_Commission]
		,[SUMMABLE_CEDED_Overrider_Commission_USD]       
		,[SUMMABLE_Provisional_Commission]
		,[SUMMABLE_Provisional_Commission_USD]
		,[SUMMABLE_CEDED_Provisional_Commission]
		,[SUMMABLE_CEDED_Provisional_Commission_USD]
		,[SUMMABLE_Deferred_Commission]
		,[SUMMABLE_Deferred_Commission_USD]
		,[SUMMABLE_CEDED_Deferred_Commission]
		,[SUMMABLE_CEDED_Deferred_Commission_USD]
		,[SUMMABLE_int_funds_gross]
		,[SUMMABLE_int_funds_gross_USD]
		,[SUMMABLE_CEDED_int_funds_gross]
		,[SUMMABLE_CEDED_int_funds_gross_USD]
		,[SUMMABLE_int_funds_wth]
		,[SUMMABLE_int_funds_wth_USD]
		,[SUMMABLE_CEDED_int_funds_wth]
		,[SUMMABLE_CEDED_int_funds_wth_USD]
		,[SUMMABLE_fire_prevent_fund]
		,[SUMMABLE_fire_prevent_fund_USD]
		,[SUMMABLE_CEDED_fire_prevent_fund]
		,[SUMMABLE_CEDED_fire_prevent_fund_USD]
		,[SUMMABLE_xch_diff]
		,[SUMMABLE_xch_diff_USD]
		,[SUMMABLE_CEDED_xch_diff]
		,[SUMMABLE_CEDED_xch_diff_USD]
		,[SUMMABLE_NO_CLM_RBT]
		,[SUMMABLE_NO_CLM_RBT_USD]
		,[SUMMABLE_CEDED_NO_CLM_RBT]
		,[SUMMABLE_CEDED_NO_CLM_RBT_USD]
		,[SUMMABLE_funds_withheld_premium]
		,[SUMMABLE_funds_withheld_premium_USD]
		,[SUMMABLE_CEDED_funds_withheld_premium]
		,[SUMMABLE_CEDED_funds_withheld_premium_USD]
		,[SUMMABLE_funds_released_premium]
		,[SUMMABLE_funds_released_premium_USD]
		,[SUMMABLE_CEDED_funds_released_premium]
		,[SUMMABLE_CEDED_funds_released_premium_USD]
		,[SUMMABLE_funds_withheld_losses]
		,[SUMMABLE_funds_withheld_losses_USD]
		,[SUMMABLE_CEDED_funds_withheld_losses]
		,[SUMMABLE_CEDED_funds_withheld_losses_USD]
		,[SUMMABLE_deferred_withheld]
		,[SUMMABLE_deferred_withheld_USD]
		,[SUMMABLE_CEDED_deferred_withheld]
		,[SUMMABLE_CEDED_deferred_withheld_USD]
		,[SUMMABLE_deferred_released]
		,[SUMMABLE_deferred_released_USD]
		,[SUMMABLE_CEDED_deferred_released]
		,[SUMMABLE_CEDED_deferred_released_USD]
		,[SUMMABLE_UEPR]
		,[SUMMABLE_UEPR_USD]
		,[SUMMABLE_CEDED_UEPR]
		,[SUMMABLE_CEDED_UEPR_USD]
		,[SUMMABLE_UEPR_RPT_CURR1]
		,[SUMMABLE_UEPR_RPT_CURR2]
		,[SUMMABLE_DAC]
		,[SUMMABLE_DAC_USD]
		,[SUMMABLE_CEDED_DAC]
		,[SUMMABLE_CEDED_DAC_USD]
		,[SUMMABLE_DAC_RPT_CURR1]
		,[SUMMABLE_DAC_RPT_CURR2]
		,[T7_CODE]
		,[T8_CODE]
		,[T9_CODE]
		,[MBU]
		,[L01]
		,[L02]
		,[L03]
		,[L04]
		,[L05]
		,[L06]
		,[L07]
		,[L08]
		,[L09]
		,[L10]
		,[GD1]
		,[RPTCURR1]
		,[RPTCURR1_CD]
		,[RPTCURR2]
		,[RPTCURR2_CD]
		,[InsurerCode]
		,[Financial_Lob]
		,[RPT_OFC_NM]
		,[ICP_CEDED_FLG]
		,[actuariallob]
		,[CLMS_PROCSS_CLM_DEPT]
		,[ID]
		,[Unmatched_Fields]
		,[topside_reg_date]
		,[Blended_Rate]
		,[MATCH_SOURCE_FLAG]
		,[DataHash]	=CONVERT(VARBINARY(500), NULL)
	INTO #TopSides_UW_Stage
	FROM EDW_PREPROD.dbo.RS_TIRS_UNDERWRITING_TOPSIDE;
	--------------------------------------------------------------------------
	--DataHash
	--------------------------------------------------------------------------
	UPDATE s
	SET DataHash = HASHBYTES('SHA1', 
				CONCAT(
					s.[TREATY_NBR]
					, '|',s.[UNDERWRITING_YEAR]
					, '|',s.[CEDED_CONTRACT_NBR]
					, '|',s.[Source]
					, '|',s.[TIRS_ORIG_CURR_CD]
					, '|',s.[TIRS_ORIG_CURR_NAME]
					, '|',s.[lob_name]
					, '|',s.[reg_date]
					, '|',s.[aslob]
					, '|',s.[solvency_II_regulatory_key]
					, '|',s.[AdjustmentType]
					, '|',s.[TIRS_UW_ASSM_CEDED_NAME]
					, '|',s.[SUMMABLE_WRTN_PREM_ALL_DOC_TYPES]
					, '|',s.[SUMMABLE_WRTN_PREM_ALL_DOC_TYPES_USD]
					, '|',s.[SUMMABLE_CEDED_WRTN_PREM_ALL_DOC_TYPES]
					, '|',s.[SUMMABLE_CEDED_WRTN_PREM_ALL_DOC_TYPES_USD]
					, '|',s.[SUMMABLE_WRTN_PREM_No_Claims_Rebate]
					, '|',s.[SUMMABLE_WRTN_PREM_No_Claims_Rebate_USD]
					, '|',s.[SUMMABLE_CEDED_WRTN_PREM_No_Claims_Rebate]
					, '|',s.[SUMMABLE_CEDED_WRTN_PREM_No_Claims_Rebate_USD]
					, '|',s.[SUMMABLE_WRTN_PREM_Reinstatement_Premium]
					, '|',s.[SUMMABLE_WRTN_PREM_Reinstatement_Premium_USD]
					, '|',s.[SUMMABLE_CEDED_WRTN_PREM_Reinstatement_Premium]
					, '|',s.[SUMMABLE_CEDED_WRTN_PREM_Reinstatement_Premium_USD]
					, '|',s.[SUMMABLE_Brokerage]
					, '|',s.[SUMMABLE_Brokerage_USD]
					, '|',s.[SUMMABLE_CEDED_Brokerage]
					, '|',s.[SUMMABLE_CEDED_Brokerage_USD]
					, '|',s.[SUMMABLE_Commission]
					, '|',s.[SUMMABLE_Commission_USD]
					, '|',s.[SUMMABLE_CEDED_Commission]
					, '|',s.[SUMMABLE_CEDED_Commission_USD]
					, '|',s.[SUMMABLE_tax_nonrefund]
					, '|',s.[SUMMABLE_tax_nonrefund_USD]
					, '|',s.[SUMMABLE_CEDED_tax_nonrefund]
					, '|',s.[SUMMABLE_CEDED_tax_nonrefund_USD]
					, '|',s.[SUMMABLE_tax_on_prem]
					, '|',s.[SUMMABLE_tax_on_prem_USD]
					, '|',s.[SUMMABLE_CEDED_tax_on_prem]
					, '|',s.[SUMMABLE_CEDED_tax_on_prem_USD]
					, '|',s.[SUMMABLE_tax_refund]
					, '|',s.[SUMMABLE_tax_refund_USD]
					, '|',s.[SUMMABLE_CEDED_tax_refund]
					, '|',s.[SUMMABLE_CEDED_tax_refund_USD]
					, '|',s.[SUMMABLE_Profit_Commission_Paid]
					, '|',s.[SUMMABLE_Profit_Commission_Paid_USD]
					, '|',s.[SUMMABLE_CEDED_Profit_Commission_Paid]
					, '|',s.[SUMMABLE_CEDED_Profit_Commission_Paid_USD]
					, '|',s.[SUMMABLE_Sliding_Scale_Commission]
					, '|',s.[SUMMABLE_Sliding_Scale_Commission_USD]
					, '|',s.[SUMMABLE_CEDED_Sliding_Scale_Commission]
					, '|',s.[SUMMABLE_CEDED_Sliding_Scale_Commission_USD]
					, '|',s.[SUMMABLE_Overrider_Commission]
					, '|',s.[SUMMABLE_Overrider_Commission_USD]
					, '|',s.[SUMMABLE_CEDED_Overrider_Commission]
					, '|',s.[SUMMABLE_CEDED_Overrider_Commission_USD]       
					, '|',s.[SUMMABLE_Provisional_Commission]
					, '|',s.[SUMMABLE_Provisional_Commission_USD]
					, '|',s.[SUMMABLE_CEDED_Provisional_Commission]
					, '|',s.[SUMMABLE_CEDED_Provisional_Commission_USD]
					, '|',s.[SUMMABLE_Deferred_Commission]
					, '|',s.[SUMMABLE_Deferred_Commission_USD]
					, '|',s.[SUMMABLE_CEDED_Deferred_Commission]
					, '|',s.[SUMMABLE_CEDED_Deferred_Commission_USD]
					, '|',s.[SUMMABLE_int_funds_gross]
					, '|',s.[SUMMABLE_int_funds_gross_USD]
					, '|',s.[SUMMABLE_CEDED_int_funds_gross]
					, '|',s.[SUMMABLE_CEDED_int_funds_gross_USD]
					, '|',s.[SUMMABLE_int_funds_wth]
					, '|',s.[SUMMABLE_int_funds_wth_USD]
					, '|',s.[SUMMABLE_CEDED_int_funds_wth]
					, '|',s.[SUMMABLE_CEDED_int_funds_wth_USD]
					, '|',s.[SUMMABLE_fire_prevent_fund]
					, '|',s.[SUMMABLE_fire_prevent_fund_USD]
					, '|',s.[SUMMABLE_CEDED_fire_prevent_fund]
					, '|',s.[SUMMABLE_CEDED_fire_prevent_fund_USD]
					, '|',s.[SUMMABLE_xch_diff]
					, '|',s.[SUMMABLE_xch_diff_USD]
					, '|',s.[SUMMABLE_CEDED_xch_diff]
					, '|',s.[SUMMABLE_CEDED_xch_diff_USD]
					, '|',s.[SUMMABLE_NO_CLM_RBT]
					, '|',s.[SUMMABLE_NO_CLM_RBT_USD]
					, '|',s.[SUMMABLE_CEDED_NO_CLM_RBT]
					, '|',s.[SUMMABLE_CEDED_NO_CLM_RBT_USD]
					, '|',s.[SUMMABLE_funds_withheld_premium]
					, '|',s.[SUMMABLE_funds_withheld_premium_USD])
					+CONCAT(
					  '|',s.[SUMMABLE_CEDED_funds_withheld_premium]
					, '|',s.[SUMMABLE_CEDED_funds_withheld_premium_USD]
					, '|',s.[SUMMABLE_funds_released_premium]
					, '|',s.[SUMMABLE_funds_released_premium_USD]
					, '|',s.[SUMMABLE_CEDED_funds_released_premium]
					, '|',s.[SUMMABLE_CEDED_funds_released_premium_USD]
					, '|',s.[SUMMABLE_funds_withheld_losses]
					, '|',s.[SUMMABLE_funds_withheld_losses_USD]
					, '|',s.[SUMMABLE_CEDED_funds_withheld_losses]
					, '|',s.[SUMMABLE_CEDED_funds_withheld_losses_USD]
					, '|',s.[SUMMABLE_deferred_withheld]
					, '|',s.[SUMMABLE_deferred_withheld_USD]
					, '|',s.[SUMMABLE_CEDED_deferred_withheld]
					, '|',s.[SUMMABLE_CEDED_deferred_withheld_USD]
					, '|',s.[SUMMABLE_deferred_released]
					, '|',s.[SUMMABLE_deferred_released_USD]
					, '|',s.[SUMMABLE_CEDED_deferred_released]
					, '|',s.[SUMMABLE_CEDED_deferred_released_USD]
					, '|',s.[SUMMABLE_UEPR]
					, '|',s.[SUMMABLE_UEPR_USD]
					, '|',s.[SUMMABLE_CEDED_UEPR]
					, '|',s.[SUMMABLE_CEDED_UEPR_USD]
					, '|',s.[SUMMABLE_UEPR_RPT_CURR1]
					, '|',s.[SUMMABLE_UEPR_RPT_CURR2]
					, '|',s.[SUMMABLE_DAC]
					, '|',s.[SUMMABLE_DAC_USD]
					, '|',s.[SUMMABLE_CEDED_DAC]
					, '|',s.[SUMMABLE_CEDED_DAC_USD]
					, '|',s.[SUMMABLE_DAC_RPT_CURR1]
					, '|',s.[SUMMABLE_DAC_RPT_CURR2]
					, '|',s.[T7_CODE]
					, '|',s.[T8_CODE]
					, '|',s.[T9_CODE]
					, '|',s.[MBU]
					, '|',s.[L01]
					, '|',s.[L02]
					, '|',s.[L03]
					, '|',s.[L04]
					, '|',s.[L05]
					, '|',s.[L06]
					, '|',s.[L07]
					, '|',s.[L08]
					, '|',s.[L09]
					, '|',s.[L10]
					, '|',s.[GD1]
					, '|',s.[RPTCURR1]
					, '|',s.[RPTCURR1_CD]
					, '|',s.[RPTCURR2]
					, '|',s.[RPTCURR2_CD]
					, '|',s.[InsurerCode]
					, '|',s.[Financial_Lob]
					, '|',s.[RPT_OFC_NM]
					, '|',s.[ICP_CEDED_FLG]
					, '|',s.[actuariallob]
					, '|',s.[CLMS_PROCSS_CLM_DEPT]
					, '|',s.[Unmatched_Fields]
					, '|',s.[topside_reg_date]
					, '|',s.[Blended_Rate]
					, '|',s.[MATCH_SOURCE_FLAG]
		))
	FROM #TopSides_UW_Stage s
	--------------------------------------------------------------------------
	--#UWLoadOperation
	--------------------------------------------------------------------------	
	DROP TABLE IF EXISTS #UWLoadOperation

	CREATE TABLE #UWLoadOperation
	(
	 [ID]			BIGINT NOT NULL
	,[CONTRACT_NBR]	VARCHAR(25) COLLATE DATABASE_DEFAULT NOT NULL
	,[Operation]	CHAR(1) NOT NULL
	,UNIQUE (CONTRACT_NBR, ID)
	)
	
	INSERT INTO #UWLoadOperation
	(
		 [ID]
		,[CONTRACT_NBR]				
		,[Operation]
	)
	SELECT
		 [ID]			= COALESCE(t.ID, s.ID, 0)
		,[CONTRACT_NBR] = COALESCE(t.CONTRACT_NBR COLLATE DATABASE_DEFAULT, s.CONTRACT_NBR COLLATE DATABASE_DEFAULT)
		,[Operation]	= CASE WHEN t.TopSides_UW_StagingID IS NULL THEN 'I' WHEN s.DataHash IS NULL THEN 'D' ELSE 'U' END
	FROM (
		SELECT t.*
		FROM assumed.TopSides_UW_Staging t
		WHERE t.EndDate = '9999-12-31'
		) t
	FULL JOIN #TopSides_UW_Stage s		ON  s.ID = t.ID
										AND s.CONTRACT_NBR = t.CONTRACT_NBR COLLATE DATABASE_DEFAULT
	 WHERE t.DataHash IS NULL
		OR s.DataHash IS NULL
		OR t.DataHash != s.DataHash
	--------------------------------------------------------------------------
	--TopSides_UW_Staging
	--------------------------------------------------------------------------		
	BEGIN TRANSACTION		

	UPDATE t
	   SET EndDate = p.ClosingValidTo
	  FROM assumed.TopSides_UW_Staging	t
	 CROSS JOIN #Parameters				p
	 INNER JOIN #UWLoadOperation		lo	ON  lo.ID			= t.ID
											AND lo.CONTRACT_NBR = t.CONTRACT_NBR COLLATE DATABASE_DEFAULT
											AND lo.Operation IN ('U', 'D')
	WHERE t.EndDate = '9999-12-31'

	INSERT INTO assumed.TopSides_UW_Staging
		([StartDate]
 		,[TREATY_NBR]
		,[UNDERWRITING_YEAR]
		,[CONTRACT_NBR]
		,[CEDED_CONTRACT_NBR]
		,[Source]
		,[TIRS_ORIG_CURR_CD]
		,[TIRS_ORIG_CURR_NAME]
		,[lob_name]
		,[reg_date]
		,[aslob]
		,[solvency_II_regulatory_key]
		,[AdjustmentType]
		,[TIRS_UW_ASSM_CEDED_NAME]
		,[SUMMABLE_WRTN_PREM_ALL_DOC_TYPES]
		,[SUMMABLE_WRTN_PREM_ALL_DOC_TYPES_USD]
		,[SUMMABLE_CEDED_WRTN_PREM_ALL_DOC_TYPES]
		,[SUMMABLE_CEDED_WRTN_PREM_ALL_DOC_TYPES_USD]
		,[SUMMABLE_WRTN_PREM_No_Claims_Rebate]
		,[SUMMABLE_WRTN_PREM_No_Claims_Rebate_USD]
		,[SUMMABLE_CEDED_WRTN_PREM_No_Claims_Rebate]
		,[SUMMABLE_CEDED_WRTN_PREM_No_Claims_Rebate_USD]
		,[SUMMABLE_WRTN_PREM_Reinstatement_Premium]
		,[SUMMABLE_WRTN_PREM_Reinstatement_Premium_USD]
		,[SUMMABLE_CEDED_WRTN_PREM_Reinstatement_Premium]
		,[SUMMABLE_CEDED_WRTN_PREM_Reinstatement_Premium_USD]
		,[SUMMABLE_Brokerage]
		,[SUMMABLE_Brokerage_USD]
		,[SUMMABLE_CEDED_Brokerage]
		,[SUMMABLE_CEDED_Brokerage_USD]
		,[SUMMABLE_Commission]
		,[SUMMABLE_Commission_USD]
		,[SUMMABLE_CEDED_Commission]
		,[SUMMABLE_CEDED_Commission_USD]
		,[SUMMABLE_tax_nonrefund]
		,[SUMMABLE_tax_nonrefund_USD]
		,[SUMMABLE_CEDED_tax_nonrefund]
		,[SUMMABLE_CEDED_tax_nonrefund_USD]
		,[SUMMABLE_tax_on_prem]
		,[SUMMABLE_tax_on_prem_USD]
		,[SUMMABLE_CEDED_tax_on_prem]
		,[SUMMABLE_CEDED_tax_on_prem_USD]
		,[SUMMABLE_tax_refund]
		,[SUMMABLE_tax_refund_USD]
		,[SUMMABLE_CEDED_tax_refund]
		,[SUMMABLE_CEDED_tax_refund_USD]
		,[SUMMABLE_Profit_Commission_Paid]
		,[SUMMABLE_Profit_Commission_Paid_USD]
		,[SUMMABLE_CEDED_Profit_Commission_Paid]
		,[SUMMABLE_CEDED_Profit_Commission_Paid_USD]
		,[SUMMABLE_Sliding_Scale_Commission]
		,[SUMMABLE_Sliding_Scale_Commission_USD]
		,[SUMMABLE_CEDED_Sliding_Scale_Commission]
		,[SUMMABLE_CEDED_Sliding_Scale_Commission_USD]
		,[SUMMABLE_Overrider_Commission]
		,[SUMMABLE_Overrider_Commission_USD]
		,[SUMMABLE_CEDED_Overrider_Commission]
		,[SUMMABLE_CEDED_Overrider_Commission_USD]       
		,[SUMMABLE_Provisional_Commission]
		,[SUMMABLE_Provisional_Commission_USD]
		,[SUMMABLE_CEDED_Provisional_Commission]
		,[SUMMABLE_CEDED_Provisional_Commission_USD]
		,[SUMMABLE_Deferred_Commission]
		,[SUMMABLE_Deferred_Commission_USD]
		,[SUMMABLE_CEDED_Deferred_Commission]
		,[SUMMABLE_CEDED_Deferred_Commission_USD]
		,[SUMMABLE_int_funds_gross]
		,[SUMMABLE_int_funds_gross_USD]
		,[SUMMABLE_CEDED_int_funds_gross]
		,[SUMMABLE_CEDED_int_funds_gross_USD]
		,[SUMMABLE_int_funds_wth]
		,[SUMMABLE_int_funds_wth_USD]
		,[SUMMABLE_CEDED_int_funds_wth]
		,[SUMMABLE_CEDED_int_funds_wth_USD]
		,[SUMMABLE_fire_prevent_fund]
		,[SUMMABLE_fire_prevent_fund_USD]
		,[SUMMABLE_CEDED_fire_prevent_fund]
		,[SUMMABLE_CEDED_fire_prevent_fund_USD]
		,[SUMMABLE_xch_diff]
		,[SUMMABLE_xch_diff_USD]
		,[SUMMABLE_CEDED_xch_diff]
		,[SUMMABLE_CEDED_xch_diff_USD]
		,[SUMMABLE_NO_CLM_RBT]
		,[SUMMABLE_NO_CLM_RBT_USD]
		,[SUMMABLE_CEDED_NO_CLM_RBT]
		,[SUMMABLE_CEDED_NO_CLM_RBT_USD]
		,[SUMMABLE_funds_withheld_premium]
		,[SUMMABLE_funds_withheld_premium_USD]
		,[SUMMABLE_CEDED_funds_withheld_premium]
		,[SUMMABLE_CEDED_funds_withheld_premium_USD]
		,[SUMMABLE_funds_released_premium]
		,[SUMMABLE_funds_released_premium_USD]
		,[SUMMABLE_CEDED_funds_released_premium]
		,[SUMMABLE_CEDED_funds_released_premium_USD]
		,[SUMMABLE_funds_withheld_losses]
		,[SUMMABLE_funds_withheld_losses_USD]
		,[SUMMABLE_CEDED_funds_withheld_losses]
		,[SUMMABLE_CEDED_funds_withheld_losses_USD]
		,[SUMMABLE_deferred_withheld]
		,[SUMMABLE_deferred_withheld_USD]
		,[SUMMABLE_CEDED_deferred_withheld]
		,[SUMMABLE_CEDED_deferred_withheld_USD]
		,[SUMMABLE_deferred_released]
		,[SUMMABLE_deferred_released_USD]
		,[SUMMABLE_CEDED_deferred_released]
		,[SUMMABLE_CEDED_deferred_released_USD]
		,[SUMMABLE_UEPR]
		,[SUMMABLE_UEPR_USD]
		,[SUMMABLE_CEDED_UEPR]
		,[SUMMABLE_CEDED_UEPR_USD]
		,[SUMMABLE_UEPR_RPT_CURR1]
		,[SUMMABLE_UEPR_RPT_CURR2]
		,[SUMMABLE_DAC]
		,[SUMMABLE_DAC_USD]
		,[SUMMABLE_CEDED_DAC]
		,[SUMMABLE_CEDED_DAC_USD]
		,[SUMMABLE_DAC_RPT_CURR1]
		,[SUMMABLE_DAC_RPT_CURR2]
		,[T7_CODE]
		,[T8_CODE]
		,[T9_CODE]
		,[MBU]
		,[L01]
		,[L02]
		,[L03]
		,[L04]
		,[L05]
		,[L06]
		,[L07]
		,[L08]
		,[L09]
		,[L10]
		,[GD1]
		,[RPTCURR1]
		,[RPTCURR1_CD]
		,[RPTCURR2]
		,[RPTCURR2_CD]
		,[InsurerCode]
		,[Financial_Lob]
		,[RPT_OFC_NM]
		,[ICP_CEDED_FLG]
		,[actuariallob]
		,[CLMS_PROCSS_CLM_DEPT]
		,[ID]
		,[Unmatched_Fields]
		,[topside_reg_date]
		,[Blended_Rate]
		,[MATCH_SOURCE_FLAG]
		,[DataHash]
	)
	SELECT [StartDate] = p.NewValidFrom
 		,s.[TREATY_NBR]
 		,s.[UNDERWRITING_YEAR]
 		,s.[CONTRACT_NBR]
 		,s.[CEDED_CONTRACT_NBR]
 		,s.[Source]
 		,s.[TIRS_ORIG_CURR_CD]
 		,s.[TIRS_ORIG_CURR_NAME]
 		,s.[lob_name]
 		,s.[reg_date]
 		,s.[aslob]
 		,s.[solvency_II_regulatory_key]
 		,s.[AdjustmentType]
 		,s.[TIRS_UW_ASSM_CEDED_NAME]
 		,s.[SUMMABLE_WRTN_PREM_ALL_DOC_TYPES]
 		,s.[SUMMABLE_WRTN_PREM_ALL_DOC_TYPES_USD]
 		,s.[SUMMABLE_CEDED_WRTN_PREM_ALL_DOC_TYPES]
 		,s.[SUMMABLE_CEDED_WRTN_PREM_ALL_DOC_TYPES_USD]
 		,s.[SUMMABLE_WRTN_PREM_No_Claims_Rebate]
 		,s.[SUMMABLE_WRTN_PREM_No_Claims_Rebate_USD]
 		,s.[SUMMABLE_CEDED_WRTN_PREM_No_Claims_Rebate]
 		,s.[SUMMABLE_CEDED_WRTN_PREM_No_Claims_Rebate_USD]
 		,s.[SUMMABLE_WRTN_PREM_Reinstatement_Premium]
 		,s.[SUMMABLE_WRTN_PREM_Reinstatement_Premium_USD]
 		,s.[SUMMABLE_CEDED_WRTN_PREM_Reinstatement_Premium]
 		,s.[SUMMABLE_CEDED_WRTN_PREM_Reinstatement_Premium_USD]
 		,s.[SUMMABLE_Brokerage]
 		,s.[SUMMABLE_Brokerage_USD]
 		,s.[SUMMABLE_CEDED_Brokerage]
 		,s.[SUMMABLE_CEDED_Brokerage_USD]
 		,s.[SUMMABLE_Commission]
 		,s.[SUMMABLE_Commission_USD]
 		,s.[SUMMABLE_CEDED_Commission]
 		,s.[SUMMABLE_CEDED_Commission_USD]
 		,s.[SUMMABLE_tax_nonrefund]
 		,s.[SUMMABLE_tax_nonrefund_USD]
 		,s.[SUMMABLE_CEDED_tax_nonrefund]
 		,s.[SUMMABLE_CEDED_tax_nonrefund_USD]
 		,s.[SUMMABLE_tax_on_prem]
 		,s.[SUMMABLE_tax_on_prem_USD]
 		,s.[SUMMABLE_CEDED_tax_on_prem]
 		,s.[SUMMABLE_CEDED_tax_on_prem_USD]
 		,s.[SUMMABLE_tax_refund]
 		,s.[SUMMABLE_tax_refund_USD]
 		,s.[SUMMABLE_CEDED_tax_refund]
 		,s.[SUMMABLE_CEDED_tax_refund_USD]
 		,s.[SUMMABLE_Profit_Commission_Paid]
 		,s.[SUMMABLE_Profit_Commission_Paid_USD]
 		,s.[SUMMABLE_CEDED_Profit_Commission_Paid]
 		,s.[SUMMABLE_CEDED_Profit_Commission_Paid_USD]
 		,s.[SUMMABLE_Sliding_Scale_Commission]
 		,s.[SUMMABLE_Sliding_Scale_Commission_USD]
 		,s.[SUMMABLE_CEDED_Sliding_Scale_Commission]
 		,s.[SUMMABLE_CEDED_Sliding_Scale_Commission_USD]
 		,s.[SUMMABLE_Overrider_Commission]
 		,s.[SUMMABLE_Overrider_Commission_USD]
 		,s.[SUMMABLE_CEDED_Overrider_Commission]
 		,s.[SUMMABLE_CEDED_Overrider_Commission_USD]       
 		,s.[SUMMABLE_Provisional_Commission]
 		,s.[SUMMABLE_Provisional_Commission_USD]
 		,s.[SUMMABLE_CEDED_Provisional_Commission]
 		,s.[SUMMABLE_CEDED_Provisional_Commission_USD]
 		,s.[SUMMABLE_Deferred_Commission]
 		,s.[SUMMABLE_Deferred_Commission_USD]
 		,s.[SUMMABLE_CEDED_Deferred_Commission]
 		,s.[SUMMABLE_CEDED_Deferred_Commission_USD]
 		,s.[SUMMABLE_int_funds_gross]
 		,s.[SUMMABLE_int_funds_gross_USD]
 		,s.[SUMMABLE_CEDED_int_funds_gross]
 		,s.[SUMMABLE_CEDED_int_funds_gross_USD]
 		,s.[SUMMABLE_int_funds_wth]
 		,s.[SUMMABLE_int_funds_wth_USD]
 		,s.[SUMMABLE_CEDED_int_funds_wth]
 		,s.[SUMMABLE_CEDED_int_funds_wth_USD]
 		,s.[SUMMABLE_fire_prevent_fund]
 		,s.[SUMMABLE_fire_prevent_fund_USD]
 		,s.[SUMMABLE_CEDED_fire_prevent_fund]
 		,s.[SUMMABLE_CEDED_fire_prevent_fund_USD]
 		,s.[SUMMABLE_xch_diff]
 		,s.[SUMMABLE_xch_diff_USD]
 		,s.[SUMMABLE_CEDED_xch_diff]
 		,s.[SUMMABLE_CEDED_xch_diff_USD]
 		,s.[SUMMABLE_NO_CLM_RBT]
 		,s.[SUMMABLE_NO_CLM_RBT_USD]
 		,s.[SUMMABLE_CEDED_NO_CLM_RBT]
 		,s.[SUMMABLE_CEDED_NO_CLM_RBT_USD]
 		,s.[SUMMABLE_funds_withheld_premium]
 		,s.[SUMMABLE_funds_withheld_premium_USD]
 		,s.[SUMMABLE_CEDED_funds_withheld_premium]
 		,s.[SUMMABLE_CEDED_funds_withheld_premium_USD]
 		,s.[SUMMABLE_funds_released_premium]
 		,s.[SUMMABLE_funds_released_premium_USD]
 		,s.[SUMMABLE_CEDED_funds_released_premium]
 		,s.[SUMMABLE_CEDED_funds_released_premium_USD]
 		,s.[SUMMABLE_funds_withheld_losses]
 		,s.[SUMMABLE_funds_withheld_losses_USD]
 		,s.[SUMMABLE_CEDED_funds_withheld_losses]
 		,s.[SUMMABLE_CEDED_funds_withheld_losses_USD]
 		,s.[SUMMABLE_deferred_withheld]
 		,s.[SUMMABLE_deferred_withheld_USD]
 		,s.[SUMMABLE_CEDED_deferred_withheld]
 		,s.[SUMMABLE_CEDED_deferred_withheld_USD]
 		,s.[SUMMABLE_deferred_released]
 		,s.[SUMMABLE_deferred_released_USD]
 		,s.[SUMMABLE_CEDED_deferred_released]
 		,s.[SUMMABLE_CEDED_deferred_released_USD]
 		,s.[SUMMABLE_UEPR]
 		,s.[SUMMABLE_UEPR_USD]
 		,s.[SUMMABLE_CEDED_UEPR]
 		,s.[SUMMABLE_CEDED_UEPR_USD]
 		,s.[SUMMABLE_UEPR_RPT_CURR1]
 		,s.[SUMMABLE_UEPR_RPT_CURR2]
 		,s.[SUMMABLE_DAC]
 		,s.[SUMMABLE_DAC_USD]
 		,s.[SUMMABLE_CEDED_DAC]
 		,s.[SUMMABLE_CEDED_DAC_USD]
 		,s.[SUMMABLE_DAC_RPT_CURR1]
 		,s.[SUMMABLE_DAC_RPT_CURR2]
 		,s.[T7_CODE]
 		,s.[T8_CODE]
 		,s.[T9_CODE]
 		,s.[MBU]
 		,s.[L01]
 		,s.[L02]
 		,s.[L03]
 		,s.[L04]
 		,s.[L05]
 		,s.[L06]
 		,s.[L07]
 		,s.[L08]
 		,s.[L09]
 		,s.[L10]
 		,s.[GD1]
 		,s.[RPTCURR1]
 		,s.[RPTCURR1_CD]
 		,s.[RPTCURR2]
 		,s.[RPTCURR2_CD]
 		,s.[InsurerCode]
 		,s.[Financial_Lob]
 		,s.[RPT_OFC_NM]
 		,s.[ICP_CEDED_FLG]
 		,s.[actuariallob]
 		,s.[CLMS_PROCSS_CLM_DEPT]
 		,s.[ID]
 		,s.[Unmatched_Fields]
 		,s.[topside_reg_date]
 		,s.[Blended_Rate]
 		,s.[MATCH_SOURCE_FLAG]
		,s.[DataHash]
	FROM #TopSides_UW_Stage		s
	CROSS JOIN #Parameters		p
	INNER JOIN #UWLoadOperation lo	ON  COALESCE(lo.ID, - 1) = COALESCE(s.ID, - 1)
									AND lo.CONTRACT_NBR = s.CONTRACT_NBR COLLATE DATABASE_DEFAULT
									AND lo.Operation IN ('I', 'U')

	COMMIT TRANSACTION

	-------------------------------------------------------
	-- Update etl_controller, flag SUCCESS
	-------------------------------------------------------
	SET @v_RowsProcessed	= COALESCE((SELECT COUNT(0) FROM #UWLoadOperation WHERE Operation IN ('I', 'U', 'D')), 0)
	SET @v_ProcessingEnded	= GETDATE()
	SET @v_LastIdentity		= SCOPE_IDENTITY()

	EXEC ETL.dbo.update_etl_controller 
		 @ps_process_name			= @v_ProcessName
		,@pn_rows_processed			= @v_RowsProcessed
		,@pdt_data_datetime			= @v_SourceDataDate
		,@pdt_process_start_datetime= @v_ProcessingStarted
		,@pdt_process_end_datetime	= @v_ProcessingEnded
		,@pn_error_number			= 0
		,@ps_comment				= @v_Comment
		,@pn_max_processed_event_id = @v_LastIdentity
END TRY

BEGIN CATCH        
        IF @@TRANCOUNT > 0 
			BEGIN ROLLBACK TRANSACTION;
        END
		/*Raise error to SQL Agent*/
		DECLARE @v_ErrorDescription	VARCHAR(MAX)= CONCAT('Error: ', ERROR_NUMBER(), ' - ', ERROR_MESSAGE(), '; ', 'Occurred in procedure: ' + ERROR_PROCEDURE() + ', ', 'Line ', ERROR_LINE())
		DECLARE @v_ErrorNumber		INT			= ERROR_NUMBER()
		DECLARE @v_ErrorMessage		VARCHAR(MAX)= ERROR_MESSAGE()
		DECLARE @v_ErrorSeverity	INT			= ERROR_SEVERITY()
		DECLARE @v_ErrorState		INT			= ERROR_STATE()
			SET @v_ProcessingEnded	= GETDATE() 

		EXEC ETL.dbo.update_etl_controller 
			 @ps_process_name			= @v_ProcessName
			,@pn_rows_processed			= 0
			,@pdt_data_datetime			= @v_SourceDataDate
			,@pdt_process_start_datetime= @v_ProcessingStarted
			,@pdt_process_end_datetime	= @v_ProcessingEnded
			,@pn_error_number			= @v_ErrorNumber
			,@ps_comment				= @v_ErrorDescription
			,@pn_max_processed_event_id = 0

		EXEC ETL.dbo.insert_error_log 
			 @process_name	= @v_ProcessName
			,@object_name	= 0
			,@user_message	= @v_ErrorDescription
			,@status		= 0
			,@remedy		= 'Contact EDW team'

		RAISERROR(@v_ErrorMessage, @v_ErrorSeverity, @v_ErrorState)
END CATCH
