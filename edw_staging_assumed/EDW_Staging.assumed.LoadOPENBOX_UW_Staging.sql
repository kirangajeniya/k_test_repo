-- Database: EDW_Staging
-- Schema: assumed
-- Procedure: LoadOPENBOX_UW_Staging

CREATE   PROCEDURE [assumed].[LoadOPENBOX_UW_Staging]
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

	SELECT
		 ClosingValidTo = DATEADD(NANOSECOND, -100, SYSDATETIME())
		,NewValidFrom	= SYSDATETIME()
	INTO #Parameters

	----------------------------------------------------------------
	--#OpenBox_UW_Stage
	----------------------------------------------------------------
	DROP TABLE IF EXISTS #OpenBox_UW_Stage

	CREATE TABLE #OpenBox_UW_Stage 
	(
		[TREATY_NBR]					VARCHAR(5) NULL,
		[UNDERWRITING_YEAR]				VARCHAR(4) NULL,
		[CONTRACT_NBR]					VARCHAR(25) NULL,
		[reg_date]						DATETIME NULL,
		[ASSUMED_CEDED_FLG]				CHAR(1) NULL,
		[TIRS_UW_ASSM_CEDED_NAME]		VARCHAR(7) NULL,
		[TIRS_ORIG_CURR_CD]				VARCHAR(3) NULL,
		[TIRS_ORIG_CURR_NAME]			VARCHAR(50) NULL,
		[lob_name]						VARCHAR(255) NULL,
		[ActuarialLob]					VARCHAR(100) NULL,
		[solvency_II_regulatory_key]	INT NULL,
		[SUMMABLE_WRTN_PREM_ALL_DOC_TYPES]		MONEY NULL,
		[SUMMABLE_WRTN_PREM_ALL_DOC_TYPES_USD]	MONEY NULL,
		[SUMMABLE_UEPR]					MONEY NULL,
		[SUMMABLE_UEPR_USD]				MONEY NULL,
		[SUMMABLE_UEPR_RPT_CURR1]		MONEY NULL,	
		[SUMMABLE_UEPR_RPT_CURR2]		MONEY NULL,	
		[SUMMABLE_DAC]					MONEY NULL,
		[SUMMABLE_DAC_USD]				MONEY NULL,
		[SUMMABLE_DAC_RPT_CURR1]		MONEY NULL,
		[SUMMABLE_DAC_RPT_CURR2]		MONEY NULL,
		[SUMMABLE_Brokerage]			MONEY NULL,
		[SUMMABLE_Brokerage_USD]		MONEY NULL,
		[SUMMABLE_Commission]			MONEY NULL,
		[SUMMABLE_Commission_USD]		MONEY NULL,
		[SUMMABLE_tax_nonrefund]		MONEY NULL,
		[SUMMABLE_tax_nonrefund_USD]	MONEY NULL,
		[SUMMABLE_tax_on_prem]			MONEY NULL,
		[SUMMABLE_tax_on_prem_USD]		MONEY NULL,
		[AdjustmentType]				VARCHAR(200) NULL,
		[aslob]							VARCHAR(20) NULL,
		[financial_lob]					VARCHAR(10) NULL,	
		[InsurerCode]					VARCHAR(20) NULL,
		[ICP_CEDED_FLG]					CHAR(1) NULL,
		[RPT_OFC_NM]					VARCHAR(100) NULL,
		[RPT_OFF_NAME]					VARCHAR(100) NULL,
		[T7_CODE]						VARCHAR(100) NULL,
		[T8_code]						VARCHAR(20) NULL,
		[T9_CODE]						CHAR(1) NULL,
		[MBU]							CHAR(3) NULL,
		[L01]							CHAR(3) NULL,
		[L02]							CHAR(3) NULL,
		[L03]							VARCHAR(7) NULL,
		[l04]							VARCHAR(1) NOT NULL,
		[L06]							CHAR(4) NULL,
		[l07]							VARCHAR(15) NULL,
		[L10]							VARCHAR(10) NULL,
		[GD1]							VARCHAR(10) NULL,	
		[Source]						VARCHAR(20) NULL,	
		[RPTCURR1_CD]					CHAR(3) NULL,
		[RPTCURR2_CD]					CHAR(3) NULL,
		[RPTCURR1]						FLOAT NULL,
		[RPTCURR2]						FLOAT NULL,
		[Blended_Rate]					DECIMAL(18,12) NULL,
		[SourceSystemKey]				BIGINT NULL,
		[lPolicySectionRCCSplitKey]		INT NULL,
		[lPolicyLiabilityCustomInstalmentKey] INT NULL,
        [DueDate]						DATE NULL ,
		[FromDate]						DATE NULL,
		[ToDate]						DATE NULL,
		[doc_key]						VARCHAR(25) NULL,
		[TransactionTypeCode]			VARCHAR(10) NULL,		
		[TransactionTypeCategory]		VARCHAR(50) NULL,
		--------------
		[DataHash]						VARBINARY(500) NULL
	)
	----------------------------------------------------------------------------------
	--#LGC
	----------------------------------------------------------------------------------
	DROP TABLE IF EXISTS #LGC
	
	SELECT *,reg_date = CAST(REPLACE(JoinMonth, '/', '-') + '-01' AS DATE)
	  INTO #LGC
	  FROM EDW_PREPROD.dbo.LOOKUP_GENIUS_CURRENCYRATES
	----------------------------------------------------------------------------------
	--#mapping
	----------------------------------------------------------------------------------
	DROP TABLE IF EXISTS #mapping

	SELECT DISTINCT 
			 plcy_SRC			,RPT_OFF_NAME		,DIV_NAME		
			,SUB_DEPT_CD		,PRO_RATA_XOL_NAME	,TRTY_FAC_NAME
			,DEPT_NAME			,DEPT_CD			,ICPFLAG
			,contract_NBR		,Contract_Reference	,actuariallob
			,sub_dept_name		,Financial_LOB		,t7_code = SunBranchCode
			,T8_CODE = SIF_OIF	,t9_code			,insurercode
			,CEDNG_COMPANY_NAME	,INCEPT_DT
	  INTO #mapping
	  FROM edw_preprod.dbo.MAP_CONTRACT_EDW
	 WHERE plcy_SRC='OPENBOX'

	----------------------------------------------------------------------------------
	--#openbox_Brok_Comm_Tax
	----------------------------------------------------------------------------------
	DROP TABLE IF EXISTS #CurrencyNameLookup

	SELECT
		 x.TIRS_CURRENCY_CODE
		,x.CURRENCY_NAME
	INTO #CurrencyNameLookup
	FROM (
	  SELECT etr.TIRS_CURRENCY_CODE
			,etr.CURRENCY_NAME
			,MostRecent = ROW_NUMBER() OVER (PARTITION BY etr.TIRS_CURRENCY_CODE ORDER BY etr.K1PERIOD_OF_TIME DESC)
		FROM EDW_PREPROD.dbo.EDW_TIRS_ROE etr
		) x
	WHERE 	
	x.MostRecent = 1
	----------------------------------------------------------------------------------
	--#AccountingPeriod
	----------------------------------------------------------------------------------
	DROP TABLE IF EXISTS #AccountingPeriod

	SELECT
		 x.AccountingPeriodDate
		,x.AccountingStartDate
		,x.AccountingEndDate
	INTO #AccountingPeriod
	FROM (
	  SELECT AccountingPeriodDate	= CAST(ap.accounting_period_date AS DATE)
			,AccountingStartDate	= CAST(DATEADD(DAY, 1, LAG(ap.accounting_period_close_date) OVER (ORDER BY ap.accounting_period_key)) AS DATE)
			,AccountingEndDate		= CAST(ap.accounting_period_close_date AS DATE)
		FROM Insight.dbo.accounting_periods ap
		) x
	WHERE x.AccountingStartDate IS NOT NULL
	----------------------------------------------------------------------------------
	--#ContractMap
	----------------------------------------------------------------------------------	
	DROP TABLE IF EXISTS #ContractMap
	
	SELECT DISTINCT
		 CONTRACT_NBR
		,CONTRACT_REFERENCE
	INTO #ContractMap
	FROM EDW_PREPROD.dbo.MAP_CONTRACT_EDW
	WHERE PLCY_SRC = 'OPENBOX'
	----------------------------------------------------------------------------------
	--#Currency
	----------------------------------------------------------------------------------		
	DROP TABLE IF EXISTS #Currency
	
	SELECT 
		 lCurrencyKey = c.lCurrencyKey
		,CurrencyCode = c.SCCY
		,CurrencyName = x.CURRENCY_NAME
	INTO #Currency
	FROM SRC_LLOYDS_DB.dbo.Currency c
	INNER JOIN (
	  SELECT etr.TIRS_CURRENCY_CODE
			,etr.CURRENCY_NAME
			,MostRecent = ROW_NUMBER() OVER (PARTITION BY etr.TIRS_CURRENCY_CODE ORDER BY etr.K1PERIOD_OF_TIME DESC)
		FROM EDW_PREPROD.dbo.EDW_TIRS_ROE etr
		) x
	 ON x.TIRS_CURRENCY_CODE = c.SCCY COLLATE DATABASE_DEFAULT
	AND x.MostRecent = 1

	-----------------------------------------------------------------------------------------------------------------------------	
	--Intermediate Measures – Instalment & Risk Split
	--For each instalment, calculates the cumulative percentage of amount (CumulativeAmountPC) and the previous cumulative amount
	-----------------------------------------------------------------------------------------------------------------------------	
	DROP TABLE IF EXISTS #InstalmentSplit
	
	SELECT
		 x.LPolicyLiabilityCustomInstalmentKEY
		,x.lPolicyLiabilityKey
		,x.NINSTALMENTSEQUENCE
		,x.DTDUE
		,x.NAMOUNTPC
		,PreviousCumulativeAmountPC = COALESCE(LAG(x.CumulativeAmountPC) OVER (PARTITION BY x.lPolicyLiabilityKey ORDER BY x.NINSTALMENTSEQUENCE, x.LPolicyLiabilityCustomInstalmentKEY), 0)
		,x.CumulativeAmountPC
	INTO #InstalmentSplit
	FROM (
		SELECT plci.LPolicyLiabilityCustomInstalmentKEY
			,plci.lPolicyLiabilityKey
			,plci.NINSTALMENTSEQUENCE
			,plci.DTDUE
			,plci.NAMOUNTPC
			,CumulativeAmountPC = COALESCE(CAST(SUM(plci.NAMOUNTPC) OVER (PARTITION BY plci.lPolicyLiabilityKey ORDER BY plci.NINSTALMENTSEQUENCE, plci.LPolicyLiabilityCustomInstalmentKEY) AS FLOAT) / NULLIF(SUM(plci.NAMOUNTPC) OVER (PARTITION BY plci.lPolicyLiabilityKey), 0), 1)
		 FROM SRC_LLOYDS_DB.dbo.PolicyLiabilityCustomInstalment plci
		INNER JOIN SRC_LLOYDS_DB.dbo.PolicyActivity				pa		ON  pa.lPolicyActivityKey = plci.lPolicyActivityKey
		INNER JOIN SRC_LLOYDS_DB.dbo.Typeofreportinglayer		torl	ON  torl.lTypeOfReportingLayerKey = pa.lTypeOfReportingLayerKey
		INNER JOIN SRC_LLOYDS_DB.dbo.TypeOfProductgroup			topg	ON  topg.lTypeOfProductGroupKey = torl.lTypeOfProductGroupKey
																		AND topg.sCode = 'RI'
		) x

	-----------------------------------------------------------------------------------------------------------------------------	
	--For each policy section split, calculates CumulativeSplitPC and the prior cumulative value
	-----------------------------------------------------------------------------------------------------------------------------	
	DROP TABLE IF EXISTS #RiskSplit
	
	SELECT
		 x.lPolicySectionRCCSplitKey
		,x.lPolicySectionKey
		,x.lTypeOfRCCKey
		,x.dSplitPC
		,PreviousCumulativeSplitPC = COALESCE(LAG(x.CumulativeSplitPC) OVER (PARTITION BY x.lPolicySectionKey ORDER BY x.lPolicySectionRCCSplitKey), 0)
		,x.CumulativeSplitPC
	INTO #RiskSplit
	FROM (
		SELECT psrs.lPolicySectionRCCSplitKey
			,psrs.lPolicySectionKey
			,psrs.lTypeOfRCCKey
			,psrs.dSplitPC
			,CumulativeSplitPC = COALESCE(  CAST(SUM(psrs.dSplitPC) OVER (PARTITION BY psrs.lPolicySectionKey ORDER BY psrs.lPolicySectionRCCSplitKey) AS FLOAT) / 
										  NULLIF(SUM(psrs.dSplitPC) OVER (PARTITION BY psrs.lPolicySectionKey), 0)
										, 1)
		FROM SRC_LLOYDS_DB.dbo.PolicySectionRCCSplit	  psrs
		INNER JOIN SRC_LLOYDS_DB.dbo.PolicyActivity		  pa	ON  pa.lPolicyActivityKey = psrs.lPolicyActivityKey
		INNER JOIN SRC_LLOYDS_DB.dbo.Typeofreportinglayer torl	ON  torl.lTypeOfReportingLayerKey = pa.lTypeOfReportingLayerKey
		INNER JOIN SRC_LLOYDS_DB.dbo.TypeOfProductgroup   topg	ON  topg.lTypeOfProductGroupKey = torl.lTypeOfProductGroupKey
																AND topg.sCode = 'RI'
		) x
	-----------------------------------------------------------------------------------------------------------------------------		
	--#WrittenPremium
	-----------------------------------------------------------------------------------------------------------------------------	
	DROP TABLE IF EXISTS #WrittenPremium
	
	SELECT
		 CONTRACT_NBR			= cm.CONTRACT_NBR COLLATE DATABASE_DEFAULT
		,ContractReference		= p.sPolicyReference
		,SourceSystemKey		= 30000000000 + z.lPolicyLiabilityKey
		,lPolicySectionRCCSplitKey = z.lPolicySectionRCCSplitKey
	    ,lPolicyLiabilityCustomInstalmentKey = z.lPolicyLiabilityCustomInstalmentKey
		,reg_date				= ap.AccountingPeriodDate
		,tirs_orig_curr_cd		= cur.CurrencyCode
		,tirs_orig_curr_name	= cur.CurrencyName
		,underwriting_year		= p.nYearOfAccount
		,tirs_uw_assm_ceded_name= 'Assumed'
		,TransactionTypeCode	= tp.sCode
		,TransactionTypeCategory= 'Premium Transaction Type'
		,DueDate				= CAST(ins.DTDUE AS DATE)
		,FromDate				= CAST(pa.dtPeriodFrom AS DATE)
		,ToDate					= CAST(pa.dtPeriodTo AS DATE)
		,doc_key				= pl.lPolicyLiabilityKey
		,WrittenPremium			= z.GrossWrittenPremium
		,WrittenPremiumUSD		= z.GrossWrittenPremiumUSD
	INTO #WrittenPremium
	FROM (
	  SELECT y.lPolicySectionKey
			,y.lPolicyLiabilityKey
			,y.lPolicySectionRCCSplitKey
			,ins.lPolicyLiabilityCustomInstalmentKey
			,GrossWrittenPremium	= CAST(ROUND(y.GrossWrittenPremium * ins.CumulativeAmountPC, 2)    - ROUND(y.GrossWrittenPremium * ins.PreviousCumulativeAmountPC, 2) AS DECIMAL(19,2))
			,GrossWrittenPremiumUSD = CAST(ROUND(y.GrossWrittenPremiumUSD * ins.CumulativeAmountPC, 2) - ROUND(y.GrossWrittenPremiumUSD * ins.PreviousCumulativeAmountPC, 2) AS DECIMAL(19,2))
		FROM (
		  SELECT x.lPolicyLiabilityKey
				,x.lPolicySectionKey
				,rs.lPolicySectionRCCSplitKey
				,GrossWrittenPremium	= CAST(ROUND(x.GrossWrittenPremium * rs.CumulativeSplitPC, 2)    - ROUND(x.GrossWrittenPremium * rs.PreviousCumulativeSplitPC, 2) AS DECIMAL(19,2))
				,GrossWrittenPremiumUSD = CAST(ROUND(x.GrossWrittenPremiumUSD * rs.CumulativeSplitPC, 2) - ROUND(x.GrossWrittenPremiumUSD * rs.PreviousCumulativeSplitPC, 2) AS DECIMAL(19,2))
			FROM (
			  SELECT pl.lPolicyLiabilityKey
					,pl.lPolicySectionKey
					,GrossWrittenPremium	= CAST(COALESCE(pl.dVersionGrossPremiumShareS, pl.dVersionGrossPremiumShareW, 0) AS DECIMAL(19, 2))
					,GrossWrittenPremiumUSD = CAST(ROUND(COALESCE(pl.dVersionGrossPremiumShareS, pl.dVersionGrossPremiumShareW, 0) / NULLIF(pl.dLiabilityPremiumROE, 0), 2) AS DECIMAL(19,2))
				FROM SRC_LLOYDS_DB.dbo.PolicyLiability 				pl
				INNER JOIN SRC_LLOYDS_DB.dbo.PolicySection 			ps		ON 	ps.lPolicySectionKey = pl.lPolicySectionKey
				INNER JOIN SRC_LLOYDS_DB.dbo.Policy 				p		ON 	p.lPolicyKey = pl.lPolicyKey
																			AND p.lActivePolicyActivityKey = pl.lPolicyActivityKey
				INNER JOIN SRC_LLOYDS_DB.dbo.PolicyActivity 		pa		ON 	pa.lPolicyActivityKey = pl.lPolicyActivityKey
				INNER JOIN SRC_LLOYDS_DB.dbo.Typeofreportinglayer	torl	ON 	torl.lTypeOfReportingLayerKey = pa.lTypeOfReportingLayerKey
				INNER JOIN SRC_LLOYDS_DB.dbo.TypeOfProductgroup		topg	ON 	topg.lTypeOfProductGroupKey = torl.lTypeOfProductGroupKey
																			AND topg.sCode = 'RI'
				INNER JOIN SRC_LLOYDS_DB.dbo.EntityInstanceStates	pseis	ON 	pseis.lInstanceKey = pl.lPolicySectionKey
																			AND pseis.lEntityKey = 614
				INNER JOIN SRC_LLOYDS_DB.dbo.EntitystateMembers 	psesm	ON 	psesm.lEntityStateMemberKey = pseis.lEntityStateMemberKey
																			AND psesm.sEntityStateMember IN ('Cancelled', 'Current', 'Endorsement Data Entry', 'Written')
				INNER JOIN SRC_LLOYDS_DB.dbo.EntityInstanceStates	peis	ON  peis.lInstanceKey = p.lPolicyKey
																			AND peis.lEntityKey = 608
				INNER JOIN SRC_LLOYDS_DB.dbo.EntitystateMembers 	pesm	ON  pesm.lEntityStateMemberKey = peis.lEntityStateMemberKey
																			AND pesm.sEntityStateMember IN ('Booked', 'Cancelled', 'Endorsement Data Entry', 'Expired', 'Renewed', 'Written')
				) x
			INNER JOIN #RiskSplit	rs	ON rs.lPolicySectionKey = x.lPolicySectionKey
			) y
		INNER JOIN #InstalmentSplit ins	ON ins.lPolicyLiabilityKey = y.lPolicyLiabilityKey
		) z
	INNER JOIN SRC_LLOYDS_DB.dbo.PolicyLiability	pl	ON pl.lPolicyLiabilityKey = z.lPolicyLiabilityKey
	INNER JOIN SRC_LLOYDS_DB.dbo.TypeOfPremium		tp	ON tp.lTypeOfPremiumKey = pl.lTypeOfPremiumKey
	INNER JOIN SRC_LLOYDS_DB.dbo.Policy				p	ON p.lPolicyKey = pl.lPolicyKey
	INNER JOIN SRC_LLOYDS_DB.dbo.PolicyActivity		pa	ON pa.lPolicyActivityKey = pl.lPolicyActivityKey
	INNER JOIN #Currency							cur	ON cur.lCurrencyKey = pl.lLiabilityPremiumCcyKey
	INNER JOIN #AccountingPeriod					ap	ON pa.dtPeriodFrom BETWEEN ap.AccountingStartDate AND ap.AccountingEndDate
	INNER JOIN #RiskSplit							rs	ON rs.lPolicySectionRCCSplitKey = z.lPolicySectionRCCSplitKey
	INNER JOIN #InstalmentSplit						ins	ON ins.LPolicyLiabilityCustomInstalmentKEY = z.LPolicyLiabilityCustomInstalmentKEY
	INNER JOIN #ContractMap							cm	ON cm.CONTRACT_REFERENCE = p.sPolicyReference COLLATE DATABASE_DEFAULT
	WHERE z.GrossWrittenPremium != 0
	----------
	UNION ALL
	----------
	SELECT cm.CONTRACT_NBR
		,ContractReference			= ma.PolicyNumber
		,SourceSystemKey			= NULL
		,lPolicySectionRCCSplitKey	= NULL
		,lPolicyLiabilityCustomInstalmentKey = NULL
		,reg_date 					= ma.AccountingDate
		,tirs_orig_curr_cd 			= ma.OriginalCurrencyCode
		,tirs_orig_curr_name 		= cur.CurrencyName
		,underwriting_year 			= ma.YOA
		,tirs_uw_assm_ceded_name	= ma.BusinessType
		,TransactionTypeCode		= NULL
		,TransactionTypeCategory	= NULL
		,DueDate 					= NULL
		,FromDate 					= NULL
		,ToDate 					= NULL
		,doc_key					= NULL
		,WrittenPremium 			= ma.GrossWrittenPremiumOrig
		,WrittenPremiumUSD 			= ma.GrossWrittenPremiumUSD
	 FROM SRC_LLOYDS_DB.SSIS.tbl_ep_gp_llyds_manual_adjustments ma
	INNER JOIN #ContractMap		cm	ON cm.CONTRACT_REFERENCE = ma.PolicyNumber COLLATE DATABASE_DEFAULT
	INNER JOIN #Currency		cur	ON cur.CurrencyCode = ma.OriginalCurrencyCode
	WHERE ma.BusinessType = 'Assumed'
	  AND ma.PolicySource = 'OPENBOX'
	  AND NOT (COALESCE(ma.GrossWrittenPremiumOrig, 0) = 0
	  AND COALESCE(ma.GrossWrittenPremiumUSD, 0) = 0)
	;

	-----------------------------------------------------------------------------------------------------------------------------		
	--#Deduction
	-----------------------------------------------------------------------------------------------------------------------------		
	DROP TABLE IF EXISTS #Deduction
	
	SELECT CONTRACT_NBR				= cm.CONTRACT_NBR COLLATE DATABASE_DEFAULT
		,ContractReference			= p.sPolicyReference
		,SourceSystemKey			= 40000000000 + z.lPolicyLiabilityDeductionKey
		,lPolicySectionRCCSplitKey	= z.lPolicySectionRCCSplitKey
		,lPolicyLiabilityCustomInstalmentKey = z.lPolicyLiabilityCustomInstalmentKey
		,reg_date					= ap.AccountingPeriodDate
		,tirs_orig_curr_cd			= cur.CurrencyCode
		,tirs_orig_curr_name 		= cur.CurrencyName
		,underwriting_year			= p.nYearOfAccount
		,tirs_uw_assm_ceded_name	= 'Assumed'
		,TransactionTypeCode		= tod.sCode
		,TransactionTypeCategory	= 'Deduction Transaction Type'
		,DueDate 					= CAST(ins.DTDUE AS DATE)
		,FromDate 					= CAST(pa.dtPeriodFrom AS DATE)
		,ToDate 					= CAST(pa.dtPeriodTo AS DATE)
		,doc_key					= pl.lPolicyLiabilityKey
		,Brokerage 					= IIF(z.DeductionType = 'BROKERAGE'  ,z.DeductionAmount 	,0)
		,BrokerageUSD 				= IIF(z.DeductionType = 'BROKERAGE'  ,z.DeductionAmountUSD 	,0)
		,Commission 				= IIF(z.DeductionType = 'COMMISSION' ,z.DeductionAmount 	,0)
		,CommissionUSD 				= IIF(z.DeductionType = 'COMMISSION' ,z.DeductionAmountUSD 	,0)
		,TaxNonRefund 				= IIF(z.DeductionType = 'TAX' 		 ,z.DeductionAmount 	,0)
		,TaxNonRefundUSD 			= IIF(z.DeductionType = 'TAX' 		 ,z.DeductionAmountUSD 	,0)
	INTO #Deduction
	FROM (
	  SELECT y.lPolicyLiabilityDeductionKey
			,y.lPolicySectionKey
			,y.lPolicyLiabilityKey
			,y.lPolicySectionRCCSplitKey
			,ins.lPolicyLiabilityCustomInstalmentKey
			,DeductionAmount	= CAST(ROUND(y.DeductionAmount * ins.CumulativeAmountPC, 2) - ROUND(y.DeductionAmount * ins.PreviousCumulativeAmountPC, 2) AS DECIMAL(19,2))
			,DeductionAmountUSD = CAST(ROUND(y.DeductionAmountUSD * ins.CumulativeAmountPC, 2) - ROUND(y.DeductionAmountUSD * ins.PreviousCumulativeAmountPC, 2) AS DECIMAL(19,2))
			,y.DeductionType
		FROM (
		  SELECT x.lPolicyLiabilityDeductionKey
				,x.lPolicySectionKey
				,lPolicyLiabilityKey
				,rs.lPolicySectionRCCSplitKey
				,DeductionAmount 	= CAST(ROUND(x.DeductionAmount * rs.CumulativeSplitPC, 2) - ROUND(x.DeductionAmount * rs.PreviousCumulativeSplitPC, 2) AS DECIMAL(19,2))
				,DeductionAmountUSD = CAST(ROUND(x.DeductionAmountUSD * rs.CumulativeSplitPC, 2) - ROUND(x.DeductionAmountUSD * rs.PreviousCumulativeSplitPC, 2) AS DECIMAL(19,2))
				,x.DeductionType
			FROM (
			  SELECT pld.lPolicyLiabilityDeductionKey
					,pld.lPolicySectionKey
					,pld.lPolicyLiabilityKey
					,DeductionAmount 	= CAST(CASE WHEN ps.dActualSignedLinePC IS NOT NULL THEN pld.dDeductionAmountS ELSE pld.dDeductionAmountW END AS DECIMAL(19,2))
					,DeductionAmountUSD = CAST(ROUND(CASE WHEN ps.dActualSignedLinePC IS NOT NULL THEN pld.dDeductionAmountS ELSE pld.dDeductionAmountW END / pl.dLiabilityPremiumROE, 2) AS DECIMAL(19,2))
					,DeductionType 		= tt.transaction_type_group
				FROM SRC_LLOYDS_DB.dbo.PolicyLiabilityDeduction 	pld
				INNER JOIN SRC_LLOYDS_DB.dbo.PolicyLiability 		pl		ON  pl.lPolicyLiabilityKey = pld.lPolicyLiabilityKey
				INNER JOIN SRC_LLOYDS_DB.dbo.Policy 				p		ON  p.lPolicyKey = pl.lPolicyKey
																				AND p.lActivePolicyActivityKey = pl.lPolicyActivityKey
				INNER JOIN SRC_LLOYDS_DB.dbo.PolicySection 			ps		ON  ps.lPolicySectionKey = pld.lPolicySectionKey
				INNER JOIN SRC_LLOYDS_DB.dbo.TypeofDeduction 		tod		ON  tod.lTypeOfDeductionkey = pld.lTypeOfDeductionKey
				INNER JOIN Insight.mapping.transaction_types 		tt		ON  tt.source_key = 1
																				AND tt.external_key = tod.lTypeOfDeductionkey
																				AND tt.external_group = 'Deductions'
																				AND tt.transaction_type_group IN ('TAX', 'BROKERAGE', 'COMMISSION')
				INNER JOIN SRC_LLOYDS_DB.dbo.PolicyActivity 		pa		ON  pa.lPolicyActivityKey = pld.lPolicyActivityKey
				INNER JOIN SRC_LLOYDS_DB.dbo.Typeofreportinglayer 	torl	ON  torl.lTypeOfReportingLayerKey = pa.lTypeOfReportingLayerKey
				INNER JOIN SRC_LLOYDS_DB.dbo.TypeOfProductgroup		topg	ON  topg.lTypeOfProductGroupKey = torl.lTypeOfProductGroupKey
																				AND topg.sCode = 'RI'
				INNER JOIN SRC_LLOYDS_DB.dbo.EntityInstanceStates 	pseis	ON 	pseis.lInstanceKey = pld.lPolicySectionKey
																				AND pseis.lEntityKey = 614
				INNER JOIN SRC_LLOYDS_DB.dbo.EntitystateMembers 	psesm	ON 	psesm.lEntityStateMemberKey = pseis.lEntityStateMemberKey
																				AND psesm.sEntityStateMember IN ('Cancelled', 'Current', 'Endorsement Data Entry', 'Written')
				INNER JOIN SRC_LLOYDS_DB.dbo.EntityInstanceStates 	peis	ON 	peis.lInstanceKey = pld.lPolicyKey
																				AND peis.lEntityKey = 608
				INNER JOIN SRC_LLOYDS_DB.dbo.EntitystateMembers 	pesm	ON 	pesm.lEntityStateMemberKey = peis.lEntityStateMemberKey
																				AND pesm.sEntityStateMember IN ('Booked', 'Cancelled', 'Endorsement Data Entry', 'Expired', 'Renewed', 'Written')
				) x
			INNER JOIN #RiskSplit	rs	ON rs.lPolicySectionKey = x.lPolicySectionKey
			WHERE x.DeductionAmount != 0
			) y
		INNER JOIN #InstalmentSplit ins	ON ins.lPolicyLiabilityKey = y.lPolicyLiabilityKey
		) z
	INNER JOIN SRC_LLOYDS_DB.dbo.PolicyLiabilityDeduction 	pld		ON pld.lPolicyLiabilityDeductionKey = z.lPolicyLiabilityDeductionKey
	INNER JOIN SRC_LLOYDS_DB.dbo.TypeofDeduction 			tod		ON tod.lTypeOfDeductionkey = pld.lTypeOfDeductionKey
	INNER JOIN SRC_LLOYDS_DB.dbo.PolicyLiability 			pl		ON pl.lPolicyLiabilityKey = z.lPolicyLiabilityKey
	INNER JOIN SRC_LLOYDS_DB.dbo.Policy 					p		ON p.lPolicyKey = pl.lPolicyKey
	INNER JOIN SRC_LLOYDS_DB.dbo.PolicyActivity 			pa		ON pa.lPolicyActivityKey = pl.lPolicyActivityKey
	INNER JOIN #Currency 									cur		ON cur.lCurrencyKey = pl.lLiabilityPremiumCcyKey
	INNER JOIN #AccountingPeriod 							ap		ON pa.dtPeriodFrom BETWEEN ap.AccountingStartDate AND ap.AccountingEndDate
	INNER JOIN #RiskSplit 									rs		ON rs.lPolicySectionRCCSplitKey = z.lPolicySectionRCCSplitKey
	INNER JOIN #InstalmentSplit 							ins		ON ins.LPolicyLiabilityCustomInstalmentKEY = z.LPolicyLiabilityCustomInstalmentKEY
	INNER JOIN #ContractMap 								cm		ON cm.CONTRACT_REFERENCE = p.sPolicyReference COLLATE DATABASE_DEFAULT

	----------------------------------------------------------------------------------
	--#EGL
	----------------------------------------------------------------------------------
	DROP TABLE IF EXISTS #EGL

	SELECT
		E.policyNumber, 
		E.AccountingDate,
		E.OriginalCurrencyCode,
		R.CURRENCY_NAME,
		yoa,
		businesstype,		
		GrossWrittenPremiumOrig			= CONVERT(MONEY, SUM(E.GrossWrittenPremiumOrig)),
		GrossWrittenPremiumUSD			= CONVERT(MONEY, SUM(E.GrossWrittenPremiumUSD)),
		GrossWrittenPremiumOrigUnearned	= CONVERT(MONEY, SUM(E.GrossWrittenPremiumOrigUnearned)),		
		GrossWrittenPremiumUSDUnearned	= CONVERT(MONEY, SUM(E.GrossWrittenPremiumUSDUnearned)),
		TotalDeductionsOrigUnearned		= CONVERT(MONEY, SUM(E.TotalDeductionsOrigUnearned)),
		TotalDeductionsUSDUNEarned		= CONVERT(MONEY, SUM(E.TotalDeductionsUSDUNEarned))

		INTO #EGL
		FROM edw_preprod.lloyds.tbl_ep_gp_llyds E
	   OUTER APPLY (SELECT TOP 1 R.TIRS_CURRENCY_CODE, R.CURRENCY_NAME  
					  FROM EDW_PREPROD.dbo.EDW_TIRS_ROE   R 
					 WHERE E.OriginalCurrencyCode=R.TIRS_CURRENCY_CODE ORDER BY R.K1PERIOD_OF_TIME desc) AS R	
	   WHERE businesstype='Assumed'
		 AND PolicySource='Openbox'
	  GROUP BY
		E.policyNumber, 
		E.AccountingDate ,
		E.OriginalCurrencyCode,
		R.CURRENCY_NAME,
		yoa,
		businesstype
	----------------------------------------------------------------------------------
	--#EGLBrokerCommissionTax
	----------------------------------------------------------------------------------
    DROP TABLE IF EXISTS #EGLBrokerCommissionTax
	
	SELECT 
		 CONTRACT_NBR			= CONTRACT_NBR		COLLATE DATABASE_DEFAULT
		,ContractReference		= ContractReference COLLATE DATABASE_DEFAULT
		,SourceSystemKey
		,lPolicySectionRCCSplitKey
		,lPolicyLiabilityCustomInstalmentKey
		,reg_date
		,tirs_orig_curr_cd		= tirs_orig_curr_cd		COLLATE DATABASE_DEFAULT
		,tirs_orig_curr_name	= tirs_orig_curr_name	COLLATE DATABASE_DEFAULT
		,underwriting_year
		,tirs_uw_assm_ceded_name= tirs_uw_assm_ceded_name COLLATE DATABASE_DEFAULT
		,TransactionTypeCode
		,TransactionTypeCategory
		,DueDate
		,FromDate
		,ToDate
		,doc_key					
		,WrittenPremium					= SUM(WrittenPremium)
	    ,WrittenPremiumUSD				= SUM(WrittenPremiumUSD)
		,GrossWrittenPremiumUnearned	= NULL
		,GrossWrittenPremiumUnearnedUSD	= NULL
		,TotalDeductionsUnearned		= NULL
		,TotalDeductionsUnearnedUSD		= NULL
		,Brokerage						= NULL 
		,BrokerageUSD					= NULL
		,Commission						= NULL
		,CommissionUSD					= NULL
		,PremiumTax						= NULL
	    ,PremiumTaxUSD					= NULL
		,TaxNonRefund					= NULL
		,TaxNonRefundUSD				= NULL
		,UEPRRPT1						= NULL
		,DACRPT1						= NULL
	INTO #EGLBrokerCommissionTax
	FROM #WrittenPremium
	GROUP BY 
		 CONTRACT_NBR
		,ContractReference
		,SourceSystemKey
		,lPolicySectionRCCSplitKey
		,lPolicyLiabilityCustomInstalmentKey
		,reg_date
		,tirs_orig_curr_cd
		,tirs_orig_curr_name
		,underwriting_year
		,tirs_uw_assm_ceded_name
		,TransactionTypeCode
		,TransactionTypeCategory
		,DueDate
		,FromDate
		,ToDate
		,doc_key
	------------
	UNION ALL
	------------
	SELECT 
		 CONTRACT_NBR			= CONTRACT_NBR		COLLATE DATABASE_DEFAULT
		,ContractReference		= ContractReference COLLATE DATABASE_DEFAULT
		,SourceSystemKey
		,lPolicySectionRCCSplitKey
		,lPolicyLiabilityCustomInstalmentKey
		,reg_date
		,tirs_orig_curr_cd		= tirs_orig_curr_cd		COLLATE DATABASE_DEFAULT
		,tirs_orig_curr_name	= tirs_orig_curr_name	COLLATE DATABASE_DEFAULT
		,underwriting_year
		,tirs_uw_assm_ceded_name= tirs_uw_assm_ceded_name COLLATE DATABASE_DEFAULT
		,TransactionTypeCode
		,TransactionTypeCategory
		,DueDate
		,FromDate
		,ToDate
		,doc_key
		,WrittenPremium					= NULL
		,WrittenPremiumUSD				= NULL
		,GrossWrittenPremiumUnearned	= NULL
		,GrossWrittenPremiumUnearnedUSD	= NULL
		,TotalDeductionsUnearned		= NULL
		,TotalDeductionsUnearnedUSD		= NULL
		,Brokerage						= SUM(Brokerage)
		,BrokerageUSD					= SUM(BrokerageUSD)
		,Commission						= SUM(Commission)
		,CommissionUSD					= SUM(CommissionUSD)
		,PremiumTax						= NULL
		,PremiumTaxUSD					= NULL
		,TaxNonRefund					= SUM(TaxNonRefund)
		,TaxNonRefundUSD				= SUM(TaxNonRefundUSD)
		,UEPRRPT1						= NULL
		,DACRPT1						= NULL
	FROM #Deduction
	GROUP BY 
		 CONTRACT_NBR
		,ContractReference
		,SourceSystemKey
		,lPolicySectionRCCSplitKey
		,lPolicyLiabilityCustomInstalmentKey
		,reg_date
		,tirs_orig_curr_cd
		,tirs_orig_curr_name
		,underwriting_year
		,tirs_uw_assm_ceded_name
		,TransactionTypeCode
		,TransactionTypeCategory
		,DueDate
		,FromDate
		,ToDate
		,doc_key
	-----------
	UNION ALL
	-----------
	SELECT
		 x.CONTRACT_NBR
		,x.ContractReference
		,SourceSystemKey					= NULL
		,lPolicySectionRCCSplitKey			= NULL
		,lPolicyLiabilityCustomInstalmentKey= NULL
		,x.reg_date
		,x.tirs_orig_curr_cd
		,x.tirs_orig_curr_name
		,x.underwriting_year
		,x.tirs_uw_assm_ceded_name
		,TransactionTypeCode	= NULL
		,TransactionTypeCategory= NULL
		,DueDate				= NULL
		,FromDate				= NULL
		,ToDate					= NULL
		,doc_key				= NULL
		,WrittenPremium			= 0
		,WrittenPremiumUSD		= 0
		,x.GrossWrittenPremiumUnearned
		,x.GrossWrittenPremiumUnearnedUSD
		,x.TotalDeductionsUnearned
		,x.TotalDeductionsUnearnedUSD
		,Brokerage				= 0
		,BrokerageUSD			= 0
		,Commission				= 0
		,CommissionUSD			= 0
		,PremiumTax				= 0
		,PremiumTaxUSD			= 0
		,TaxNonRefund			= 0
		,TaxNonRefundUSD		= 0
		,UEPRRPT1				= COALESCE(x.UEPRRPT1RunningTotal, 0) - COALESCE(LAG(x.UEPRRPT1RunningTotal) OVER (PARTITION BY x.CONTRACT_NBR, x.tirs_orig_curr_cd ORDER BY x.reg_date), 0)
		,DACRPT1				= COALESCE(x.DACRPT1RunningTotal, 0)  - COALESCE(LAG(x.DACRPT1RunningTotal)  OVER (PARTITION BY x.CONTRACT_NBR, x.tirs_orig_curr_cd ORDER BY x.reg_date), 0)
	FROM (
		SELECT
			 CONTRACT_NBR				= e.PolicyNumber COLLATE DATABASE_DEFAULT
			,ContractReference			= e.PolicyNumber COLLATE DATABASE_DEFAULT
			,reg_date					= e.AccountingDate
			,tirs_orig_curr_cd			= e.OriginalCurrencyCode COLLATE DATABASE_DEFAULT
			,tirs_orig_curr_name		= e.CURRENCY_NAME
			,underwriting_year			= e.yoa
			,tirs_uw_assm_ceded_name	= e.businesstype
			,GrossWrittenPremiumUnearned	= COALESCE(e.GrossWrittenPremiumOrigUnearned, 0)
			,GrossWrittenPremiumUnearnedUSD	= COALESCE(e.GrossWrittenPremiumUSDUnearned, 0)
			,TotalDeductionsUnearned		= COALESCE(e.TotalDeductionsOrigUnearned, 0)
			,TotalDeductionsUnearnedUSD		= COALESCE(e.TotalDeductionsUSDUNEarned, 0)
			,UEPRRPT1RunningTotal			= SUM(e.GrossWrittenPremiumOrigUnearned) OVER (PARTITION BY e.PolicyNumber, e.OriginalCurrencyCode ORDER BY e.AccountingDate)
											  *
											  SUM(e.GrossWrittenPremiumOrig * CONVERT(FLOAT, IIF(e.OriginalCurrencyCode = 'USD', 1, ofx.EXCHANGERATE) * ( 1 / rpt1fx.EXCHANGERATE) )) 
											  OVER (PARTITION BY e.PolicyNumber, e.OriginalCurrencyCode ORDER BY e.AccountingDate) 
											  /
											  NULLIF(SUM(e.GrossWrittenPremiumOrig) OVER (PARTITION BY e.PolicyNumber, e.OriginalCurrencyCode ORDER BY e.AccountingDate), 0)
			,DACRPT1RunningTotal			=-SUM(e.TotalDeductionsOrigUnearned)    OVER (PARTITION BY e.PolicyNumber, e.OriginalCurrencyCode ORDER BY e.AccountingDate) 
											  *
											  SUM(e.GrossWrittenPremiumOrig * CONVERT(FLOAT, IIF(e.OriginalCurrencyCode = 'USD', 1, ofx.EXCHANGERATE) * ( 1 / rpt1fx.EXCHANGERATE) ))
											  OVER (PARTITION BY e.PolicyNumber, e.OriginalCurrencyCode ORDER BY e.AccountingDate) 
											  /
											  NULLIF(SUM(e.GrossWrittenPremiumOrig) OVER (PARTITION BY e.PolicyNumber, e.OriginalCurrencyCode ORDER BY e.AccountingDate), 0)
		FROM #EGL		e
		LEFT JOIN #LGC	ofx		ON  ofx.ISOCode COLLATE DATABASE_DEFAULT = e.OriginalCurrencyCode
								AND ofx.reg_date = e.AccountingDate
		LEFT JOIN #LGC	rpt1fx	ON	rpt1fx.ISOCode COLLATE DATABASE_DEFAULT = 'GBP'
								AND rpt1fx.reg_date = e.AccountingDate
		) x;
					
    ----------------------------------------------------------------------------------
	--#OpenBox_UW_Stage 1
	----------------------------------------------------------------------------------
	;WITH openbox AS 
	(
	SELECT 
		[TREATY_NBR]				= 'OB',
		[UNDERWRITING_YEAR]			= ebct.UNDERWRITING_YEAR,
		[CONTRACT_NBR]				= M.contract_NBR,
		[ASSUMED_CEDED_FLG]			= 'A',
		[TIRS_ORIG_CURR_CD]			= ebct.TIRS_ORIG_CURR_CD,
		[TIRS_ORIG_CURR_NAME]		= ebct.TIRS_ORIG_CURR_NAME,
		[lob_name]					= ISNULL(M.SUB_DEPT_NAME,'N/A'),
		[actuariallob]				= m.actuariallob,
		[reg_date]					= ebct.reg_date,
		[aslob]						= '0',
		[Blended_Rate]				= 1,
		[AdjustmentType]			= 'N/A',
		[TIRS_UW_ASSM_CEDED_NAME]	= ebct.TIRS_UW_ASSM_CEDED_NAME,
		[Financial_LOB]				= M.Financial_LOB,
		[T7_CODE]					= M.t7_code,
		[T8_CODE]					= M.T8_Code,
		[T9_CODE]					= M.T9_code,
		[InsurerCode]				= M.InsurerCode,
		[ICP_CEDED_FLG]				= M.ICPFLAG,
		[solvency_II_regulatory_key]= solII.solvency_II_regulatory_key,
		[RPT_OFC_NM]				= LMAP.rpt_ofc_nm,
		[RPT_OFF_NAME]				= M.RPT_OFF_NAME,
		[MBU]						= 'LYC',
		[L01]						= 'LSL',
		[L02]						= LMAP.L02,
		[L03]						= LMAP.L03,
		[L04]						= '',
		[L06]						= 'LLON',
		[L07]						= SOLII_L.Fairfax_LOB_LCode + ISNULL(CM.FairFaxAbbrv_Code,'ZZZ') COLLATE DATABASE_DEFAULT,
		[L10]						= CAST(ebct.UNDERWRITING_YEAR AS CHAR(4)),
		[GD1]						= 'OPENBOX',
		[SOURCE]					= 'OPENBOX',
		[SUMMABLE_WRTN_PREM_ALL_DOC_TYPES]		= CAST(ebct.WrittenPremium as money),
		[SUMMABLE_WRTN_PREM_ALL_DOC_TYPES_USD]	= CAST(ebct.WrittenPremiumUSD as money),	
		[SUMMABLE_Brokerage]					= CAST(ebct.Brokerage as money),	
		[SUMMABLE_Brokerage_USD]				= CAST(ebct.BrokerageUSD as money),
		[SUMMABLE_Commission]					= CAST(ebct.Commission as money),
		[SUMMABLE_Commission_USD]				= CAST(ebct.CommissionUSD as money),
		[SUMMABLE_tax_on_prem]					= CAST(ebct.PremiumTax as money),
		[SUMMABLE_tax_on_prem_USD]				= CAST(ebct.PremiumTaxUSD as money),
		[SUMMABLE_tax_nonrefund]				= CAST(ebct.TaxNonRefund as money),
		[SUMMABLE_tax_nonrefund_USD]			= CAST(ebct.TaxNonRefundUSD as money),
		[SUMMABLE_UEPR]							= CAST(ebct.GrossWrittenPremiumUnearned as money),		
		[SUMMABLE_UEPR_USD]						= CAST(ebct.GrossWrittenPremiumUnearnedUSD as money),
		[SUMMABLE_DAC]							= CAST(ebct.TotalDeductionsUnearned as money) * -1,
		[SUMMABLE_DAC_USD]						= CAST(ebct.TotalDeductionsUnearnedUSD as money)  * -1,
		--[UEPR_Run_Tot_RPT_CURR1]				= SUM(ebct.GrossWrittenPremiumUnearned) OVER (PARTITION BY  M.contract_NBR, ebct.TIRS_ORIG_CURR_CD ORDER BY ebct.reg_date) * SUM((ebct.WrittenPremium * CAST( iif (ebct.TIRS_ORIG_CURR_CD = 'USD', 1, R.EXCHANGERATE) *( 1/RT1.EXCHANGERATE) AS FLOAT))  )OVER (PARTITION BY  M.contract_NBR, ebct.TIRS_ORIG_CURR_CD ORDER BY ebct.reg_date) / NULLIF(SUM( ebct.WrittenPremium )OVER (PARTITION BY  M.contract_NBR, ebct.TIRS_ORIG_CURR_CD ORDER BY ebct.reg_date),0),
		--[DAC_Run_Tot_RPT_CURR1]				= SUM(ebct.TotalDeductionsUnearned)     OVER (PARTITION BY  M.contract_NBR, ebct.TIRS_ORIG_CURR_CD ORDER BY ebct.reg_date) * SUM((ebct.WrittenPremium * CAST( iif (ebct.TIRS_ORIG_CURR_CD = 'USD', 1, R.EXCHANGERATE) *( 1/RT1.EXCHANGERATE) AS FLOAT))  )OVER (PARTITION BY  M.contract_NBR, ebct.TIRS_ORIG_CURR_CD ORDER BY ebct.reg_date) / NULLIF(SUM( ebct.WrittenPremium )OVER (PARTITION BY  M.contract_NBR, ebct.TIRS_ORIG_CURR_CD ORDER BY ebct.reg_date),0),
		[SUMMABLE_UEPR_RPT_CURR1]				= CAST(ebct.UEPRRPT1 AS MONEY),
		[SUMMABLE_DAC_RPT_CURR1]				= CAST(ebct.DACRPT1 AS MONEY),
		[RPTCURR1_CD]							= 'GBP',
		[RPTCURR2_CD]							= NULL,
		[RPTCURR1]								= CAST( iif (ebct.TIRS_ORIG_CURR_CD = 'USD', 1, R.EXCHANGERATE) *( 1/RT1.EXCHANGERATE) AS FLOAT),
		[RPTCURR2]								= NULL
		,[SourceSystemKey]						= ebct.SourceSystemKey
		,lPolicySectionRCCSplitKey				= ebct.lPolicySectionRCCSplitKey
		,lPolicyLiabilityCustomInstalmentKey	= ebct.lPolicyLiabilityCustomInstalmentKey
		,[DueDate]								= ebct.DueDate
		,[FromDate]								= ebct.FromDate
		,[ToDate]								= ebct.ToDate
		,[doc_key]								= ebct.doc_key
		,[TransactionTypeCode]					= ebct.TransactionTypeCode
		,[TransactionTypeCategory]				= ebct.TransactionTypeCategory
	FROM #EGLBrokerCommissionTax	ebct
	LEFT JOIN #Mapping										M		ON M.Contract_Reference = ebct.ContractReference COLLATE DATABASE_DEFAULT
	LEFT JOIN EDW_PREPROD.dbo.solvency_II_regulatory_etl	solII	ON  solII.source = M.PLCY_SRC
																	AND solII.assumed_or_direct = 'assumed'
																	AND	ISNULL(solII.branch_name,'Uncoded')				= ISNULL(M.RPT_OFF_NAME,'Uncoded')
																	AND ISNULL(solII.product_group_name,'Uncoded')		= ISNULL(M.DIV_NAME,'Uncoded')
																	AND ISNULL(solII.product_department_name,'Uncoded') = ISNULL(M.DEPT_NAME,'Uncoded')
																	AND ISNULL(solII.product_department_code,'Uncoded') = ISNULL(M.DEPT_CD,'Uncoded')
																	AND ISNULL(solII.lob_name,'Uncoded')				= ISNULL(M.SUB_DEPT_NAME,'Uncoded')
																	AND ISNULL(solII.lob_code,'Uncoded')				= ISNULL(M.SUB_DEPT_CD,'Uncoded')
																	AND ISNULL(solII.prorata_or_xol,'Uncoded')			= ISNULL(M.PRO_RATA_XOL_NAME,'Uncoded')
																	AND ISNULL(solII.treaty_or_fav,'Uncoded')			= ISNULL(M.TRTY_FAC_NAME,'Uncoded')
																	AND ISNULL(solII.property_or_casualty,'Uncoded')	= ISNULL(CASE	WHEN M.DIV_NAME LIKE '%property%'	THEN 'PROPERTY'
																																		WHEN M.DIV_NAME LIKE '%marine%'		THEN 'PROPERTY'
																																		ELSE 'CASUALTY' END,'Uncoded')
																	AND COALESCE(solII.InceptionFrom, M.INCEPT_DT, '1 Jan 1900') <= COALESCE(M.INCEPT_DT, '1 Jan 1900')
																	AND COALESCE(solII.InceptionTo, M.INCEPT_DT, '1 Jan 1900')   >= COALESCE(M.INCEPT_DT, '1 Jan 1900')
	LEFT JOIN EDW_PREPROD.dbo.solvency_II_regulatory_lookup SOLII_L ON SOLII_L.solvency_II_regulatory_key=solII.solvency_II_regulatory_key
	LEFT JOIN MDS.MDM.Ceding_Company						CM		ON CM.Code=M.CEDNG_COMPANY_NAME COLLATE DATABASE_DEFAULT
	OUTER APPLY ( SELECT TOP 1 * 
					FROM DM_DataStandard.TIRS.l02_L03_mapping LMAP 
				   WHERE 1=1
					 AND ISNULL(NULLIF(CAST( LMAP.rpt_ofc_nm	AS VARCHAR(100)),'%') ,ISNULL(M.RPT_OFF_NAME COLLATE DATABASE_DEFAULT,''))	= ISNULL(M.RPT_OFF_NAME COLLATE DATABASE_DEFAULT,'')
					 AND ISNULL(NULLIF(CAST( LMAP.DIV_NAME		AS VARCHAR(100)),'%') ,ISNULL(M.DIV_NAME COLLATE DATABASE_DEFAULT ,''))		= ISNULL(M.DIV_NAME COLLATE DATABASE_DEFAULT,'')
					 AND ISNULL(NULLIF(CAST( LMAP.DEPT_NAME		AS VARCHAR(100)),'%') ,ISNULL(M.DEPT_NAME COLLATE DATABASE_DEFAULT ,''))	= ISNULL(M.DEPT_NAME COLLATE DATABASE_DEFAULT,'')
					 AND ISNULL(NULLIF(CAST( LMAP.SUB_DEPT_NAME AS VARCHAR(100)),'%') ,ISNULL(M.SUB_DEPT_NAME COLLATE DATABASE_DEFAULT,''))	= ISNULL(M.SUB_DEPT_NAME COLLATE DATABASE_DEFAULT,'')
					 AND ISNULL(NULLIF(CAST( LMAP.YearOfAccount AS VARCHAR(100)),'%') ,ISNULL(CAST (ebct.UNDERWRITING_YEAR  AS char(4))  ,''))				= ISNULL(CAST (ebct.UNDERWRITING_YEAR  as char(4)) ,'')
					 AND ISNULL(NULLIF(CAST( LMAP.t9			AS VARCHAR(100)),'%') ,ISNULL(M.t9_code  COLLATE DATABASE_DEFAULT,''))		= ISNULL(M.t9_code COLLATE DATABASE_DEFAULT,'')
					 AND ISNULL(NULLIF(CAST( LMAP.PolicySource  AS VARCHAR(100)),'%') ,ISNULL(M.PLCY_SRC  COLLATE DATABASE_DEFAULT,''))		= ISNULL(M.PLCY_SRC COLLATE DATABASE_DEFAULT,'')
					ORDER BY Priority_Key DESC 
				) LMAP
	LEFT JOIN #LGC R	ON  R.ISOCode COLLATE DATABASE_DEFAULT = ebct.TIRS_ORIG_CURR_CD	AND R.JoinMonth		= FORMAT(ebct.reg_date, 'yyyy/MM', 'en-US' )
	LEFT JOIN #LGC RT1	ON  RT1.ISOCode COLLATE DATABASE_DEFAULT='GBP'					AND RT1.JoinMonth	= FORMAT(ebct.reg_date, 'yyyy/MM', 'en-US' )
	)
	INSERT INTO #OpenBox_UW_Stage
	(
		 [TREATY_NBR] 
		,[UNDERWRITING_YEAR] 
		,[CONTRACT_NBR] 
		,[reg_date]
		,[ASSUMED_CEDED_FLG] 
		,[TIRS_UW_ASSM_CEDED_NAME] 
		,[TIRS_ORIG_CURR_CD] 
		,[TIRS_ORIG_CURR_NAME] 
		,[lob_name] 
		,[ActuarialLob] 
		,[solvency_II_regulatory_key]
		,[SUMMABLE_WRTN_PREM_ALL_DOC_TYPES]
		,[SUMMABLE_WRTN_PREM_ALL_DOC_TYPES_USD]
		,[SUMMABLE_UEPR]
		,[SUMMABLE_UEPR_USD]
		,[SUMMABLE_UEPR_RPT_CURR1]	
		,[SUMMABLE_UEPR_RPT_CURR2]
		,[SUMMABLE_DAC]
		,[SUMMABLE_DAC_USD]
		,[SUMMABLE_DAC_RPT_CURR1]
		,[SUMMABLE_DAC_RPT_CURR2]
		,[SUMMABLE_Brokerage]
		,[SUMMABLE_Brokerage_USD]
		,[SUMMABLE_Commission]
		,[SUMMABLE_Commission_USD]
		,[SUMMABLE_tax_nonrefund]
		,[SUMMABLE_tax_nonrefund_USD]
		,[SUMMABLE_tax_on_prem]
		,[SUMMABLE_tax_on_prem_USD]
		,[AdjustmentType]
		,[aslob]
		,[financial_lob]
		,[InsurerCode]
		,[ICP_CEDED_FLG] 
		,[RPT_OFC_NM]
		,[RPT_OFF_NAME]
		,[T7_CODE]
		,[T8_code]
		,[T9_CODE] 
		,[MBU]
		,[L01]
		,[L02]
		,[L03]
		,[l04]
		,[L06] 
		,[l07]
		,[L10]
		,[GD1]
		,[Source]	
		,[RPTCURR1_CD]
		,[RPTCURR2_CD]
		,[RPTCURR1]
		,[RPTCURR2]
		,[Blended_Rate]
		,[SourceSystemKey]
		,lPolicySectionRCCSplitKey
		,lPolicyLiabilityCustomInstalmentKey
		,[DueDate]
		,[FromDate] 
		,[ToDate] 
		,[doc_key]
		,[TransactionTypeCode]		
		,[TransactionTypeCategory]
	)    
	SELECT 
		 [TREATY_NBR] 
		,[UNDERWRITING_YEAR] 
		,[CONTRACT_NBR] 
		,[reg_date]
		,[ASSUMED_CEDED_FLG] 
		,[TIRS_UW_ASSM_CEDED_NAME] 
		,[TIRS_ORIG_CURR_CD] 
		,[TIRS_ORIG_CURR_NAME] 
		,[lob_name] 
		,[ActuarialLob] 
		,[solvency_II_regulatory_key]
		,[SUMMABLE_WRTN_PREM_ALL_DOC_TYPES]		= SUM([SUMMABLE_WRTN_PREM_ALL_DOC_TYPES])
		,[SUMMABLE_WRTN_PREM_ALL_DOC_TYPES_USD]	= SUM([SUMMABLE_WRTN_PREM_ALL_DOC_TYPES_USD])
		,[SUMMABLE_UEPR]						= SUM([SUMMABLE_UEPR])
		,[SUMMABLE_UEPR_USD]					= SUM([SUMMABLE_UEPR_USD])
		,[SUMMABLE_UEPR_RPT_CURR1]				= SUM([SUMMABLE_UEPR_RPT_CURR1])
		,[SUMMABLE_UEPR_RPT_CURR2]				= 0
		,[SUMMABLE_DAC]							= SUM([SUMMABLE_DAC])
		,[SUMMABLE_DAC_USD]						= SUM([SUMMABLE_DAC_USD]) 
		,[SUMMABLE_DAC_RPT_CURR1]				= SUM([SUMMABLE_DAC_RPT_CURR1])
		,[SUMMABLE_DAC_RPT_CURR2]				= 0
		,[SUMMABLE_Brokerage]					= SUM([SUMMABLE_Brokerage])
		,[SUMMABLE_Brokerage_USD]				= SUM([SUMMABLE_Brokerage_USD])
		,[SUMMABLE_Commission]					= SUM([SUMMABLE_Commission])
		,[SUMMABLE_Commission_USD]				= SUM([SUMMABLE_Commission_USD])
		,[SUMMABLE_tax_nonrefund]				= SUM([SUMMABLE_tax_nonrefund])
		,[SUMMABLE_tax_nonrefund_USD]			= SUM([SUMMABLE_tax_nonrefund_USD])
		,[SUMMABLE_tax_on_prem]					= SUM([SUMMABLE_tax_on_prem])
		,[SUMMABLE_tax_on_prem_USD]				= SUM([SUMMABLE_tax_on_prem_USD])
		,[AdjustmentType]
		,[aslob]
		,[financial_lob]
		,[InsurerCode]
		,[ICP_CEDED_FLG] 
		,[RPT_OFC_NM]
		,[RPT_OFF_NAME]
		,[T7_CODE]
		,[T8_code]
		,[T9_CODE] 
		,[MBU]
		,[L01]
		,[L02]
		,[L03]
		,[l04]
		,[L06] 
		,[l07]
		,[L10]
		,[GD1]
		,[Source]	
		,[RPTCURR1_CD]
		,[RPTCURR2_CD]
		,[RPTCURR1]
		,[RPTCURR2]
		,[Blended_Rate]
		,[SourceSystemKey]
		,lPolicySectionRCCSplitKey
		,lPolicyLiabilityCustomInstalmentKey
		,[DueDate]
		,[FromDate] 
		,[ToDate] 
		,[doc_key]
		,[TransactionTypeCode]		
		,[TransactionTypeCategory]
	FROM openbox
	GROUP BY 
		 [TREATY_NBR] 
		,[UNDERWRITING_YEAR] 
		,[CONTRACT_NBR] 
		,[reg_date]
		,[ASSUMED_CEDED_FLG] 
		,[TIRS_UW_ASSM_CEDED_NAME] 
		,[TIRS_ORIG_CURR_CD] 
		,[TIRS_ORIG_CURR_NAME] 
		,[lob_name] 
		,[ActuarialLob] 
		,[solvency_II_regulatory_key]
		,[AdjustmentType]
		,[aslob]
		,[financial_lob]
		,[InsurerCode]
		,[ICP_CEDED_FLG] 
		,[RPT_OFC_NM]
		,[RPT_OFF_NAME]
		,[T7_CODE]
		,[T8_code]
		,[T9_CODE] 
		,[MBU]
		,[L01]
		,[L02]
		,[L03]
		,[l04]
		,[L06] 
		,[l07]
		,[L10]
		,[GD1]
		,[Source]	
		,[RPTCURR1_CD]
		,[RPTCURR2_CD]
		,[RPTCURR1]
		,[RPTCURR2]
		,[Blended_Rate]
		,[SourceSystemKey]
		,lPolicySectionRCCSplitKey
		,lPolicyLiabilityCustomInstalmentKey
		,[DueDate]
		,[FromDate] 
		,[ToDate] 
		,[doc_key]
		,[TransactionTypeCode]		
		,[TransactionTypeCategory]

	/*
	----------------------------------------------------------------------------------
	--#OpenBox_UW_Stage 2
	----------------------------------------------------------------------------------
	;WITH a AS 
	(
	 SELECT 
		CONTRACT_NBR,
		UNDERWRITING_YEAR ,
		reg_date,
		TIRS_ORIG_CURR_CD,
		TIRS_ORIG_CURR_NAME,
		TIRS_UW_ASSM_CEDED_NAME,
		lob_name,
		AdjustmentType,
		L01,
		L02,
		L03,
		L06,
		L07,
		L10,
		RPTCURR1,
		RPTCURR1_CD,
		RPTCURR2_CD,
		SUMMABLE_UEPR,
		SUMMABLE_UEPR_USD,
		SUMMABLE_WRTN_PREM_ALL_DOC_TYPES,
		SUMMABLE_WRTN_PREM_ALL_DOC_TYPES_USD,
		SUMMABLE_UEPR_RPT_CURR1,
		SUMMABLE_UEPR_RPT_CURR2,
		SUMMABLE_DAC_RPT_CURR1,
		SUMMABLE_DAC_RPT_CURR2,
		WP_RT_RPT_CUR1	= ISNULL(SUM(SUMMABLE_WRTN_PREM_ALL_DOC_TYPES * RPTCURR1) OVER (PARTITION BY lob_name, l01, CONTRACT_NBR,TIRS_ORIG_CURR_CD,TIRS_UW_ASSM_CEDED_NAME,l02,l03,l06,l07,l10	ORDER BY reg_date ),0),
		WP_RT_RPT_CUR2	= ISNULL(SUM(SUMMABLE_WRTN_PREM_ALL_DOC_TYPES * RPTCURR2) OVER (PARTITION by lob_name, l01, CONTRACT_NBR,TIRS_ORIG_CURR_CD,TIRS_UW_ASSM_CEDED_NAME,l02,l03,l06,l07,l10    order by reg_date ),0),
		COMM_RT_RPT_CUR1= ISNULL(SUM((ISNULL(SUMMABLE_Brokerage,0)+ISNULL(SUMMABLE_tax_nonrefund,0)+ISNULL(SUMMABLE_tax_on_prem,0)+ISNULL(SUMMABLE_Commission,0))  * RPTCURR1 )OVER (PARTITION BY lob_name, l01, CONTRACT_NBR,TIRS_ORIG_CURR_CD,TIRS_UW_ASSM_CEDED_NAME,l02,l03,l06,l07,l10 ORDER BY  reg_date),0),
		COMM_RT_RPT_CUR2= ISNULL(SUM((ISNULL(SUMMABLE_Brokerage,0)+ISNULL(SUMMABLE_tax_nonrefund,0)+ISNULL(SUMMABLE_tax_on_prem,0)+ISNULL(SUMMABLE_Commission,0))  * RPTCURR2 )OVER  (PARTITION BY lob_name, l01, CONTRACT_NBR,TIRS_ORIG_CURR_CD,TIRS_UW_ASSM_CEDED_NAME,l02,l03,l06,l07,l10 ORDER BY  reg_date),0) ,
		UEPR_RT_RATE	= ISNULL(CAST(SUM( CAST(SUMMABLE_UEPR  AS FLOAT)) OVER (PARTITION BY lob_name, l01, CONTRACT_NBR,TIRS_ORIG_CURR_CD,TIRS_UW_ASSM_CEDED_NAME,l02,l03,l06,l07,l10 order by  reg_date ) as float)
									/ 
								 CAST(NULLIF(SUM(NULLIF( CAST(SUMMABLE_WRTN_PREM_ALL_DOC_TYPES AS FLOAT),0))OVER (PARTITION  BY lob_name, l01, CONTRACT_NBR,TIRS_ORIG_CURR_CD,TIRS_UW_ASSM_CEDED_NAME,l02,l03,l06,l07,l10  order by  reg_date),0) as float)
								,0),

		DAC_RT_RATE	= ISNULL(SUM( CAST(SUMMABLE_DAC  AS FLOAT)) OVER (PARTITION BY lob_name, l01, CONTRACT_NBR,TIRS_ORIG_CURR_CD,TIRS_UW_ASSM_CEDED_NAME,l02,l03,l06,l07,l10 order by  reg_date) 
									/ 
									NULLIF(SUM(NULLIF( CAST( ISNULL(SUMMABLE_Brokerage,0)+ISNULL(SUMMABLE_tax_nonrefund,0)+  ISNULL(SUMMABLE_tax_on_prem,0)+ISNULL(SUMMABLE_Commission,0) AS FLOAT),0))OVER (PARTITION  by lob_name, l01, CONTRACT_NBR,TIRS_ORIG_CURR_CD,TIRS_UW_ASSM_CEDED_NAME,l02,l03,l06,L07,l10  ORDER by  reg_date),0)
								,0)	
	 FROM #OpenBox_UW_Stage
	WHERE RPTCURR1_CD <> ''
	)
	,b AS 
	(
	 SELECT
		a.CONTRACT_NBR,
		a.UNDERWRITING_YEAR,
		a.reg_date,
		a.TIRS_ORIG_CURR_CD,
		a.TIRS_ORIG_CURR_NAME,
		a.TIRS_UW_ASSM_CEDED_NAME,
		a.lob_name,
		a.AdjustmentType,
		a.L01,a.L02,a.L03,a.L06,a.L07,a.L10,
		a.RPTCURR1,
		a.RPTCURR1_CD,
		a.SUMMABLE_WRTN_PREM_ALL_DOC_TYPES,
		a.SUMMABLE_WRTN_PREM_ALL_DOC_TYPES_USD,
		a.SUMMABLE_WRTN_PREM_ALL_DOC_TYPES *RPTCURR1 AS  WP_RPT,
		a.SUMMABLE_UEPR,
		a.SUMMABLE_UEPR_USD,
		a.WP_RT_RPT_CUR1,
		a.UEPR_RT_RATE,
		SUMMABLE_UEPR_RPT_CURR1_NEW	= ISNULL((a.WP_RT_RPT_CUR1 * a.UEPR_RT_RATE) - (ISNULL(LAG(a.WP_RT_RPT_CUR1 * UEPR_RT_RATE) OVER(PARTITION BY lob_name, l01, CONTRACT_NBR,TIRS_ORIG_CURR_CD,TIRS_UW_ASSM_CEDED_NAME,l02,l03,l06,l07,l10		ORDER BY reg_date),0)),0),
		SUMMABLE_UEPR_RPT_CURR2_NEW	= ISNULL((a.WP_RT_RPT_CUR2 * a.UEPR_RT_RATE) - (ISNULL(LAG(a.WP_RT_RPT_CUR2 * UEPR_RT_RATE) OVER(PARTITION BY lob_name, l01, CONTRACT_NBR,TIRS_ORIG_CURR_CD,TIRS_UW_ASSM_CEDED_NAME,l02,l03,l06,l07,l10		ORDER BY reg_date),0)),0),
		SUMMABLE_DAC_RPT_CURR1_NEW	= ISNULL((a.COMM_RT_RPT_CUR1 * a.DAC_RT_RATE) - (ISNULL(LAG(a.COMM_RT_RPT_CUR1 * DAC_RT_RATE) OVER(PARTITION BY lob_name, l01, CONTRACT_NBR,TIRS_ORIG_CURR_CD,TIRS_UW_ASSM_CEDED_NAME,l02,l03,l06,l07,l10	ORDER BY reg_date),0)),0),
		SUMMABLE_DAC_RPT_CURR2_NEW	= ISNULL((a.COMM_RT_RPT_CUR2 * a.DAC_RT_RATE) - (ISNULL(LAG(a.COMM_RT_RPT_CUR2 * DAC_RT_RATE) OVER(PARTITION BY lob_name, l01, CONTRACT_NBR,TIRS_ORIG_CURR_CD,TIRS_UW_ASSM_CEDED_NAME,l02,l03,l06,l07,l10   ORDER BY reg_date),0)),0)
	FROM a
	)
	UPDATE  U
	   SET  SUMMABLE_UEPR_RPT_CURR1	= ISNULL(SUMMABLE_UEPR_RPT_CURR1_NEW, 0),
	    	SUMMABLE_UEPR_RPT_CURR2	= ISNULL(SUMMABLE_UEPR_RPT_CURR2_NEW, 0),
	    	SUMMABLE_DAC_RPT_CURR1	= ISNULL(SUMMABLE_DAC_RPT_CURR1_NEW,  0),
	    	SUMMABLE_DAC_RPT_CURR2	= ISNULL(SUMMABLE_DAC_RPT_CURR2_NEW,  0)
	  FROM  #OpenBox_UW_Stage U 
	 INNER  JOIN B	ON  B.[CONTRACT_NBR]			= U.[CONTRACT_NBR] 
					AND B.[UNDERWRITING_YEAR]		= U.[UNDERWRITING_YEAR]
					AND B.[reg_date]				= U.[reg_date]
					AND B.[TIRS_ORIG_CURR_CD]		= U.[TIRS_ORIG_CURR_CD] 
					AND B.[TIRS_UW_ASSM_CEDED_NAME]	= U.[TIRS_UW_ASSM_CEDED_NAME]
					AND B.[lob_name]				= U.[lob_name]
					AND B.[AdjustmentType]			= U.[AdjustmentType]
	*/

	----------------------------------------------------------------------------------
	--Populate DataHash
	----------------------------------------------------------------------------------
	UPDATE s
	SET DataHash = HASHBYTES('SHA1',
							CONCAT(s.[TREATY_NBR] 
							, '|', s.[ASSUMED_CEDED_FLG] 
							, '|', s.[TIRS_UW_ASSM_CEDED_NAME] 
							, '|', s.[TIRS_ORIG_CURR_NAME] 
							, '|', s.[lob_name] 
							, '|', s.[SUMMABLE_WRTN_PREM_ALL_DOC_TYPES]
							, '|', s.[SUMMABLE_WRTN_PREM_ALL_DOC_TYPES_USD]
							, '|', s.[SUMMABLE_UEPR]
							, '|', s.[SUMMABLE_UEPR_USD]
							, '|', s.[SUMMABLE_UEPR_RPT_CURR1]	
							, '|', s.[SUMMABLE_UEPR_RPT_CURR2]	
							, '|', s.[SUMMABLE_DAC]
							, '|', s.[SUMMABLE_DAC_USD]
							, '|', s.[SUMMABLE_DAC_RPT_CURR1]
							, '|', s.[SUMMABLE_DAC_RPT_CURR2]
							, '|', s.[SUMMABLE_Brokerage]
							, '|', s.[SUMMABLE_Brokerage_USD]
							, '|', s.[SUMMABLE_Commission]
							, '|', s.[SUMMABLE_Commission_USD]
							, '|', s.[SUMMABLE_tax_nonrefund]
							, '|', s.[SUMMABLE_tax_nonrefund_USD]
							, '|', s.[SUMMABLE_tax_on_prem]
							, '|', s.[SUMMABLE_tax_on_prem_USD]
							, '|', s.[AdjustmentType]
							, '|', s.[aslob]
							, '|', s.[financial_lob]
							, '|', s.[InsurerCode]
							, '|', s.[ICP_CEDED_FLG] 
							, '|', s.[RPT_OFC_NM]
							, '|', s.[RPT_OFF_NAME]
							, '|', s.[T7_CODE]
							, '|', s.[T8_code]
							, '|', s.[T9_CODE] 
							, '|', s.[MBU]
							, '|', s.[L01]
							, '|', s.[L02]
							, '|', s.[L03]
							, '|', s.[l04]
							, '|', s.[L06] 
							, '|', s.[l07]
							, '|', s.[L10]
							, '|', s.[GD1]
							, '|', s.[Source]	
							, '|', s.[RPTCURR1_CD]
							, '|', s.[RPTCURR2_CD]
							, '|', s.[RPTCURR1]
							, '|', s.[RPTCURR2]
							, '|', s.[Blended_Rate]
							, '|', s.[SourceSystemKey]
							, '|', s.[lPolicySectionRCCSplitKey]
							, '|', s.[lPolicyLiabilityCustomInstalmentKey]
							, '|', s.[DueDate]
							, '|', s.[FromDate] 
							, '|', s.[ToDate] 
							, '|', s.[doc_key]
							, '|', s.[TransactionTypeCode]		
							, '|', s.[TransactionTypeCategory]
					))
	FROM #OpenBox_UW_Stage s

	----------------------------------------------------------------------------------
	--Populate #UWLoadOperation
	----------------------------------------------------------------------------------
	DROP TABLE IF EXISTS #UWLoadOperation
	CREATE TABLE #UWLoadOperation 
	(
		[CONTRACT_NBR]							VARCHAR(20) COLLATE DATABASE_DEFAULT NOT NULL,
		[UNDERWRITING_YEAR]						VARCHAR(4) COLLATE DATABASE_DEFAULT NOT NULL,
		[reg_date]								DATE NOT NULL,
		[TIRS_ORIG_CURR_CD]						VARCHAR(10) COLLATE DATABASE_DEFAULT NOT NULL,
		[TIRS_UW_ASSM_CEDED_NAME]				VARCHAR(10) COLLATE DATABASE_DEFAULT NOT NULL,
		[lob_name]								VARCHAR(255) COLLATE DATABASE_DEFAULT NOT NULL,
		[ActuarialLob]							VARCHAR(255) NULL,
		[solvency_II_regulatory_key]			INT NULL,
		[SourceSystemKey]						BIGINT NULL, 
		[lPolicySectionRCCSplitKey]				INT NULL,
		[lPolicyLiabilityCustomInstalmentKey]	INT NULL,
		[Operation]								CHAR(1) NOT NULL,
		UNIQUE([CONTRACT_NBR]
			  ,[UNDERWRITING_YEAR]
			  ,[reg_date]
			  ,[TIRS_ORIG_CURR_CD]
			  ,[TIRS_UW_ASSM_CEDED_NAME]
			  ,[lob_name]
			  ,[ActuarialLob]
			  ,[solvency_II_regulatory_key]
			  ,[SourceSystemKey]
			  ,[lPolicySectionRCCSplitKey]
			  ,[lPolicyLiabilityCustomInstalmentKey])
	);

	INSERT INTO #UWLoadOperation
	(
		 [CONTRACT_NBR]				
		,[UNDERWRITING_YEAR]
		,[reg_date]
		,[TIRS_ORIG_CURR_CD]		
		,[TIRS_UW_ASSM_CEDED_NAME]
		,[lob_name]
		,[ActuarialLob]
		,[solvency_II_regulatory_key]
		,[SourceSystemKey]
		,[lPolicySectionRCCSplitKey]          
		,[lPolicyLiabilityCustomInstalmentKey] 
		,[Operation]
	)
	SELECT 
		 [CONTRACT_NBR]							= COALESCE(t.CONTRACT_NBR COLLATE DATABASE_DEFAULT, s.CONTRACT_NBR COLLATE DATABASE_DEFAULT)
		,[UNDERWRITING_YEAR]					= COALESCE(t.UNDERWRITING_YEAR, s.UNDERWRITING_YEAR)
		,[reg_date]								= COALESCE(t.reg_date, s.reg_date)
		,[TIRS_ORIG_CURR_CD]					= COALESCE(t.TIRS_ORIG_CURR_CD COLLATE DATABASE_DEFAULT, s.TIRS_ORIG_CURR_CD COLLATE DATABASE_DEFAULT)
		,[TIRS_UW_ASSM_CEDED_NAME]				= COALESCE(t.TIRS_UW_ASSM_CEDED_NAME COLLATE DATABASE_DEFAULT, s.TIRS_UW_ASSM_CEDED_NAME COLLATE DATABASE_DEFAULT)
		,[lob_name]								= COALESCE(t.lob_name COLLATE DATABASE_DEFAULT, s.lob_name COLLATE DATABASE_DEFAULT)
		,[ActuarialLob]							= COALESCE(t.ActuarialLob COLLATE DATABASE_DEFAULT, s.ActuarialLob COLLATE DATABASE_DEFAULT, '')
		,[solvency_II_regulatory_key]			= COALESCE(t.solvency_II_regulatory_key, s.solvency_II_regulatory_key, -1)
		,[SourceSystemKey]						= COALESCE(t.SourceSystemKey, s.SourceSystemKey, -1)
		,[lPolicySectionRCCSplitKey]			= COALESCE(t.lPolicySectionRCCSplitKey, s.lPolicySectionRCCSplitKey, -1)        
		,[lPolicyLiabilityCustomInstalmentKey]	= COALESCE(t.lPolicyLiabilityCustomInstalmentKey, s.lPolicyLiabilityCustomInstalmentKey, -1)
		,[Operation]							= CASE WHEN t.OPENBOX_UW_stagingID IS NULL THEN 'I' WHEN s.DataHash IS NULL THEN 'D' ELSE 'U' END
	FROM (
		SELECT *
		  FROM assumed.OpenBox_UW_Staging
		 WHERE EndDate = '9999-12-31'
		) t
	FULL JOIN #OpenBox_UW_Stage s	ON  s.CONTRACT_NBR										= t.CONTRACT_NBR COLLATE DATABASE_DEFAULT
									AND s.UNDERWRITING_YEAR									= t.UNDERWRITING_YEAR COLLATE DATABASE_DEFAULT
									AND COALESCE(s.reg_date,'1900-01-01')					= COALESCE(t.reg_date,'1900-01-01')
									AND COALESCE(s.TIRS_ORIG_CURR_CD, '^&*')				= COALESCE(t.TIRS_ORIG_CURR_CD, '^&*') COLLATE DATABASE_DEFAULT
									AND COALESCE(s.TIRS_UW_ASSM_CEDED_NAME, '^&*')			= COALESCE(t.TIRS_UW_ASSM_CEDED_NAME, '^&*') COLLATE DATABASE_DEFAULT
									AND COALESCE(s.LOB_NAME, '^&*')							= COALESCE(t.LOB_NAME, '^&*') COLLATE DATABASE_DEFAULT
									AND COALESCE(s.ActuarialLob, '^&*')						= COALESCE(t.ActuarialLob, '^&*') COLLATE DATABASE_DEFAULT
									AND COALESCE(s.solvency_II_regulatory_key, -1)			= COALESCE(t.solvency_II_regulatory_key, -1)
									AND COALESCE(s.SourceSystemKey, -1)						= COALESCE(t.SourceSystemKey, -1)
									AND COALESCE(s.lPolicySectionRCCSplitKey, -1)			= COALESCE(t.lPolicySectionRCCSplitKey, -1)
									AND COALESCE(s.lPolicyLiabilityCustomInstalmentKey, -1)	= COALESCE(t.lPolicyLiabilityCustomInstalmentKey, -1)

	WHERE t.DataHash IS NULL
	   OR s.DataHash IS NULL
	   OR t.DataHash != s.DataHash  

	----------------------------------------------------------------------------------
	--OpenBox_UW_Staging
	----------------------------------------------------------------------------------
	BEGIN TRANSACTION
	
	UPDATE t
	   SET EndDate = p.ClosingValidTo
	  FROM assumed.OpenBox_UW_Staging t
	 CROSS JOIN #Parameters				p
	 INNER JOIN #UWLoadOperation		lo	ON  lo.CONTRACT_NBR											= t.CONTRACT_NBR COLLATE DATABASE_DEFAULT
											AND lo.UNDERWRITING_YEAR									= t.UNDERWRITING_YEAR COLLATE DATABASE_DEFAULT
											AND COALESCE(lo.reg_date,'1900-01-01')						= COALESCE(t.reg_date,'1900-01-01')
											AND COALESCE(lo.TIRS_ORIG_CURR_CD, '^&*')					= COALESCE(t.TIRS_ORIG_CURR_CD, '^&*') COLLATE DATABASE_DEFAULT
											AND COALESCE(lo.TIRS_UW_ASSM_CEDED_NAME, '^&*')				= COALESCE(t.TIRS_UW_ASSM_CEDED_NAME, '^&*') COLLATE DATABASE_DEFAULT
											AND COALESCE(lo.LOB_NAME, '^&*')							= COALESCE(t.LOB_NAME, '^&*') COLLATE DATABASE_DEFAULT
											AND COALESCE(lo.ActuarialLob, '^&*')						= COALESCE(t.ActuarialLob, '^&*') COLLATE DATABASE_DEFAULT
											AND COALESCE(lo.solvency_II_regulatory_key, -1)				= COALESCE(t.solvency_II_regulatory_key, -1)
											AND COALESCE(lo.SourceSystemKey, -1)						= COALESCE(t.SourceSystemKey, -1)
											AND COALESCE(lo.lPolicySectionRCCSplitKey, -1)				= COALESCE(t.lPolicySectionRCCSplitKey, -1)
											AND COALESCE(lo.lPolicyLiabilityCustomInstalmentKey, -1)	= COALESCE(t.lPolicyLiabilityCustomInstalmentKey, -1)
											AND lo.Operation IN ('U', 'D')
	WHERE t.EndDate = '9999-12-31';

	INSERT INTO assumed.OpenBox_UW_Staging
	(	 [StartDate]
		,[TREATY_NBR] 
		,[UNDERWRITING_YEAR] 
		,[CONTRACT_NBR] 
		,[reg_date]
		,[ASSUMED_CEDED_FLG] 
		,[TIRS_UW_ASSM_CEDED_NAME] 
		,[TIRS_ORIG_CURR_CD] 
		,[TIRS_ORIG_CURR_NAME] 
		,[lob_name] 
		,[ActuarialLob] 
		,[solvency_II_regulatory_key]
		,[SUMMABLE_WRTN_PREM_ALL_DOC_TYPES]
		,[SUMMABLE_WRTN_PREM_ALL_DOC_TYPES_USD]
		,[SUMMABLE_UEPR]
		,[SUMMABLE_UEPR_USD]
		,[SUMMABLE_UEPR_RPT_CURR1]	
		,[SUMMABLE_UEPR_RPT_CURR2]
		,[SUMMABLE_DAC]
		,[SUMMABLE_DAC_USD]
		,[SUMMABLE_DAC_RPT_CURR1]
		,[SUMMABLE_DAC_RPT_CURR2]
		,[SUMMABLE_Brokerage]
		,[SUMMABLE_Brokerage_USD]
		,[SUMMABLE_Commission]
		,[SUMMABLE_Commission_USD]
		,[SUMMABLE_tax_nonrefund]
		,[SUMMABLE_tax_nonrefund_USD]
		,[SUMMABLE_tax_on_prem]
		,[SUMMABLE_tax_on_prem_USD]
		,[AdjustmentType]
		,[aslob]
		,[financial_lob]
		,[InsurerCode]
		,[ICP_CEDED_FLG] 
		,[RPT_OFC_NM]
		,[RPT_OFF_NAME]
		,[T7_CODE]
		,[T8_code]
		,[T9_CODE] 
		,[MBU]
		,[L01]
		,[L02]
		,[L03]
		,[l04]
		,[L06] 
		,[l07]
		,[L10]
		,[GD1]
		,[Source]	
		,[RPTCURR1_CD]
		,[RPTCURR2_CD]
		,[RPTCURR1]
		,[RPTCURR2]
		,[Blended_Rate]
		,[SourceSystemKey]
		,[lPolicySectionRCCSplitKey]
		,[lPolicyLiabilityCustomInstalmentKey]
		,[DueDate]
		,[FromDate] 
		,[ToDate] 
		,[doc_key]
		,[TransactionTypeCode]		
		,[TransactionTypeCategory]
		-----------
		,[DataHash]
		)
	SELECT [StartDate] = p.NewValidFrom
		,s.[TREATY_NBR] 
		,s.[UNDERWRITING_YEAR] 
		,s.[CONTRACT_NBR] 
		,s.[reg_date]
		,s.[ASSUMED_CEDED_FLG] 
		,s.[TIRS_UW_ASSM_CEDED_NAME] 
		,s.[TIRS_ORIG_CURR_CD] 
		,s.[TIRS_ORIG_CURR_NAME] 
		,s.[lob_name] 
		,s.[ActuarialLob] 
		,s.[solvency_II_regulatory_key]
		,s.[SUMMABLE_WRTN_PREM_ALL_DOC_TYPES]
		,s.[SUMMABLE_WRTN_PREM_ALL_DOC_TYPES_USD]
		,s.[SUMMABLE_UEPR]
		,s.[SUMMABLE_UEPR_USD]
		,s.[SUMMABLE_UEPR_RPT_CURR1]
		,s.[SUMMABLE_UEPR_RPT_CURR2]
		,s.[SUMMABLE_DAC]
		,s.[SUMMABLE_DAC_USD]
		,s.[SUMMABLE_DAC_RPT_CURR1]
		,s.[SUMMABLE_DAC_RPT_CURR2]
		,s.[SUMMABLE_Brokerage]
		,s.[SUMMABLE_Brokerage_USD]
		,s.[SUMMABLE_Commission]
		,s.[SUMMABLE_Commission_USD]
		,s.[SUMMABLE_tax_nonrefund]
		,s.[SUMMABLE_tax_nonrefund_USD]
		,s.[SUMMABLE_tax_on_prem]
		,s.[SUMMABLE_tax_on_prem_USD]
		,s.[AdjustmentType]
		,s.[aslob]
		,s.[financial_lob]
		,s.[InsurerCode]
		,s.[ICP_CEDED_FLG] 
		,s.[RPT_OFC_NM]
		,s.[RPT_OFF_NAME]
		,s.[T7_CODE]
		,s.[T8_code]
		,s.[T9_CODE] 
		,s.[MBU]
		,s.[L01]
		,s.[L02]
		,s.[L03]
		,s.[l04]
		,s.[L06] 
		,s.[l07]
		,s.[L10]
		,s.[GD1]
		,s.[Source]	
		,s.[RPTCURR1_CD]
		,s.[RPTCURR2_CD]
		,s.[RPTCURR1]
		,s.[RPTCURR2]
		,s.[Blended_Rate]
		,s.[SourceSystemKey]
		,s.[lPolicySectionRCCSplitKey]
		,s.[lPolicyLiabilityCustomInstalmentKey]
		,s.[DueDate]
		,s.[FromDate] 
		,s.[ToDate] 
		,s.[doc_key]
		,s.[TransactionTypeCode]		
		,s.[TransactionTypeCategory]
		-------------
		,s.[DataHash]
	FROM #OpenBox_UW_Stage		s
	CROSS JOIN #Parameters		p
	INNER JOIN #UWLoadOperation	lo	ON  lo.CONTRACT_NBR											= s.CONTRACT_NBR COLLATE DATABASE_DEFAULT
									AND lo.UNDERWRITING_YEAR									= s.UNDERWRITING_YEAR COLLATE DATABASE_DEFAULT
									AND COALESCE(lo.reg_date,'1900-01-01')						= COALESCE(s.reg_date,'1900-01-01')
									AND COALESCE(lo.TIRS_ORIG_CURR_CD, '^&*')					= COALESCE(s.TIRS_ORIG_CURR_CD, '^&*') COLLATE DATABASE_DEFAULT
									AND COALESCE(lo.TIRS_UW_ASSM_CEDED_NAME, '^&*')				= COALESCE(s.TIRS_UW_ASSM_CEDED_NAME, '^&*') COLLATE DATABASE_DEFAULT
									AND COALESCE(lo.LOB_NAME, '^&*')							= COALESCE(s.LOB_NAME, '^&*') COLLATE DATABASE_DEFAULT
									AND COALESCE(lo.ActuarialLob, '^&*')						= COALESCE(s.ActuarialLob, '^&*') COLLATE DATABASE_DEFAULT
									AND COALESCE(lo.solvency_II_regulatory_key, -1)				= COALESCE(s.solvency_II_regulatory_key, -1)
									AND COALESCE(lo.SourceSystemKey, -1)						= COALESCE(s.SourceSystemKey, -1)						
									AND COALESCE(lo.lPolicySectionRCCSplitKey, -1)				= COALESCE(s.lPolicySectionRCCSplitKey, -1)
									AND COALESCE(lo.lPolicyLiabilityCustomInstalmentKey, -1)	= COALESCE(s.lPolicyLiabilityCustomInstalmentKey, -1)
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

		RAISERROR(@v_ErrorDescription, @v_ErrorSeverity, @v_ErrorState)
    END CATCH
