-- Database: EDW_PREPROD
-- Schema: assumed
-- Procedure: LoadFactClaim


CREATE   PROCEDURE assumed.LoadFactClaim
	@FullLoad BIT = 0
AS
BEGIN TRY
		SET NOCOUNT ON

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
		-------------------------------------------------------

		/*
		-- dependencies
		EXEC EDW_Staging.assumed.LoadProportionalEarningRate
		EXEC EDW_Staging.assumed.LoadTIRSOSLossBalance
		EXEC EDW_Staging.assumed.LoadTIRSOSLossMovement
		EXEC EDW_Staging.assumed.LoadTIRSOSLossEarnedAccidentYear
		EXEC EDW_Staging.assumed.LoadTIRSAccountingLossPaid
		EXEC EDW_Staging.assumed.LoadTIRSAccountingLossPaidEarnedAccidentYear
		EXEC EDW_Staging.assumed.LoadTIRSClaimLossPaidOSLR
		EXEC EDW_Staging.assumed.LoadTIRSClaimLossPaidOSLRInfo

		EXEC EDW_PREPROD.assumed.LoadDimAccidentYear
		EXEC EDW_PREPROD.assumed.LoadDimAccounting
		EXEC EDW_PREPROD.assumed.LoadDimAccountingPeriod
		EXEC EDW_PREPROD.assumed.LoadDimAdjustmentType
		EXEC EDW_PREPROD.assumed.LoadDimClaim
		EXEC EDW_PREPROD.assumed.LoadDimBankDetail
		EXEC EDW_PREPROD.assumed.LoadDimClaimTransaction
		EXEC EDW_PREPROD.assumed.LoadDimBilling
		EXEC EDW_PREPROD.assumed.LoadDimAssured
		EXEC EDW_PREPROD.assumed.LoadDimBroker
		EXEC EDW_PREPROD.assumed.LoadDimMGA
		EXEC EDW_PREPROD.assumed.LoadDimSchlCompanyName
		EXEC EDW_PREPROD.assumed.LoadDimTPA
		EXEC EDW_PREPROD.assumed.LoadDimContract
		EXEC EDW_PREPROD.assumed.LoadDimCurrency
		EXEC EDW_PREPROD.assumed.LoadDimExchangeRate
		EXEC EDW_PREPROD.assumed.LoadDimLineOfBusiness
		EXEC EDW_PREPROD.assumed.LoadDimMeasure
		EXEC EDW_PREPROD.assumed.LoadDimParticipant
		EXEC EDW_PREPROD.assumed.LoadDimTransactionType
		EXEC EDW_PREPROD.assumed.LoadDimDate
		EXEC EDW_PREPROD.assumed.LoadDimPayee
		EXEC EDW_PREPROD.assumed.LoadBridgePayeeBankDetail

		assumed.LoadFactClaim @FullLoad = 1

		DECLARE @FullLoad BIT = 1
		--*/
		DROP TABLE IF EXISTS #Timings

		SELECT EventTime = SYSDATETIME()
			,EventMessage = CAST('Start' AS VARCHAR(100))
			,ErrorNo = 0
		INTO #Timings

		SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

		DROP TABLE IF EXISTS #AccountingPeriod

		SELECT x.AccountingPeriodDate
			,x.AccountingStartDate
			,x.AccountingEndDate
			,OffsetDays = 1
			,OffsetAccountingStartDate = DATEADD(DAY, 1, x.AccountingStartDate)
			,OffsetAccountingEndDate = DATEADD(DAY, 1, x.AccountingEndDate)
			,CurrentPeriod = CAST(CASE WHEN CAST(DATEADD(DAY, -1, GETDATE()) AS DATE) BETWEEN x.AccountingStartDate AND x.AccountingEndDate THEN 1 ELSE 0 END AS BIT)
		INTO #AccountingPeriod
		FROM (
			SELECT AccountingPeriodDate = ap.accounting_period_date
				,AccountingStartDate = CAST(DATEADD(DAY, 1, LAG(ap.accounting_period_close_date) OVER (ORDER BY ap.accounting_period_key)) AS DATE)
				,AccountingEndDate = CAST(ap.accounting_period_close_date AS DATE)
			FROM Insight.dbo.accounting_periods ap
			) x
		WHERE x.AccountingStartDate IS NOT NULL

		DROP TABLE IF EXISTS #Parameters

		SELECT CurrentAccountingPeriod = (SELECT AccountingPeriodDate FROM #AccountingPeriod WHERE CurrentPeriod = 1)
			,CurrentAccountingStartDate = (SELECT AccountingStartDate FROM #AccountingPeriod WHERE CurrentPeriod = 1)
			,CurrentOffsetAccountingEndDate = (SELECT OffsetAccountingEndDate FROM #AccountingPeriod WHERE CurrentPeriod = 1)
			,ClaimTouchedSince = DATEADD(DAY, -2, COALESCE((SELECT LastCreatedDate = MAX(fc.CreatedDate) FROM assumed.FactClaim fc), '1 Jan 1900'))
			,CatCodeHistoryChangedSince = DATEADD(DAY, -45, COALESCE((SELECT LastCreatedDate = MAX(fc.CreatedDate) FROM assumed.FactClaim fc), '1 Jan 1900'))
			,ProcessingDate = SYSDATETIME()
			,FullLoad = CAST(CASE WHEN NOT EXISTS (SELECT 1 FROM assumed.FactClaim) THEN 1 ELSE @FullLoad END AS BIT)
			,DimContractUncoded = (SELECT dac.DimContractID FROM EDW_PREPROD.assumed.DimContract dac WHERE dac.Contract_NBR = 'Uncoded' AND SYSDATETIME() BETWEEN dac.StartDate AND dac.EndDate)
			,DimContractNA = (SELECT dac.DimContractID FROM EDW_PREPROD.assumed.DimContract dac WHERE dac.Contract_NBR = 'N/A' AND SYSDATETIME() BETWEEN dac.StartDate AND dac.EndDate)
			,DimClaimTransactionUncoded = (SELECT dact.DimClaimTransactionID FROM EDW_PREPROD.assumed.DimClaimTransaction dact WHERE dact.ClaimTransactionCode = 'Uncoded' AND SYSDATETIME() BETWEEN dact.StartDate AND dact.EndDate)
			,DimClaimTransactionNA = (SELECT dact.DimClaimTransactionID FROM EDW_PREPROD.assumed.DimClaimTransaction dact WHERE dact.ClaimTransactionCode = 'N/A' AND SYSDATETIME() BETWEEN dact.StartDate AND dact.EndDate)
			,DimTransactionTypeUncoded = (SELECT dtt.DimTransactionTypeID FROM EDW_PREPROD.assumed.DimTransactionType dtt WHERE dtt.TransactionType = 'Uncoded' AND SYSDATETIME() BETWEEN dtt.StartDate AND dtt.EndDate)
			,DimTransactionTypeNA = (SELECT dtt.DimTransactionTypeID FROM EDW_PREPROD.assumed.DimTransactionType dtt WHERE dtt.TransactionType = 'N/A' AND SYSDATETIME() BETWEEN dtt.StartDate AND dtt.EndDate)
			,DimDateUncoded = (SELECT ddd.DimDateID FROM EDW_PREPROD.assumed.DimDate ddd WHERE ddd.DateText = 'Uncoded' AND SYSDATETIME() BETWEEN ddd.StartDate AND ddd.EndDate)
			,DimDateNA = (SELECT ddd.DimDateID FROM EDW_PREPROD.assumed.DimDate ddd WHERE ddd.DateText = 'N/A' AND SYSDATETIME() BETWEEN ddd.StartDate AND ddd.EndDate)
			,DimAccidentYearUncoded = (SELECT ay.DimAccidentYearID FROM EDW_PREPROD.assumed.DimAccidentYear ay WHERE ay.L04 = 'Uncoded' AND SYSDATETIME() BETWEEN ay.StartDate AND ay.EndDate)
			,DimMeasureUncoded = (SELECT dm.DimMeasureID FROM EDW_PREPROD.assumed.DimMeasure dm WHERE dm.MeasureCode = 'Uncoded' AND SYSDATETIME() BETWEEN dm.StartDate AND dm.EndDate)
			,DimAccountingUncoded = (SELECT da.DimAccountingID FROM EDW_PREPROD.assumed.DimAccounting da WHERE da.ActuarialLob = 'Uncoded' AND da.RPT_OFF_NAME = 'Uncoded' AND SYSDATETIME() BETWEEN da.StartDate AND da.EndDate)
			,DimAccountingPeriodUncoded = (SELECT dap.DimAccountingPeriodID FROM EDW_PREPROD.assumed.DimAccountingPeriod dap WHERE dap.AccountingYearMonth = 'Uncoded' AND SYSDATETIME() BETWEEN dap.StartDate AND dap.EndDate)
			,Current_DimAccountingPeriodID = (
				SELECT dap.DimAccountingPeriodID
				FROM EDW_PREPROD.assumed.DimAccountingPeriod dap
				INNER JOIN #AccountingPeriod ap
					ON ap.AccountingPeriodDate = dap.AccountingPeriodDate
				WHERE ap.CurrentPeriod = 1
				AND SYSDATETIME() BETWEEN dap.StartDate AND dap.EndDate
				)
			,DimAdjustmentTypeUncoded = (SELECT dat.DimAdjustmentTypeID FROM EDW_PREPROD.assumed.DimAdjustmentType dat WHERE dat.AdjustmentType = 'Uncoded' AND SYSDATETIME() BETWEEN dat.StartDate AND dat.EndDate)
			,DimExchangeRateUncoded = (SELECT daer.DimExchangeRateID FROM EDW_PREPROD.assumed.DimExchangeRate daer WHERE daer.RateDescription = 'Uncoded' AND SYSDATETIME() BETWEEN daer.StartDate AND daer.EndDate)
			,DimExchangeRateNA = (SELECT daer.DimExchangeRateID FROM EDW_PREPROD.assumed.DimExchangeRate daer WHERE daer.RateDescription = 'N/A' AND SYSDATETIME() BETWEEN daer.StartDate AND daer.EndDate)
			,DimCurrencyUncoded = (SELECT dac.DimCurrencyID FROM EDW_PREPROD.assumed.DimCurrency dac WHERE dac.TIRS_CURR_NAME = 'Uncoded' AND SYSDATETIME() BETWEEN dac.StartDate AND dac.EndDate)
			,DimCurrencyNA = (SELECT dac.DimCurrencyID FROM EDW_PREPROD.assumed.DimCurrency dac WHERE dac.TIRS_CURR_NAME = 'N/A' AND SYSDATETIME() BETWEEN dac.StartDate AND dac.EndDate)
			,DimLineOfBusinessUncoded = (SELECT dlob.DimLineOfBusinessID FROM EDW_PREPROD.assumed.DimLineOfBusiness dlob WHERE dlob.LineOfBusinessName = 'Uncoded' AND SYSDATETIME() BETWEEN dlob.StartDate AND dlob.EndDate)
			,DimParticipantUncoded = (SELECT dp.DimParticipantID FROM EDW_PREPROD.assumed.DimParticipant dp WHERE dp.Participant = 'Uncoded' AND SYSDATETIME() BETWEEN dp.StartDate AND dp.EndDate)
			,DimParticipantNA = (SELECT dp.DimParticipantID FROM EDW_PREPROD.assumed.DimParticipant dp WHERE dp.Participant = 'N/A' AND SYSDATETIME() BETWEEN dp.StartDate AND dp.EndDate)
			,DimPayeeUncoded = (SELECT dp.DimPayeeID FROM EDW_PREPROD.assumed.DimPayee dp WHERE dp.PayeeName = 'Uncoded')
			,DimPayeeNA = (SELECT dp.DimPayeeID FROM EDW_PREPROD.assumed.DimPayee dp WHERE dp.PayeeName = 'N/A')
			,DimDocumentUncoded = (SELECT dd.DimDocumentID FROM EDW_PREPROD.assumed.DimDocument dd WHERE dd.doc_key = 'Uncoded' AND SYSDATETIME() BETWEEN dd.StartDate AND dd.EndDate)
            ,DimDocumentNA = (SELECT dd.DimDocumentID FROM EDW_PREPROD.assumed.DimDocument dd WHERE dd.doc_key = 'N/A' AND SYSDATETIME() BETWEEN dd.StartDate AND dd.EndDate)
			,ProcessName = COALESCE(OBJECT_SCHEMA_NAME(@@PROCID) + '.' + OBJECT_NAME(@@PROCID), 'assumed.LoadFactClaim')
		INTO #Parameters

		INSERT INTO #Timings SELECT SYSDATETIME(), 'Created #Parameters', @@ERROR

		-- Handle situations where the processing isn't run on the first day of a new accounting period (covering the last day of source data for the previous accounting period), but then is run the next
		-- day.  This situation includes 2 days of source data, one of which should be processed into the previous month and one day that should be processed into the current month.  In this case only
		-- use the reg_date received from source to indicate the accounting period it should be placed in.  In those situations, one row will be created in the following table that can be used to override
		-- the Actual_DimAccountingPeriodID in the final inserts of this stored procedure.
		DROP TABLE IF EXISTS #ActualAccountingPeriodOverride

		SELECT Intended_DimAccountingPeriodID = dap.DimAccountingPeriodID
			,Actual_DimAccountingPeriodID = dap.DimAccountingPeriodID
		INTO #ActualAccountingPeriodOverride
		FROM (
			SELECT ap.AccountingPeriodDate
				,MostRecent = ROW_NUMBER() OVER (ORDER BY ap.AccountingPeriodDate DESC)
			FROM (
				SELECT EarliestUnprocessedEOD = CAST(MAX(p.process_start_datetime) AS DATE)
					,LatestUnprocessedEOD = DATEADD(DAY, -1, CAST(GETDATE() AS DATE))
				FROM (
					SELECT ec.process_start_datetime
					FROM ETL.dbo.etl_controller ec
					INNER JOIN #Parameters prm
						ON prm.ProcessName = ec.process_name COLLATE DATABASE_DEFAULT
					WHERE ec.process_start_datetime IS NOT NULL
						AND ec.error_number = 0
					UNION ALL
					SELECT eh.process_start_datetime
					FROM ETL.dbo.etl_history eh
					INNER JOIN #Parameters prm
						ON prm.ProcessName = eh.process_name COLLATE DATABASE_DEFAULT
					WHERE eh.process_start_datetime IS NOT NULL
						AND eh.error_number = 0
					) p
				) x
			INNER JOIN #AccountingPeriod ap
				ON x.EarliestUnprocessedEOD BETWEEN ap.AccountingStartDate AND ap.AccountingEndDate
				OR x.LatestUnprocessedEOD BETWEEN ap.AccountingStartDate AND ap.AccountingEndDate
			) y
		INNER JOIN EDW_PREPROD.assumed.DimAccountingPeriod dap
			ON dap.EndDate = '31 Dec 9999'
			AND dap.AccountingPeriodDate = y.AccountingPeriodDate
		WHERE y.MostRecent = 2

		INSERT INTO #Timings SELECT SYSDATETIME(), 'Created #ActualAccountingPeriodOverride', @@ERROR

		-- Create the contract filter, only those contracts that have changed for non-full loads and all contracts for full loads
		DROP TABLE IF EXISTS #ContractFilter

		CREATE TABLE #ContractFilter
		(trty_no INT NULL
		,und_yr VARCHAR(4) NULL
		,Contract_NBR VARCHAR(30) NOT NULL
		,PRIMARY KEY (Contract_NBR)
		)

		DROP TABLE IF EXISTS #CededParticipantChange

		SELECT DISTINCT bcb.DimContractID
		INTO #CededParticipantChange
		FROM assumed.BridgeContractBroker bcb
		CROSS JOIN #Parameters prm
		WHERE bcb.AssumedCeded = 'C'
			AND (bcb.EndDate BETWEEN prm.ClaimTouchedSince AND prm.ProcessingDate OR bcb.StartDate > prm.ClaimTouchedSince)
			AND prm.FullLoad = 0

		DROP TABLE IF EXISTS #AssumedCededLink

		SELECT DISTINCT ad.trty_key
			,ad.ceded_trty_key
		INTO #AssumedCededLink
		FROM SRC_TIRS_DB.dbo.acct_doc ad
		WHERE ceded_trty_key != -999
		OPTION (MAXDOP 1)

		INSERT INTO #ContractFilter
			(trty_no
			,und_yr
			,Contract_NBR
			)
		SELECT DISTINCT trty_no = CAST(LEFT(talp.CONTRACT_NBR, 5) AS INT)
			,und_yr = RIGHT(talp.CONTRACT_NBR, 4)
			,talp.CONTRACT_NBR
		FROM EDW_Staging.assumed.TIRSAccountingLossPaidEarnedAccidentYear talp
		INNER JOIN #Parameters prm
			ON prm.ClaimTouchedSince <= talp.StartDate
		WHERE prm.FullLoad = 0
		UNION
		SELECT DISTINCT trty_no = CAST(LEFT(tol.CONTRACT_NBR, 5) AS INT)
			,und_yr = RIGHT(tol.CONTRACT_NBR, 4)
			,tol.CONTRACT_NBR
		FROM EDW_Staging.assumed.TIRSOSLossEarnedAccidentYear tol
		INNER JOIN #Parameters prm
			ON prm.ClaimTouchedSince <= tol.StartDate
		WHERE prm.FullLoad = 0
		UNION
		SELECT DISTINCT trty_no = CAST(LEFT(tclpo.CONTRACT_NBR, 5) AS INT)
			,und_yr = RIGHT(tclpo.CONTRACT_NBR, 4)
			,tclpo.CONTRACT_NBR
		FROM EDW_Staging.assumed.TIRSClaimLossPaidOSLR tclpo
		INNER JOIN #Parameters prm
			ON prm.ClaimTouchedSince <= tclpo.StartDate
			OR tclpo.EndDate BETWEEN prm.ClaimTouchedSince AND prm.ProcessingDate
		WHERE prm.FullLoad = 0
		UNION
		-- incremental load - detect changed participants for ceded contracts
		SELECT DISTINCT trty_no = tm.trty_no
			,und_yr = tm.und_yr
			,CONTRACT_NBR = CONCAT(LEFT(tm.trty_no, 5), tm.und_yr) COLLATE DATABASE_DEFAULT
		FROM #CededParticipantChange cpc
		INNER JOIN assumed.DimContract cdc
			ON cdc.DimContractID = cpc.DimContractID
			AND cdc.EndDate = '31 Dec 9999'
		INNER JOIN SRC_TIRS_DB.dbo.trty_master ctm
			ON CONCAT(LEFT(ctm.trty_no, 5), ctm.und_yr) COLLATE DATABASE_DEFAULT = cdc.CONTRACT_NBR
		INNER JOIN #AssumedCededLink acl
			ON acl.ceded_trty_key = ctm.trty_key
		INNER JOIN SRC_TIRS_DB.dbo.trty_master tm
			ON tm.trty_key = acl.trty_key
		UNION
		-- Non-Full Load - identify changed dbo.T_CODE_HISTORY entries within the threshold with a TIRS acct_doc record with status 'P'
		SELECT DISTINCT trty_no = ad.trty_no
			,und_yr = ad.und_yr
			,Contract_NBR = CONCAT(CAST(ad.trty_no AS CHAR(5)), CAST(TRIM(ad.und_yr) AS CHAR(4)))
		FROM SRC_TIRS_DB.dbo.acct_doc ad
		CROSS JOIN #Parameters prm
		INNER JOIN EDW_PREPROD.dbo.T_CODE_HISTORY tch
			ON tch.CONTRACT_NBR = CONCAT(CAST(ad.trty_no AS CHAR(5)), CAST(TRIM(ad.und_yr) AS CHAR(4))) COLLATE DATABASE_DEFAULT
		WHERE tch.START_DATE > prm.CatCodeHistoryChangedSince
			AND prm.FullLoad = 0
			AND ad.status_flg = 'P'
		UNION
		-- Non-Full Load - identify changed dbo.TIRS_CATCODE_HISTORY entries within the threshold with a TIRS acct_doc record with status 'P'
		SELECT DISTINCT trty_no = ad.trty_no
			,und_yr = ad.und_yr
			,Contract_NBR = CONCAT(CAST(ad.trty_no AS CHAR(5)), CAST(TRIM(ad.und_yr) AS CHAR(4)))
		FROM SRC_TIRS_DB.dbo.claim c
		CROSS JOIN #Parameters prm
		INNER JOIN SRC_TIRS_DB.dbo.claim_trans ct
			ON ct.clm_key = c.clm_key
		INNER JOIN SRC_TIRS_DB.dbo.trty_master tm
			ON tm.trty_key = c.trty_key
		INNER JOIN SRC_TIRS_DB.dbo.acct_doc ad
			ON ad.trty_no = tm.trty_no
			AND ad.und_yr = tm.und_yr
			AND ad.status_flg = 'P'
		INNER JOIN EDW_PREPROD.dbo.TIRS_CATCODE_HISTORY tch
			ON tch.TIRS_CLM_CD = ct.trans_key
		WHERE tch.START_DATE > prm.CatCodeHistoryChangedSince
			AND prm.FullLoad = 0
			AND ad.status_flg = 'P'
		UNION
		SELECT DISTINCT trty_no = tm.trty_no
			,und_yr = tm.und_yr
			,Contract_NBR = CONCAT(LEFT(tm.trty_no, 5), tm.und_yr)
		FROM SRC_TIRS_DB.dbo.m_detl_oc mdo
		INNER JOIN SRC_TIRS_DB.dbo.trty_master tm
			ON tm.trty_key = mdo.trty_key
		INNER JOIN #Parameters prm
			ON prm.ClaimTouchedSince <= mdo.touch_dt
		WHERE prm.FullLoad = 0
		UNION
		--SELECT DISTINCT trty_no = tm.trty_no
		--	,und_yr = tm.und_yr
		--	,Contract_NBR = CONCAT(CAST(tm.trty_no AS CHAR(5)), CAST(TRIM(tm.und_yr) AS CHAR(4)))
		--FROM SRC_TIRS_DB.dbo.claim c
		--CROSS JOIN #Parameters prm
		--INNER JOIN SRC_TIRS_DB.dbo.trty_master tm
		--	ON tm.trty_key = c.trty_key
		--WHERE prm.FullLoad = 1
		--UNION
		-- always include contracts with topsides as there is no way to detect a change the in topside table
		SELECT DISTINCT TRY_CAST(rtct.TREATY_NBR AS INT)
			,rtct.UNDERWRITING_YEAR COLLATE DATABASE_DEFAULT
			,rtct.CONTRACT_NBR COLLATE DATABASE_DEFAULT
		FROM EDW_PREPROD.dbo.RS_TIRS_CLAIMS_TOPSIDE rtct
		UNION
		-- always include contracts from openbox
		SELECT DISTINCT TREATY_NBR = CAST(NULL AS INT)
			,UNDERWRITING_YEAR = CAST(tcl.YOA AS VARCHAR(4))
			,CONTRACT_NBR = m.CONTRACT_NBR
		FROM EDW_PREPROD.lloyds.TBL_CLAIM_LLYDS tcl
		LEFT JOIN (
			SELECT DISTINCT CONTRACT_NBR = CONTRACT_NBR
				,CONTRACT_REFERENCE = CONTRACT_REFERENCE	
			FROM EDW_PREPROD.dbo.MAP_CONTRACT_EDW mce
			WHERE plcy_SRC = 'OPENBOX'
			) m
			ON m.CONTRACT_REFERENCE = tcl.PolicyNumber
		WHERE tcl.BusinessType = 'Assumed'
			AND tcl.PolicySource = 'Openbox'
		UNION
		-- Full Load
		SELECT DISTINCT trty_no = TRY_CAST(LEFT(dc.CONTRACT_NBR, 5) AS INT)
			,und_yr = COALESCE(dc.UNDERWRITING_YEAR, CASE WHEN dc.PLCY_SRC = 'TIRS' THEN RIGHT(dc.CONTRACT_NBR, 4) END) COLLATE DATABASE_DEFAULT
			,CONTRACT_NBR = dc.CONTRACT_NBR COLLATE DATABASE_DEFAULT
		FROM EDW_PREPROD.assumed.DimContract dc
		INNER JOIN #Parameters prm
			ON prm.FullLoad = 1
		WHERE dc.EndDate = '31 Dec 9999'
			AND LEN(COALESCE(dc.UNDERWRITING_YEAR, '')) <= 4

		INSERT INTO #Timings SELECT SYSDATETIME(), 'Created #ContractFilter', @@ERROR

		DROP TABLE IF EXISTS #BaseKey

		SELECT DISTINCT Treaty_NBR = TRIM(CAST(ad.trty_no AS VARCHAR(5))) COLLATE DATABASE_DEFAULT
			,UNDERWRITING_YEAR = TRIM(CAST(ad.und_yr AS VARCHAR(4))) COLLATE DATABASE_DEFAULT
			,CONTRACT_NBR = TRIM(CAST(ad.trty_no AS VARCHAR(5))) + TRIM(CAST(ad.und_yr AS VARCHAR(4))) COLLATE DATABASE_DEFAULT
			,CEDED_CONTRACT_NBR = TRIM(CAST(ceded_tm.trty_no AS CHAR(5))) + TRIM(CAST(ceded_tm.und_yr AS CHAR(4))) COLLATE DATABASE_DEFAULT
			,ORIGCURR_CD = TRIM(cn.curr_iso_cd) COLLATE DATABASE_DEFAULT
			,TIRS_ORIG_CURR_CD = TRIM(ad.curr_cd) COLLATE DATABASE_DEFAULT
			,TIRS_ORIG_CURR_NAME = TRIM(cn.curr_nm) COLLATE DATABASE_DEFAULT
			,LOB_NAME = TRIM(lob.desc_txt) COLLATE DATABASE_DEFAULT
			,AccidentYear = TRIM(CAST(ay.accidentyear AS VARCHAR(4))) COLLATE DATABASE_DEFAULT
			,reg_date = CAST(COALESCE(ad.reg_dt, DATEADD(MONTH, DATEDIFF(MONTH, 0, ad.create_dt), 0)) AS DATE)
			,ASLOB = TRIM(AM.ASLOB) COLLATE DATABASE_DEFAULT
			,assumed_ceded_flg = ad.assumed_ceded_flg COLLATE DATABASE_DEFAULT
			,solvency_II_regulatory_key = solII.solvency_II_regulatory_key
		INTO #BaseKey
		FROM src_tirs_db.dbo.acct_byline ab
		INNER JOIN SRC_TIRS_DB.dbo.acct_doc ad
			ON ab.doc_key = ad.doc_key
		INNER JOIN #ContractFilter cf
			ON cf.trty_no = ad.trty_no
			AND cf.und_yr = ad.und_yr
		LEFT JOIN SRC_TIRS_DB.dbo.trty_master tm
			ON tm.trty_key = ad.trty_key
		LEFT JOIN (
			SELECT DISTINCT Contract_NBR = tcer.Contract_NBR
				,AccidentYear = YEAR(tcer.Reg_Date)
			FROM EDW_PREPROD.dbo.TIRS_Contract_Earning_Rates tcer
			WHERE tcer.Earning_Allocation_RT_PCT IS NOT NULL
			) ay
			ON ay.Contract_NBR = cf.Contract_NBR COLLATE DATABASE_DEFAULT
				AND ay.AccidentYear <= COALESCE(YEAR(ad.reg_dt), YEAR(ad.create_dt))
		LEFT JOIN SRC_TIRS_DB.dbo.trty_master ceded_tm
			ON ceded_tm.trty_key = ad.Ceded_trty_key
		LEFT JOIN SRC_TIRS_DB.dbo.xrf_lob_cds lob
			ON lob.lob_cd = ab.pr_cls_cd
		LEFT JOIN SRC_TIRS_DB.dbo.xrf_annl_stmt_line aslob
			ON lob.annl_stmt_key = aslob.annl_stmt_key
		LEFT JOIN SRC_TIRS_DB.dbo.xrf_curr_cds xt
			ON ad.curr_cd = xt.curr_cd
				AND CAST(COALESCE(ad.reg_dt, DATEADD(MONTH, DATEDIFF(MONTH, 0, ad.create_dt), 0)) AS DATETIME) = xt.xch_rt_dt
		LEFT JOIN SRC_TIRS_DB.dbo.xrf_curr_names cn
			ON ad.curr_cd = cn.curr_cd
		LEFT JOIN EDW_STAGING.dbo.TIRS_ASLOBCodeMapping am
			ON am.pro_xol_flg = tm.pro_xol_flg COLLATE DATABASE_DEFAULT
				AND am.annl_stmt_ln = aslob.annl_stmt_ln COLLATE DATABASE_DEFAULT
		LEFT JOIN SRC_TIRS_DB.dbo.xrf_rpt_ofc XR
			ON XR.rpt_ofc_cd = TM.rpt_ofc_cd
		LEFT JOIN SRC_TIRS_DB.dbo.xrf_sub_dept_cds sd
			ON tm.sub_dept_key = sd.sub_dept_key
		LEFT JOIN EDW_PREPROD.dbo.solvency_II_regulatory_etl solII
			ON solII.source = 'TIRS'
				AND solII.assumed_or_direct = 'Assumed'
				AND COALESCE(solII.branch_name, '') COLLATE DATABASE_DEFAULT = COALESCE(XR.rpt_ofc_nm, '')
				AND COALESCE(solII.product_group_name, '') COLLATE DATABASE_DEFAULT = COALESCE(sd.division_nm, '')
				AND COALESCE(solII.product_department_name, '') COLLATE DATABASE_DEFAULT = COALESCE(sd.dept_nm, '')
				AND COALESCE(solII.sub_product, '') COLLATE DATABASE_DEFAULT = COALESCE(Sd.sub_dept_nm, '')
				AND COALESCE(solII.lob_name, '') COLLATE DATABASE_DEFAULT = COALESCE(lob.desc_txt, '')
				AND COALESCE(solII.prorata_or_xol, '') COLLATE DATABASE_DEFAULT = COALESCE(CASE WHEN TM.pro_xol_flg = 'X' THEN 'XOL' ELSE 'Pro Rata' END, '')
				AND COALESCE(solII.treaty_or_fav, '') COLLATE DATABASE_DEFAULT = COALESCE(CASE WHEN TM.trty_or_fac_flg = 'F' THEN 'FAC' ELSE 'Treaty' END, '')
				AND COALESCE(solII.property_or_casualty, '') COLLATE DATABASE_DEFAULT = COALESCE(CASE
				WHEN sd.division_nm LIKE '%property%'
					THEN 'PROPERTY'
				WHEN sd.division_nm LIKE '%marine%'
					THEN 'PROPERTY'
				ELSE 'CASUALTY'
				END, '')
				AND COALESCE(solII.is_lloyds, '') COLLATE DATABASE_DEFAULT = COALESCE(CASE WHEN XR.rpt_ofc_nm LIKE '%lloyd%' THEN 'Lloyds' ELSE 'Non-Lloyds' END, '')
				AND COALESCE(solII.transaction_ASLOB_code, '') COLLATE DATABASE_DEFAULT = COALESCE(aslob.annl_stmt_ln, '')
				AND COALESCE(solII.InceptionFrom, tm.inception_dt, '1 Jan 1900') <= COALESCE(tm.inception_dt, '1 Jan 1900')
				AND COALESCE(solII.InceptionTo, tm.inception_dt, '1 Jan 1900') >= COALESCE(tm.inception_dt, '1 Jan 1900')
		WHERE ad.status_flg = 'P'

		INSERT INTO #Timings SELECT SYSDATETIME(), 'Created #BaseKey', @@ERROR

		-- add any new reg_dates that were additionally created in EDW_Staging.assumed.TIRSOSLossBalance
		INSERT INTO #BaseKey
			(Treaty_NBR
			,UNDERWRITING_YEAR
			,CONTRACT_NBR
			,CEDED_CONTRACT_NBR
			,ORIGCURR_CD
			,TIRS_ORIG_CURR_CD
			,TIRS_ORIG_CURR_NAME
			,solvency_II_regulatory_key
			,LOB_NAME
			,AccidentYear
			,ASLOB
			,assumed_ceded_flg
			,reg_date
			)
		SELECT DISTINCT Treaty_NBR = bk.Treaty_NBR
			,UNDERWRITING_YEAR = bk.UNDERWRITING_YEAR
			,CONTRACT_NBR = bk.CONTRACT_NBR
			,CEDED_CONTRACT_NBR = bk.CEDED_CONTRACT_NBR
			,ORIGCURR_CD = bk.ORIGCURR_CD
			,TIRS_ORIG_CURR_CD = bk.TIRS_ORIG_CURR_CD
			,TIRS_ORIG_CURR_NAME = bk.TIRS_ORIG_CURR_NAME
			,solvency_II_regulatory_key = bk.solvency_II_regulatory_key
			,LOB_NAME = bk.LOB_NAME
			,AccidentYear = bk.AccidentYear
			,ASLOB = bk.ASLOB
			,assumed_ceded_flg = bk.assumed_ceded_flg
			,reg_date = tolb.reg_date
		FROM EDW_Staging.assumed.TIRSOSLOSSBalance tolb
		INNER JOIN (
			SELECT DISTINCT Treaty_NBR = bk.Treaty_NBR
				,UNDERWRITING_YEAR = bk.UNDERWRITING_YEAR
				,CONTRACT_NBR = bk.CONTRACT_NBR
				,CEDED_CONTRACT_NBR = bk.CEDED_CONTRACT_NBR
				,ORIGCURR_CD = bk.ORIGCURR_CD
				,TIRS_ORIG_CURR_CD = bk.TIRS_ORIG_CURR_CD
				,TIRS_ORIG_CURR_NAME = bk.TIRS_ORIG_CURR_NAME
				,solvency_II_regulatory_key = bk.solvency_II_regulatory_key
				,LOB_NAME = bk.LOB_NAME
				,AccidentYear = bk.AccidentYear
				,ASLOB = bk.ASLOB
				,assumed_ceded_flg = bk.assumed_ceded_flg
			FROM #BaseKey bk
			) bk
			ON bk.CONTRACT_NBR = tolb.CONTRACT_NBR COLLATE DATABASE_DEFAULT
				AND bk.TIRS_ORIG_CURR_CD = tolb.TIRS_ORIG_CURR_CD COLLATE DATABASE_DEFAULT
				AND bk.LOB_NAME = tolb.LOB_NAME COLLATE DATABASE_DEFAULT
				AND bk.assumed_ceded_flg = tolb.assumed_ceded_flg COLLATE DATABASE_DEFAULT
		LEFT JOIN #BaseKey ebk
			ON ebk.assumed_ceded_flg = tolb.assumed_ceded_flg COLLATE DATABASE_DEFAULT
				AND ebk.CONTRACT_NBR = tolb.CONTRACT_NBR COLLATE DATABASE_DEFAULT
				AND ebk.TIRS_ORIG_CURR_CD = tolb.TIRS_ORIG_CURR_CD COLLATE DATABASE_DEFAULT
				AND ebk.LOB_NAME = tolb.LOB_NAME COLLATE DATABASE_DEFAULT
				AND ebk.reg_date = tolb.reg_date
		WHERE ebk.CONTRACT_NBR IS NULL
			AND tolb.EndDate = '31 Dec 9999'
		OPTION (FORCE ORDER)

		INSERT INTO #Timings SELECT SYSDATETIME(), 'Added missing entries to #BaseKey', @@ERROR

		DROP TABLE IF EXISTS #FX

		SELECT JoinMonth = CAST(LEFT(lgc.JoinMonth, 4) + RIGHT(lgc.JoinMonth, 2) + '01' AS DATE)
			,lgc.ISOCode
			,ExchangeRate = MIN(lgc.ExchangeRate)
		INTO #FX
		FROM EDW_PREPROD.dbo.LOOKUP_GENIUS_CURRENCYRATES lgc
		WHERE JoinMonth IS NOT NULL
		GROUP BY CAST(LEFT(lgc.JoinMonth, 4) + RIGHT(lgc.JoinMonth, 2) + '01' AS DATE)
			,lgc.ISOCode

		INSERT INTO #Timings SELECT SYSDATETIME(), 'Created #FX', @@ERROR

		DROP TABLE IF EXISTS #TCodeUsed

		SELECT START_DATE = x.START_DATE
			,END_DATE = x.END_DATE
			,ContainsAccountingPeriod = CAST(CASE WHEN EXISTS (
							SELECT TOP 1 Column1 = 1
							FROM #AccountingPeriod ap
							WHERE ap.OffsetAccountingEndDate > x.START_DATE
								AND ap.OffsetAccountingEndDate < x.END_DATE
						) THEN 1 ELSE 0 END AS BIT)
		INTO #TCodeUsed
		FROM (
			SELECT DISTINCT START_DATE = START_DATE
				,END_DATE = END_DATE
			FROM EDW_PREPROD.dbo.T_Code_History tch
			) x

		INSERT INTO #Timings SELECT SYSDATETIME(), 'Created #TCodeUsed', @@ERROR

		DROP TABLE IF EXISTS #TCodeRevisionExASLOB

		-- Revise T_Code_History to ignore any entries that never match a period end and then combine any consecutive records with the same combination of field values into one with a start_date, end_date range that covers the original numerous rows
		SELECT z.ID
			,z.START_DATE
		INTO #TCodeRevisionExASLOB
		FROM (
			-- eliminate a records (if any) in the middle of the range of consecutive records with the same combination of field values and set the end record of the range to have a start date the same as the first
			SELECT y.ID
				,START_DATE = CASE WHEN y.PrevSame = 1 THEN LAG(y.START_DATE) OVER (PARTITION BY y.GroupingID ORDER BY y.GroupSequence) ELSE y.START_DATE END
				,y.NextSame
			FROM (
				-- identify where the same combination of fields are used in the previous and or next records
				SELECT x.ID
					,x.START_DATE
					,x.GroupingID
					,x.GroupSequence
					,PrevSame = CASE WHEN x.UniqueCombination = LAG(x.UniqueCombination) OVER (PARTITION BY x.GroupingID ORDER BY x.GroupSequence) THEN 1 ELSE 0 END
					,NextSame = CASE WHEN x.UniqueCombination = LEAD(x.UniqueCombination) OVER (PARTITION BY x.GroupingID ORDER BY x.GroupSequence) THEN 1 ELSE 0 END
				FROM (
					-- set up fields to simplify comparisons
					SELECT ID = tch.ID
						,START_DATE = tch.START_DATE
						,GroupingID = DENSE_RANK() OVER (ORDER BY tch.Contract_NBR, tch.lob_name)
						,GroupSequence = ROW_NUMBER() OVER (PARTITION BY tch.Contract_NBR, tch.lob_name ORDER BY tch.START_DATE)
						,UniqueCombination = DENSE_RANK() OVER (PARTITION BY tch.Contract_NBR
								,tch.lob_name
								ORDER BY tch.RPT_OFF_NAME
								,tch.DIV_NAME
								,tch.DEPT_NAME
								,tch.SUB_DEPT_NAME
								,tch.T2_CODE
								,tch.T7_CODE
								,tch.T9_CODE
								,tch.T8_CODE
								--,tch.ASLOB
								,tch.CLMS_PROCSS_CLM_DEPT
								,tch.MBU
								,tch.L01
								,tch.L02
								,tch.L03
								,tch.L06
								,tch.L07
								,tch.L10
								,tch.GD1
								,tch.RPTCURR1_CD
								,tch.RPTCURR2_CD
								,tch.ICP_CEDED_FLG
								,tch.solvency_II_regulatory_key
							)
					FROM EDW_PREPROD.dbo.T_Code_History tch
					INNER JOIN #TCodeUsed tcu
						ON tcu.START_DATE = tch.START_DATE
						AND tcu.END_DATE = tch.END_DATE
					-- eliminate any T_Code_History entries that would never match the end of an accounting period i.e. would never be used
					WHERE tcu.ContainsAccountingPeriod = 1
					) x
				) y
			-- eliminate a records (if any) in the middle of the range of consecutive records with the same combination of field values
			WHERE NOT (y.PrevSame = 1 AND y.NextSame = 1)
			) z
		-- keep only the last record in any range of consecutive records with the same combination of field values
		WHERE z.NextSame = 0

		INSERT INTO #Timings SELECT SYSDATETIME(), 'Created #TCodeRevisionExASLOB', @@ERROR

		DROP TABLE IF EXISTS #CatCodeUsed

		SELECT START_DATE = x.START_DATE
			,END_DATE = x.END_DATE
			,ContainsAccountingPeriod = CAST(CASE WHEN EXISTS (
							SELECT TOP 1 Column1 = 1
							FROM #AccountingPeriod ap
							WHERE ap.OffsetAccountingEndDate > x.START_DATE
								AND ap.OffsetAccountingEndDate < x.END_DATE
						) THEN 1 ELSE 0 END AS BIT)
		INTO #CatCodeUsed
		FROM (
			SELECT DISTINCT START_DATE = START_DATE
				,END_DATE = END_DATE
			FROM EDW_PREPROD.dbo.TIRS_CATCODE_HISTORY tch
			) x

		INSERT INTO #Timings SELECT SYSDATETIME(), 'Created #CatCodeUsed', @@ERROR

		DROP TABLE IF EXISTS #CatCodeRevisionExCatCodeCatKey

		-- Revise TIRS_CatCode_History to ignore any entries that never match a period end and then combine any consecutive records with the same combination of field values into one with a start_date, end_date range that covers the original numerous rows
		SELECT z.ID
			,z.START_DATE
		INTO #CatCodeRevisionExCatCodeCatKey
		FROM (
			-- eliminate a records (if any) in the middle of the range of consecutive records with the same combination of field values and set the end record of the range to have a start date the same as the first
			SELECT y.ID
				,START_DATE = CASE WHEN y.PrevSame = 1 THEN LAG(y.START_DATE) OVER (PARTITION BY y.GroupingID ORDER BY y.GroupSequence) ELSE y.START_DATE END
				,y.NextSame
			FROM (
				-- identify where the same combination of fields are used in the previous and or next records
				SELECT x.ID
					,x.START_DATE
					,x.GroupingID
					,x.GroupSequence
					,PrevSame = CASE WHEN x.UniqueCombination = LAG(x.UniqueCombination) OVER (PARTITION BY x.GroupingID ORDER BY x.GroupSequence) THEN 1 ELSE 0 END
					,NextSame = CASE WHEN x.UniqueCombination = LEAD(x.UniqueCombination) OVER (PARTITION BY x.GroupingID ORDER BY x.GroupSequence) THEN 1 ELSE 0 END
				FROM (
					-- set up fields to simplify comparisons
					SELECT ID = tch.ID
						,START_DATE = tch.START_DATE
						,GroupingID = DENSE_RANK() OVER (ORDER BY tch.TIRS_CLM_CD)
						,GroupSequence = ROW_NUMBER() OVER (PARTITION BY tch.TIRS_CLM_CD ORDER BY tch.START_DATE)
						,UniqueCombination = DENSE_RANK() OVER (PARTITION BY tch.TIRS_CLM_CD
								ORDER BY tch.AccidentYear
								--,tch.CAT_KEY
								--,tch.CatCode
								,tch.L04
							)
					FROM EDW_PREPROD.dbo.TIRS_CatCode_History tch
					INNER JOIN #CatCodeUsed ccu
						ON ccu.START_DATE = tch.START_DATE
						AND ccu.END_DATE = tch.END_DATE
					-- eliminate any T_Code_History entries that would never match the end of an accounting period i.e. would never be used
					WHERE ccu.ContainsAccountingPeriod = 1
					) x
				) y
			-- eliminate a records (if any) in the middle of the range of consecutive records with the same combination of field values
			WHERE NOT (y.PrevSame = 1 AND y.NextSame = 1)
			) z
		-- keep only the last record in any range of consecutive records with the same combination of field values
		WHERE z.NextSame = 0

		INSERT INTO #Timings SELECT SYSDATETIME(), 'Created #TCodeRevisionExASLOB', @@ERROR

		DROP TABLE IF EXISTS #L04

		SELECT TIRS_CLM_CD = H.TIRS_CLM_CD
			,CAT_KEY = H.CAT_KEY
			,CatCode = H.CatCode
			,AccidentYear = H.AccidentYear
			,L04 = H.L04
			,START_DATE = ccr.START_DATE
		INTO #L04
		FROM (
			SELECT DISTINCT TIRS_CLM_CD = clpo.TIRS_CLM_CD COLLATE DATABASE_DEFAULT
				,clpo.REG_DATE
			FROM EDW_Staging.assumed.TIRSClaimLossPaidOSLR clpo
			INNER JOIN #ContractFilter cf
				ON cf.Contract_NBR = clpo.CONTRACT_NBR COLLATE DATABASE_DEFAULT
			WHERE clpo.EndDate = '31 Dec 9999'
			) c
		INNER JOIN EDW_PREPROD.dbo.TIRS_CATCODE_HISTORY h
			ON h.TIRS_CLM_CD = c.TIRS_CLM_CD
		INNER JOIN #CatCodeRevisionExCatCodeCatKey ccr
			ON ccr.ID = h.ID
		INNER JOIN #Parameters prm
			ON prm.CurrentOffsetAccountingEndDate > ccr.START_DATE
			AND prm.CurrentOffsetAccountingEndDate < h.END_DATE

		INSERT INTO #Timings SELECT SYSDATETIME(), 'Created #L04', @@ERROR

		DROP TABLE IF EXISTS #ClaimLoadWide

		CREATE TABLE #ClaimLoadWide
		(ClaimLoadWideID INT IDENTITY NOT NULL
		,TREATY_NBR VARCHAR(5) COLLATE DATABASE_DEFAULT NULL
		,UNDERWRITING_YEAR VARCHAR(4) COLLATE DATABASE_DEFAULT NULL
		,Ceded_CONTRACT_NBR VARCHAR(9) COLLATE DATABASE_DEFAULT NULL
		,CONTRACT_NBR VARCHAR(20) COLLATE DATABASE_DEFAULT NULL
		,SourceSystemKey BIGINT NULL
		,TransactionTypeCode VARCHAR(10) COLLATE DATABASE_DEFAULT NULL
		,TransactionTypeCategory VARCHAR(30) COLLATE DATABASE_DEFAULT NULL
		,DueDate DATE NULL
		,acct_from_dt	DATE NULL
		,acct_to_dt	    DATE NULL
		,doc_key        VARCHAR(25)  COLLATE DATABASE_DEFAULT NULL
		,ORIGCURR_CD VARCHAR(3) COLLATE DATABASE_DEFAULT NULL
		,TIRS_ORIG_CURR_CD VARCHAR(3) COLLATE DATABASE_DEFAULT NULL
		,SETTL_CURR_CD VARCHAR(3) COLLATE DATABASE_DEFAULT NULL
		,TIRS_ORIG_CURR_NAME VARCHAR(50) COLLATE DATABASE_DEFAULT NULL
		,lob_name VARCHAR(100) COLLATE DATABASE_DEFAULT NULL
		,AccidentYear CHAR(4) COLLATE DATABASE_DEFAULT NULL
		,aslob VARCHAR(20) COLLATE DATABASE_DEFAULT NULL
		,TIRS_UW_ASSM_CEDED_NAME VARCHAR(7) COLLATE DATABASE_DEFAULT NULL
		,reg_date DATE NULL
		,Claim_NBR VARCHAR(10) COLLATE DATABASE_DEFAULT NULL
		,TIRS_CLM_CD VARCHAR(20) COLLATE DATABASE_DEFAULT NULL
		,CatCode VARCHAR(10) COLLATE DATABASE_DEFAULT NULL
		,CAT_KEY VARCHAR(20) COLLATE DATABASE_DEFAULT NULL
		,solvency_II_regulatory_key INT NULL
		,CLAIMLOSSDATE DATETIME NULL
		,bill_co_br_key INT NULL
		,Summable_LOSS_PAID MONEY NULL
		,SUMMABLE_LOSS_PAID_USD MONEY NULL
		,SUMMABLE_LOSS_EXP_PAID MONEY NULL
		,SUMMABLE_LOSS_EXP_PAID_USD MONEY NULL
		,SUMMABLE_LAE MONEY NULL
		,SUMMABLE_LAE_USD MONEY NULL
		,SUMMABLE_CASH_LOSS_ADV_AMT MONEY NULL
		,SUMMABLE_CASH_LOSS_ADV_AMT_USD MONEY NULL
		,SUMMABLE_CASH_LOSS_REFUND MONEY NULL
		,SUMMABLE_CASH_LOSS_REFUND_USD MONEY NULL
		,SUMMABLE_funds_released_losses MONEY NULL
		,SUMMABLE_funds_released_losses_USD MONEY NULL
		,SUMMABLE_reinstatement_premium MONEY NULL
		,SUMMABLE_reinstatement_premium_USD MONEY NULL
		,SUMMABLE_OS_LOSS MONEY NULL
		,SUMMABLE_OS_LOSS_EXP MONEY NULL
		,SUMMABLE_OS_LOSS_USD MONEY NULL
		,SUMMABLE_OS_LOSS_EXP_USD MONEY NULL
		,Summable_Ceded_LOSS_PAID MONEY NULL
		,SUMMABLE_Ceded_LOSS_PAID_USD MONEY NULL
		,SUMMABLE_Ceded_LOSS_EXP_PAID MONEY NULL
		,SUMMABLE_Ceded_LOSS_EXP_PAID_USD MONEY NULL
		,SUMMABLE_Ceded_LAE MONEY NULL
		,SUMMABLE_Ceded_LAE_USD MONEY NULL
		,SUMMABLE_Ceded_CASH_LOSS_ADV_AMT MONEY NULL
		,SUMMABLE_Ceded_CASH_LOSS_ADV_AMT_USD MONEY NULL
		,SUMMABLE_Ceded_CASH_LOSS_REFUND MONEY NULL
		,SUMMABLE_Ceded_CASH_LOSS_REFUND_USD MONEY NULL
		,SUMMABLE_Ceded_funds_released_losses MONEY NULL
		,SUMMABLE_Ceded_funds_released_losses_USD MONEY NULL
		,SUMMABLE_Ceded_OS_LOSS MONEY NULL
		,SUMMABLE_Ceded_OS_LOSS_EXP MONEY NULL
		,SUMMABLE_Ceded_OS_LOSS_USD MONEY NULL
		,SUMMABLE_Ceded_OS_LOSS_EXP_USD MONEY NULL
		,SUMMABLE_Ceded_reinstatement_premium MONEY NULL
		,SUMMABLE_Ceded_reinstatement_premium_USD MONEY NULL

		,FIRVIBNRBeg MONEY NULL
		,CededFIRVIBNRBeg MONEY NULL
		,FIRVIBNREnd MONEY NULL
		,CededFIRVIBNREnd MONEY NULL
		,FIRVIBNRBegUSD MONEY NULL
		,CededFIRVIBNRBegUSD MONEY NULL
		,FIRVIBNREndUSD MONEY NULL
		,CededFIRVIBNREndUSD MONEY NULL

		,Source VARCHAR(20) COLLATE DATABASE_DEFAULT NULL
		,SourceID AS CASE WHEN Source = 'TIRS' THEN 4 WHEN Source = 'OPENBOX' THEN 1 ELSE NULL END PERSISTED
		,adjustmenttype VARCHAR(100) COLLATE DATABASE_DEFAULT NULL
		,financial_lob VARCHAR(10) COLLATE DATABASE_DEFAULT NULL
		,T7_CODE VARCHAR(20) COLLATE DATABASE_DEFAULT NULL
		,T8_CODE VARCHAR(20) COLLATE DATABASE_DEFAULT NULL
		,T9_CODE CHAR(1) COLLATE DATABASE_DEFAULT NULL
		,InsurerCode VARCHAR(20) COLLATE DATABASE_DEFAULT NULL
		,CLMS_PROCSS_CLM_DEPT CHAR(1) COLLATE DATABASE_DEFAULT NULL
		,ICP_CEDED_FLG CHAR(1) COLLATE DATABASE_DEFAULT NULL
		,RPT_OFF_NAME VARCHAR(40) COLLATE DATABASE_DEFAULT NULL
		,ActuarialLob VARCHAR(100) COLLATE DATABASE_DEFAULT NULL
		,MBU CHAR(3) COLLATE DATABASE_DEFAULT NULL
		,L01 CHAR(3) COLLATE DATABASE_DEFAULT NULL
		,L02 CHAR(3) COLLATE DATABASE_DEFAULT NULL
		,L03 VARCHAR(7) COLLATE DATABASE_DEFAULT NULL
		,L04 VARCHAR(20) COLLATE DATABASE_DEFAULT NULL
		,L06 CHAR(4) COLLATE DATABASE_DEFAULT NULL
		,L07 VARCHAR(15) COLLATE DATABASE_DEFAULT NULL
		,L10 VARCHAR(10) COLLATE DATABASE_DEFAULT NULL
		,GD1 VARCHAR(10) COLLATE DATABASE_DEFAULT NULL
		,RPTCURR1_CD CHAR(3) COLLATE DATABASE_DEFAULT NULL
		,RPTCURR2_CD CHAR(3) COLLATE DATABASE_DEFAULT NULL
		,RPTCURR1 FLOAT NULL
		,RPTCURR2 FLOAT NULL
		,SETTL_RPTCURR1 FLOAT NULL
		,SETTL_RPTCURR2 FLOAT NULL
		,Summable_SETTL_LOSS_PAID MONEY NULL
		,Summable_SETTL_LOSS_PAID_USD MONEY NULL
		,Summable_SETTL_LAE MONEY NULL
		,Summable_SETTL_LAE_USD MONEY NULL
		,DimContractID INT NULL
		,DimClaimTransactionID INT NULL
		,Ceded_DimContractID INT NULL
		,Intended_DimAccountingPeriodID SMALLINT NULL
		,DimAccidentYearID SMALLINT NULL
		,Intended_DimAccountingID INT NULL
		,DimAccountingID INT NULL
		,DimAdjustmentTypeID SMALLINT NULL
		,Orig_DimCurrencyID TINYINT NULL
		,Settl_DimCurrencyID TINYINT NULL
		,DimLineOfBusinessID SMALLINT NULL
		,OrigRpt1_DimExchangeRateID INT NULL
		,OrigRpt2_DimExchangeRateID INT NULL
		,SettlRpt1_DimExchangeRateID INT NULL
		,SettlRpt2_DimExchangeRateID INT NULL
		,DimTransactionTypeID SMALLINT NULL
		,DimDueDateID INT NULL
		,DimFromDateID INT NULL
	    ,DimToDateID INT NULL		
	    ,DimPayeeID INT NULL
		,AdjustedTCodeL04 BIT NOT NULL
		,DimDocumentID INT NULL
		)

		;WITH CLM_LOAD AS (
				SELECT TREATY_NBR = BK.TREATY_NBR COLLATE DATABASE_DEFAULT
					,UNDERWRITING_YEAR = BK.UNDERWRITING_YEAR COLLATE DATABASE_DEFAULT
					,Ceded_CONTRACT_NBR = BK.Ceded_CONTRACT_NBR COLLATE DATABASE_DEFAULT
					,CONTRACT_NBR = CAST(BK.CONTRACT_NBR AS VARCHAR(25)) COLLATE DATABASE_DEFAULT
					,SourceSystemKey = CAST(10000000000 + pc.byline_key AS BIGINT)
					,TransactionTypeCode = CAST(pc.doc_type_cd AS VARCHAR(10))
					,TransactionTypeCategory = 'Document Type'
					,DueDate = pc.due_dt
					,acct_from_dt = pc.acct_from_dt
					,acct_to_dt = pc.acct_to_dt  
					,doc_key = pc.doc_key  --COLLATE DATABASE_DEFAULT 
					,ORIGCURR_CD = BK.ORIGCURR_CD COLLATE DATABASE_DEFAULT
					,TIRS_ORIG_CURR_CD = BK.TIRS_ORIG_CURR_CD COLLATE DATABASE_DEFAULT
					,TIRS_ORIG_CURR_NAME = BK.TIRS_ORIG_CURR_NAME COLLATE DATABASE_DEFAULT
					,lob_name = BK.lob_name COLLATE DATABASE_DEFAULT
					,AccidentYear = BK.AccidentYear COLLATE DATABASE_DEFAULT
					,aslob = BK.aslob COLLATE DATABASE_DEFAULT
					,TIRS_UW_ASSM_CEDED_NAME = CASE Bk.assumed_ceded_flg WHEN 'C' THEN 'Ceded' WHEN 'A' THEN 'Assumed' END COLLATE DATABASE_DEFAULT
					,reg_date = Bk.reg_date
					,Claim_NBR = 'N/A' COLLATE DATABASE_DEFAULT
					,TIRS_CLM_CD = 'N/A' COLLATE DATABASE_DEFAULT --CAST(TREATY_NBR AS VARCHAR(255))
					,CatCode = '' COLLATE DATABASE_DEFAULT
					,CAT_KEY = '' COLLATE DATABASE_DEFAULT
					,solvency_II_regulatory_key = solvency_II_regulatory_key
					,CLAIMLOSSDATE = NULL
					,adjustmenttype = CAST('N/A' AS VARCHAR(250)) COLLATE DATABASE_DEFAULT
					,bill_co_br_key = pc.bill_co_br_key
					,Summable_LOSS_PAID = CAST(ISNULL(CASE BK.assumed_ceded_flg WHEN 'C' THEN 0 ELSE PC.Summable_LOSS_PAID END, 0) AS MONEY)
					,SUMMABLE_LOSS_PAID_USD = CAST(ISNULL(CASE BK.assumed_ceded_flg WHEN 'C' THEN 0 ELSE PC.SUMMABLE_LOSS_PAID_USD END, 0) AS MONEY)
					,SUMMABLE_LOSS_EXP_PAID = CAST(ISNULL(CASE BK.assumed_ceded_flg WHEN 'C' THEN 0 ELSE PC.SUMMABLE_LOSS_EXP_PAID END, 0) AS MONEY)
					,SUMMABLE_LOSS_EXP_PAID_USD = CAST(ISNULL(CASE BK.assumed_ceded_flg WHEN 'C' THEN 0 ELSE PC.SUMMABLE_LOSS_EXP_PAID_USD END, 0) AS MONEY)
					,SUMMABLE_LAE = CAST(ISNULL(CASE BK.assumed_ceded_flg WHEN 'C' THEN 0 ELSE PC.SUMMABLE_LAE END, 0) AS MONEY)
					,SUMMABLE_LAE_USD = CAST(ISNULL(CASE BK.assumed_ceded_flg WHEN 'C' THEN 0 ELSE PC.SUMMABLE_LAE_USD END, 0) AS MONEY)
					,SUMMABLE_CASH_LOSS_ADV_AMT = CAST(ISNULL(CASE BK.assumed_ceded_flg WHEN 'C' THEN 0 ELSE PC.SUMMABLE_CASH_LOSS_ADV_AMT END, 0) AS MONEY)
					,SUMMABLE_CASH_LOSS_ADV_AMT_USD = CAST(ISNULL(CASE BK.assumed_ceded_flg WHEN 'C' THEN 0 ELSE PC.SUMMABLE_CASH_LOSS_ADV_AMT_USD END, 0) AS MONEY)
					,SUMMABLE_CASH_LOSS_REFUND = CAST(ISNULL(CASE BK.assumed_ceded_flg WHEN 'C' THEN 0 ELSE PC.SUMMABLE_CASH_LOSS_REFUND END, 0) AS MONEY)
					,SUMMABLE_CASH_LOSS_REFUND_USD = CAST(ISNULL(CASE BK.assumed_ceded_flg WHEN 'C' THEN 0 ELSE PC.SUMMABLE_CASH_LOSS_REFUND_USD END, 0) AS MONEY)
					,SUMMABLE_funds_released_losses = CAST(ISNULL(CASE BK.assumed_ceded_flg WHEN 'C' THEN 0 ELSE PC.SUMMABLE_funds_released_losses END, 0) AS MONEY)
					,SUMMABLE_funds_released_losses_USD = CAST(ISNULL(CASE BK.assumed_ceded_flg WHEN 'C' THEN 0 ELSE PC.SUMMABLE_funds_released_losses_USD END, 0) AS MONEY)
					,SUMMABLE_reinstatement_premium = CAST(ISNULL(CASE BK.assumed_ceded_flg WHEN 'C' THEN 0 ELSE PC.SUMMABLE_reinstatement_premium END, 0) AS MONEY)
					,SUMMABLE_reinstatement_premium_USD = CAST(ISNULL(CASE BK.assumed_ceded_flg WHEN 'C' THEN 0 ELSE PC.SUMMABLE_reinstatement_premium_USD END, 0) AS MONEY)
					,SUMMABLE_OS_LOSS = CAST(0 AS MONEY)
					,SUMMABLE_OS_LOSS_EXP = CAST(0 AS MONEY)
					,SUMMABLE_OS_LOSS_USD = CAST(0 AS MONEY)
					,SUMMABLE_OS_LOSS_EXP_USD = CAST(0 AS MONEY)
					,Summable_Ceded_LOSS_PAID = CAST(ISNULL(CASE BK.assumed_ceded_flg WHEN 'C' THEN PC.Summable_LOSS_PAID ELSE 0 END, 0) AS MONEY)
					,SUMMABLE_Ceded_LOSS_PAID_USD = CAST(ISNULL(CASE BK.assumed_ceded_flg WHEN 'C' THEN PC.SUMMABLE_LOSS_PAID_USD ELSE 0 END, 0) AS MONEY)
					,SUMMABLE_Ceded_LOSS_EXP_PAID = CAST(ISNULL(CASE BK.assumed_ceded_flg WHEN 'C' THEN PC.SUMMABLE_LOSS_EXP_PAID ELSE 0 END, 0) AS MONEY)
					,SUMMABLE_Ceded_LOSS_EXP_PAID_USD = CAST(ISNULL(CASE BK.assumed_ceded_flg WHEN 'C' THEN PC.SUMMABLE_LOSS_EXP_PAID_USD ELSE 0 END, 0) AS MONEY)
					,SUMMABLE_Ceded_LAE = CAST(ISNULL(CASE BK.assumed_ceded_flg WHEN 'C' THEN PC.SUMMABLE_LAE ELSE 0 END, 0) AS MONEY)
					,SUMMABLE_Ceded_LAE_USD = CAST(ISNULL(CASE BK.assumed_ceded_flg WHEN 'C' THEN PC.SUMMABLE_LAE_USD ELSE 0 END, 0) AS MONEY)
					,SUMMABLE_Ceded_CASH_LOSS_ADV_AMT = CAST(ISNULL(CASE BK.assumed_ceded_flg WHEN 'C' THEN PC.SUMMABLE_CASH_LOSS_ADV_AMT ELSE 0 END, 0) AS MONEY)
					,SUMMABLE_Ceded_CASH_LOSS_ADV_AMT_USD = CAST(ISNULL(CASE BK.assumed_ceded_flg WHEN 'C' THEN PC.SUMMABLE_CASH_LOSS_ADV_AMT_USD ELSE 0 END, 0) AS MONEY)
					,SUMMABLE_Ceded_CASH_LOSS_REFUND = CAST(ISNULL(CASE BK.assumed_ceded_flg WHEN 'C' THEN PC.SUMMABLE_CASH_LOSS_REFUND ELSE 0 END, 0) AS MONEY)
					,SUMMABLE_Ceded_CASH_LOSS_REFUND_USD = CAST(ISNULL(CASE BK.assumed_ceded_flg WHEN 'C' THEN PC.SUMMABLE_CASH_LOSS_REFUND_USD ELSE 0 END, 0) AS MONEY)
					,SUMMABLE_Ceded_funds_released_losses = CAST(ISNULL(CASE BK.assumed_ceded_flg WHEN 'C' THEN PC.SUMMABLE_funds_released_losses ELSE 0 END, 0) AS MONEY)
					,SUMMABLE_Ceded_funds_released_losses_USD = CAST(ISNULL(CASE BK.assumed_ceded_flg WHEN 'C' THEN PC.SUMMABLE_funds_released_losses_USD ELSE 0 END, 0) AS MONEY)
					,SUMMABLE_Ceded_reinstatement_premium = CAST(ISNULL(CASE BK.assumed_ceded_flg WHEN 'C' THEN PC.SUMMABLE_reinstatement_premium ELSE 0 END, 0) AS MONEY)
					,SUMMABLE_Ceded_reinstatement_premium_USD = CAST(ISNULL(CASE BK.assumed_ceded_flg WHEN 'C' THEN PC.SUMMABLE_reinstatement_premium_USD ELSE 0 END, 0) AS MONEY)
					,SUMMABLE_Ceded_OS_LOSS = CAST(0 AS MONEY)
					,SUMMABLE_Ceded_OS_LOSS_EXP = CAST(0 AS MONEY)
					,SUMMABLE_Ceded_OS_LOSS_USD = CAST(0 AS MONEY)
					,SUMMABLE_Ceded_OS_LOSS_EXP_USD = CAST(0 AS MONEY)

					,0 as FIRVIBNRBeg
					,0 as CededFIRVIBNRBeg
					,0 as FIRVIBNREnd
					,0 as CededFIRVIBNREnd
					,0 as FIRVIBNRBegUSD
					,0 as CededFIRVIBNRBegUSD
					,0 as FIRVIBNREndUSD
					,0 as CededFIRVIBNREndUSD

				FROM #BaseKey BK
				CROSS JOIN #Parameters prm
				INNER JOIN EDW_Staging.assumed.TIRSAccountingLossPaidEarnedAccidentYear pc
					ON BK.CONTRACT_NBR = PC.CONTRACT_NBR COLLATE DATABASE_DEFAULT
						AND BK.LOB_NAME = PC.LOB_NAME COLLATE DATABASE_DEFAULT
						AND ISNULL(BK.AccidentYear, '') = ISNULL(PC.AccidentYear, '')
						AND BK.TIRS_ORIG_CURR_CD = PC.TIRS_ORIG_CURR_CD COLLATE DATABASE_DEFAULT
						AND BK.reg_date = PC.reg_date
						AND BK.assumed_ceded_flg = PC.assumed_ceded_flg COLLATE DATABASE_DEFAULT
						AND pc.EndDate = '31 Dec 9999'

				UNION ALL
				SELECT TREATY_NBR = BK.TREATY_NBR COLLATE DATABASE_DEFAULT
					,UNDERWRITING_YEAR = BK.UNDERWRITING_YEAR COLLATE DATABASE_DEFAULT
					,Ceded_CONTRACT_NBR = BK.Ceded_CONTRACT_NBR COLLATE DATABASE_DEFAULT
					,CONTRACT_NBR = CAST(BK.CONTRACT_NBR AS VARCHAR(25)) COLLATE DATABASE_DEFAULT
					,SourceSystemKey = CAST(NULL AS BIGINT)
					,TransactionTypeCode = NULL
					,TransactionTypeCategory = NULL
					,DueDate = NULL
					,acct_from_dt = NULL
					,acct_to_dt = NULL 
					,doc_key = NULL 
					,ORIGCURR_CD = BK.ORIGCURR_CD COLLATE DATABASE_DEFAULT
					,TIRS_ORIG_CURR_CD = BK.TIRS_ORIG_CURR_CD COLLATE DATABASE_DEFAULT
					,TIRS_ORIG_CURR_NAME = BK.TIRS_ORIG_CURR_NAME COLLATE DATABASE_DEFAULT
					,lob_name = BK.lob_name COLLATE DATABASE_DEFAULT
					,AccidentYear = BK.AccidentYear COLLATE DATABASE_DEFAULT
					,aslob = BK.aslob COLLATE DATABASE_DEFAULT
					,TIRS_UW_ASSM_CEDED_NAME = CASE Bk.assumed_ceded_flg WHEN 'C' THEN 'Ceded' WHEN 'A' THEN 'Assumed' END COLLATE DATABASE_DEFAULT
					,reg_date = Bk.reg_date
					,Claim_NBR = 'N/A' COLLATE DATABASE_DEFAULT
					,TIRS_CLM_CD = 'N/A' COLLATE DATABASE_DEFAULT --CAST(TREATY_NBR AS VARCHAR(255))
					,CatCode = '' COLLATE DATABASE_DEFAULT
					,CAT_KEY = '' COLLATE DATABASE_DEFAULT
					,solvency_II_regulatory_key = solvency_II_regulatory_key
					,CLAIMLOSSDATE = NULL
					,adjustmenttype = CAST('N/A' AS VARCHAR(250)) COLLATE DATABASE_DEFAULT
					,bill_co_br_key = os.bill_co_br_key
					,Summable_LOSS_PAID = CAST(0 AS MONEY)
					,SUMMABLE_LOSS_PAID_USD = CAST(0 AS MONEY)
					,SUMMABLE_LOSS_EXP_PAID = CAST(0 AS MONEY)
					,SUMMABLE_LOSS_EXP_PAID_USD = CAST(0 AS MONEY)
					,SUMMABLE_LAE = CAST(0 AS MONEY)
					,SUMMABLE_LAE_USD = CAST(0 AS MONEY)
					,SUMMABLE_CASH_LOSS_ADV_AMT = CAST(0 AS MONEY)
					,SUMMABLE_CASH_LOSS_ADV_AMT_USD = CAST(0 AS MONEY)
					,SUMMABLE_CASH_LOSS_REFUND = CAST(0 AS MONEY)
					,SUMMABLE_CASH_LOSS_REFUND_USD = CAST(0 AS MONEY)
					,SUMMABLE_funds_released_losses = CAST(0 AS MONEY)
					,SUMMABLE_funds_released_losses_USD = CAST(0 AS MONEY)
					,SUMMABLE_reinstatement_premium = CAST(0 AS MONEY)
					,SUMMABLE_reinstatement_premium_USD = CAST(0 AS MONEY)
					,SUMMABLE_OS_LOSS = CAST(ISNULL(CASE BK.assumed_ceded_flg WHEN 'C' THEN 0 ELSE OS.SUMMABLE_OS_LOSS END, 0) AS MONEY)
					,SUMMABLE_OS_LOSS_EXP = CAST(ISNULL(CASE BK.assumed_ceded_flg WHEN 'C' THEN 0 ELSE OS.SUMMABLE_OS_LOSS_EXP END, 0) AS MONEY)
					,SUMMABLE_OS_LOSS_USD = CAST(ISNULL(CASE BK.assumed_ceded_flg WHEN 'C' THEN 0 ELSE OS.SUMMABLE_OS_LOSS_USD END, 0) AS MONEY)
					,SUMMABLE_OS_LOSS_EXP_USD = CAST(ISNULL(CASE BK.assumed_ceded_flg WHEN 'C' THEN 0 ELSE OS.SUMMABLE_OS_LOSS_EXP_USD END, 0) AS MONEY)
					,Summable_Ceded_LOSS_PAID = CAST(0 AS MONEY)
					,SUMMABLE_Ceded_LOSS_PAID_USD = CAST(0 AS MONEY)
					,SUMMABLE_Ceded_LOSS_EXP_PAID = CAST(0 AS MONEY)
					,SUMMABLE_Ceded_LOSS_EXP_PAID_USD = CAST(0 AS MONEY)
					,SUMMABLE_Ceded_LAE = CAST(0 AS MONEY)
					,SUMMABLE_Ceded_LAE_USD = CAST(0 AS MONEY)
					,SUMMABLE_Ceded_CASH_LOSS_ADV_AMT = CAST(0 AS MONEY)
					,SUMMABLE_Ceded_CASH_LOSS_ADV_AMT_USD = CAST(0 AS MONEY)
					,SUMMABLE_Ceded_CASH_LOSS_REFUND = CAST(0 AS MONEY)
					,SUMMABLE_Ceded_CASH_LOSS_REFUND_USD = CAST(0 AS MONEY)
					,SUMMABLE_Ceded_funds_released_losses = CAST(0 AS MONEY)
					,SUMMABLE_Ceded_funds_released_losses_USD = CAST(0 AS MONEY)
					,SUMMABLE_Ceded_reinstatement_premium = CAST(0 AS MONEY)
					,SUMMABLE_Ceded_reinstatement_premium_USD = CAST(0 AS MONEY)
					,SUMMABLE_Ceded_OS_LOSS = CAST(ISNULL(CASE BK.assumed_ceded_flg WHEN 'C' THEN OS.SUMMABLE_OS_LOSS ELSE 0 END, 0) AS MONEY)
					,SUMMABLE_Ceded_OS_LOSS_EXP = CAST(ISNULL(CASE BK.assumed_ceded_flg WHEN 'C' THEN OS.SUMMABLE_OS_LOSS_EXP ELSE 0 END, 0) AS MONEY)
					,SUMMABLE_Ceded_OS_LOSS_USD = CAST(ISNULL(CASE BK.assumed_ceded_flg WHEN 'C' THEN OS.SUMMABLE_OS_LOSS_USD ELSE 0 END, 0) AS MONEY)
					,SUMMABLE_Ceded_OS_LOSS_EXP_USD = CAST(ISNULL(CASE BK.assumed_ceded_flg WHEN 'C' THEN OS.SUMMABLE_OS_LOSS_EXP_USD ELSE 0 END, 0) AS MONEY)
					,0 as FIRVIBNRBeg
					,0 as CededFIRVIBNRBeg
					,0 as FIRVIBNREnd
					,0 as CededFIRVIBNREnd
					,0 as FIRVIBNRBegUSD
					,0 as CededFIRVIBNRBegUSD
					,0 as FIRVIBNREndUSD
					,0 as CededFIRVIBNREndUSD
				
				
				FROM #BaseKey BK
				CROSS JOIN #Parameters prm
				INNER JOIN EDW_Staging.assumed.TIRSOSLossEarnedAccidentYear os
					ON BK.CONTRACT_NBR = OS.CONTRACT_NBR COLLATE DATABASE_DEFAULT
						AND BK.LOB_NAME = OS.LOB_NAME COLLATE DATABASE_DEFAULT
						AND ISNULL(BK.AccidentYear, '') = ISNULL(OS.AccidentYear, '')
						AND BK.TIRS_ORIG_CURR_CD = OS.TIRS_ORIG_CURR_CD COLLATE DATABASE_DEFAULT
						AND BK.reg_date = OS.reg_date
						AND BK.assumed_ceded_flg = OS.assumed_ceded_flg COLLATE DATABASE_DEFAULT
						AND os.EndDate = '31 Dec 9999'
				UNION ALL
				SELECT TREATY_NBR = P.TREATY_NBR COLLATE DATABASE_DEFAULT
					,underwriting_YEAR = P.underwriting_YEAR COLLATE DATABASE_DEFAULT
					,CEDED_CONTRACT_NBR = P.CEDED_CONTRACT_NBR COLLATE DATABASE_DEFAULT
					,CONTRACT_NBR = P.CONTRACT_NBR COLLATE DATABASE_DEFAULT
					,SourceSystemKey = CAST(20000000000 + p.trans_key AS BIGINT)
					,TransactionTypeCode = CAST(p.trans_cd AS VARCHAR(10))
					,TransactionTypeCategory = 'Claim Transaction Type'
					,DueDate = p.entry_dt
					,acct_from_dt = p.FromDate
					,acct_to_dt = p.ToDate
					,doc_key = NULL 
					,ORIGCURR_CD = P.ORIGCURR_CD COLLATE DATABASE_DEFAULT
					,TIRS_ORIG_CURR_CD = P.TIRS_ORIG_CURR_CD COLLATE DATABASE_DEFAULT
					,TIRS_ORIG_CURR_NAME = P.TIRS_ORIG_CURR_NAME COLLATE DATABASE_DEFAULT
					,TIRS_LOB_NAME = P.TIRS_LOB_NAME COLLATE DATABASE_DEFAULT
					,AccidentYear = P.AccidentYear COLLATE DATABASE_DEFAULT
					,aslob = P.aslob COLLATE DATABASE_DEFAULT
					,TIRS_UW_ASSM_CEDED_NAME = CASE P.assumed_ceded_flg WHEN 'C' THEN 'Ceded' WHEN 'A' THEN 'Assumed' END COLLATE DATABASE_DEFAULT
					,Reg_Date = P.Reg_Date
					,Claim_NBR = P.Claim_NBR COLLATE DATABASE_DEFAULT
					,TIRS_CLM_CD = P.TIRS_CLM_CD COLLATE DATABASE_DEFAULT
					,CatCode = P.CatCode COLLATE DATABASE_DEFAULT
					,CAT_KEY = P.CAT_KEY COLLATE DATABASE_DEFAULT
					,solvency_II_regulatory_key = solvency_II_regulatory_key
					,CLAIMLOSSDATE = CLAIMLOSSDATE
					,adjustmenttype = 'N/A' COLLATE DATABASE_DEFAULT
					,bill_co_br_key = p.bill_co_br_key
					,Summable_LOSS_PAID = CAST(ISNULL(CASE P.assumed_ceded_flg WHEN 'C' THEN 0 ELSE P.SUMMABLE_LOSS_PAID END, 0) AS MONEY)
					,SUMMABLE_LOSS_PAID_USD = CAST(ISNULL(CASE P.assumed_ceded_flg WHEN 'C' THEN 0 ELSE P.SUMMABLE_LOSS_PAID_USD END, 0) AS MONEY)
					,[CAST] = CAST(0 AS MONEY)
					,[CAST] = CAST(0 AS MONEY)
					,SUMMABLE_LAE = CAST(ISNULL(CASE P.assumed_ceded_flg WHEN 'C' THEN 0 ELSE P.SUMMABLE_LAE END, 0) AS MONEY)
					,SUMMABLE_LAE_USD = CAST(ISNULL(CASE P.assumed_ceded_flg WHEN 'C' THEN 0 ELSE P.SUMMABLE_LAE_USD END, 0) AS MONEY)
					,SUMMABLE_CASH_LOSS_ADV_AMT = CAST(0 AS MONEY)
					,SUMMABLE_CASH_LOSS_ADV_AMT_USD = CAST(0 AS MONEY)
					,SUMMABLE_CASH_LOSS_REFUND = CAST(0 AS MONEY)
					,SUMMABLE_CASH_LOSS_REFUND_USD = CAST(0 AS MONEY)
					,SUMMABLE_funds_released_losses = CAST(0 AS MONEY)
					,SUMMABLE_funds_released_losses_USD = CAST(0 AS MONEY)
					,SUMMABLE_reinstatement_premium = CAST(ISNULL(CASE P.assumed_ceded_flg WHEN 'C' THEN 0 ELSE P.SUMMABLE_reinstatement_premium END, 0) AS MONEY)
					,SUMMABLE_reinstatement_premium_USD = CAST(ISNULL(CASE P.assumed_ceded_flg WHEN 'C' THEN 0 ELSE P.SUMMABLE_reinstatement_premium_USD END, 0) AS MONEY)
					,SUMMABLE_OS_LOSS = CAST(ISNULL(CASE P.assumed_ceded_flg WHEN 'C' THEN 0 ELSE SUMMABLE_OS_LOSS END, 0) AS MONEY)
					,SUMMABLE_OS_LOSS_EXP = CAST(ISNULL(CASE P.assumed_ceded_flg WHEN 'C' THEN 0 ELSE SUMMABLE_OS_LOSS_EXP END, 0) AS MONEY)
					,SUMMABLE_OS_LOSS_USD = CAST(ISNULL(CASE P.assumed_ceded_flg WHEN 'C' THEN 0 ELSE SUMMABLE_OS_LOSS_USD END, 0) AS MONEY)
					,SUMMABLE_OS_LOSS_EXP_USD = CAST(ISNULL(CASE P.assumed_ceded_flg WHEN 'C' THEN 0 ELSE SUMMABLE_OS_LOSS_EXP_USD END, 0) AS MONEY)
					,SUMMABLE_Ceded_LOSS_PAID = CAST(ISNULL(CASE P.assumed_ceded_flg WHEN 'C' THEN P.Summable_LOSS_PAID ELSE 0 END, 0) AS MONEY)
					,SUMMABLE_Ceded_LOSS_PAID_USD = CAST(ISNULL(CASE P.assumed_ceded_flg WHEN 'C' THEN P.SUMMABLE_LOSS_PAID_USD ELSE 0 END, 0) AS MONEY)
					,SUMMABLE_Ceded_LOSS_EXP_PAID = CAST(0 AS MONEY)
					,SUMMABLE_Ceded_LOSS_EXP_PAID_USD = CAST(0 AS MONEY)
					,SUMMABLE_Ceded_LAE = CAST(ISNULL(CASE P.assumed_ceded_flg WHEN 'C' THEN P.SUMMABLE_LAE ELSE 0 END, 0) AS MONEY)
					,SUMMABLE_Ceded_LAE_USD = CAST(ISNULL(CASE P.assumed_ceded_flg WHEN 'C' THEN P.SUMMABLE_LAE_USD ELSE 0 END, 0) AS MONEY)
					,SUMMABLE_Ceded_CASH_LOSS_ADV_AMT = CAST(0 AS MONEY)
					,SUMMABLE_Ceded_CASH_LOSS_ADV_AMT_USD = CAST(0 AS MONEY)
					,SUMMABLE_Ceded_CASH_LOSS_REFUND = CAST(0 AS MONEY)
					,SUMMABLE_Ceded_CASH_LOSS_REFUND_USD = CAST(0 AS MONEY)
					,SUMMABLE_Ceded_funds_released_losses = CAST(0 AS MONEY)
					,SUMMABLE_Ceded_funds_released_losses_USD = CAST(0 AS MONEY)
					,SUMMABLE_Ceded_reinstatement_premium = CAST(ISNULL(CASE P.assumed_ceded_flg WHEN 'C' THEN P.SUMMABLE_reinstatement_premium ELSE 0 END, 0) AS MONEY)
					,SUMMABLE_Ceded_reinstatement_premium_USD = CAST(ISNULL(CASE P.assumed_ceded_flg WHEN 'C' THEN P.SUMMABLE_reinstatement_premium_USD ELSE 0 END, 0) AS MONEY)
					,SUMMABLE_Ceded_OS_LOSS = CAST(ISNULL(CASE P.assumed_ceded_flg WHEN 'C' THEN SUMMABLE_OS_LOSS ELSE 0 END, 0) AS MONEY)
					,SUMMABLE_Ceded_OS_LOSS_EXP = CAST(ISNULL(CASE P.assumed_ceded_flg WHEN 'C' THEN SUMMABLE_OS_LOSS_EXP ELSE 0 END, 0) AS MONEY)
					,SUMMABLE_Ceded_OS_LOSS_USD = CAST(ISNULL(CASE P.assumed_ceded_flg WHEN 'C' THEN SUMMABLE_OS_LOSS_USD ELSE 0 END, 0) AS MONEY)
					,SUMMABLE_Ceded_OS_LOSS_EXP_USD = CAST(ISNULL(CASE P.assumed_ceded_flg WHEN 'C' THEN SUMMABLE_OS_LOSS_EXP_USD ELSE 0 END, 0) AS MONEY)
					,0 as FIRVIBNRBeg
					,0 as CededFIRVIBNRBeg
					,0 as FIRVIBNREnd
					,0 as CededFIRVIBNREnd
					,0 as FIRVIBNRBegUSD
					,0 as CededFIRVIBNRBegUSD
					,0 as FIRVIBNREndUSD
					,0 as CededFIRVIBNREndUSD	
				
				
				FROM EDW_Staging.assumed.TIRSClaimLossPaidOSLR p
				INNER JOIN #ContractFilter cf
					ON cf.Contract_NBR = p.CONTRACT_NBR COLLATE DATABASE_DEFAULT
				WHERE p.claim_description NOT IN ('Informational Only', 'Sub Claim')
					AND p.EndDate = '31 Dec 9999'
				UNION ALL
				SELECT TREATY_NBR = clpoi.TREATY_NBR COLLATE DATABASE_DEFAULT
					,UNDERWRITING_YEAR = clpoi.UNDERWRITING_YEAR COLLATE DATABASE_DEFAULT
					,Ceded_CONTRACT_NBR = clpoi.Ceded_CONTRACT_NBR COLLATE DATABASE_DEFAULT
					,CONTRACT_NBR = clpoi.CONTRACT_NBR COLLATE DATABASE_DEFAULT
					,SourceSystemKey = CAST(20000000000 + clpoi.trans_key AS BIGINT)
					,TransactionTypeCode = CAST(clpoi.trans_cd AS VARCHAR(10))
					,TransactionTypeCategory = 'Claim Transaction Type'
					,DueDate = clpoi.entry_dt
					,acct_from_dt = clpoi.FromDate
					,acct_to_dt = clpoi.ToDate
					,doc_key = NULL 
					,ORIGCURR_CD = clpoi.ORIGCURR_CD COLLATE DATABASE_DEFAULT
					,TIRS_ORIG_CURR_CD = clpoi.TIRS_ORIG_CURR_CD COLLATE DATABASE_DEFAULT
					,TIRS_ORIG_CURR_NAME = clpoi.TIRS_ORIG_CURR_NAME COLLATE DATABASE_DEFAULT
					,TIRS_LOB_NAME = clpoi.TIRS_LOB_NAME COLLATE DATABASE_DEFAULT
					,AccidentYear = clpoi.AccidentYear COLLATE DATABASE_DEFAULT
					,aslob = aslob COLLATE DATABASE_DEFAULT
					,TIRS_UW_ASSM_CEDED_NAME = CASE clpoi.assumed_ceded_flg WHEN 'C' THEN 'Ceded' WHEN 'A' THEN 'Assumed' END COLLATE DATABASE_DEFAULT
					,reg_date = clpoi.reg_date
					,Claim_NBR = clpoi.Claim_NBR COLLATE DATABASE_DEFAULT
					,TIRS_CLM_CD = clpoi.TIRS_CLM_CD COLLATE DATABASE_DEFAULT
					,CatCode = clpoi.CatCode COLLATE DATABASE_DEFAULT
					,CAT_KEY = clpoi.CAT_KEY COLLATE DATABASE_DEFAULT
					,solvency_II_regulatory_key = clpoi.solvency_II_regulatory_key
					,CLAIMLOSSDATE = NULL
					,adjustmenttype = clpoi.adjustmenttype COLLATE DATABASE_DEFAULT
					,bill_co_br_key = clpoi.bill_co_br_key
					,Summable_LOSS_PAID = IIF(clpoi.assumed_ceded_flg = 'C', 0, clpoi.Summable_LOSS_PAID)
					,SUMMABLE_LOSS_PAID_USD = IIF(clpoi.assumed_ceded_flg = 'C', 0, clpoi.SUMMABLE_LOSS_PAID_USD)
					,SUMMABLE_LOSS_EXP_PAID = 0
					,SUMMABLE_LOSS_EXP_PAID_USD = 0
					,SUMMABLE_LAE = IIF(clpoi.assumed_ceded_flg = 'C', 0, clpoi.SUMMABLE_LAE)
					,SUMMABLE_LAE_USD = IIF(clpoi.assumed_ceded_flg = 'C', 0, clpoi.SUMMABLE_LAE_USD)
					,SUMMABLE_CASH_LOSS_ADV_AMT = 0
					,SUMMABLE_CASH_LOSS_ADV_AMT_USD = 0
					,SUMMABLE_CASH_LOSS_REFUND = 0
					,SUMMABLE_CASH_LOSS_REFUND_USD = 0
					,SUMMABLE_funds_released_losses = 0
					,SUMMABLE_funds_released_losses_USD = 0
					,SUMMABLE_reinstatement_premium = IIF(clpoi.assumed_ceded_flg = 'C', 0, clpoi.SUMMABLE_reinstatement_premium)
					,SUMMABLE_reinstatement_premium_USD = IIF(clpoi.assumed_ceded_flg = 'C', 0, clpoi.SUMMABLE_reinstatement_premium_USD)
					,SUMMABLE_OS_LOSS = IIF(clpoi.assumed_ceded_flg = 'C', 0, clpoi.SUMMABLE_OS_LOSS)
					,SUMMABLE_OS_LOSS_EXP = IIF(clpoi.assumed_ceded_flg = 'C', 0, clpoi.SUMMABLE_OS_LOSS_EXP)
					,SUMMABLE_OS_LOSS_USD = IIF(clpoi.assumed_ceded_flg = 'C', 0, clpoi.SUMMABLE_OS_LOSS_USD)
					,SUMMABLE_OS_LOSS_EXP_USD = IIF(clpoi.assumed_ceded_flg = 'C', 0, clpoi.SUMMABLE_OS_LOSS_EXP_USD)
					,Summable_Ceded_LOSS_PAID = IIF(clpoi.assumed_ceded_flg = 'C', clpoi.Summable_LOSS_PAID, 0)
					,SUMMABLE_Ceded_LOSS_PAID_USD = IIF(clpoi.assumed_ceded_flg = 'C', clpoi.SUMMABLE_LOSS_PAID_USD, 0)
					,SUMMABLE_Ceded_LOSS_EXP_PAID = 0
					,SUMMABLE_Ceded_LOSS_EXP_PAID_USD = 0
					,SUMMABLE_Ceded_LAE = IIF(clpoi.assumed_ceded_flg = 'C', clpoi.SUMMABLE_LAE, 0)
					,SUMMABLE_Ceded_LAE_USD = IIF(clpoi.assumed_ceded_flg = 'C', clpoi.SUMMABLE_LAE_USD, 0)
					,SUMMABLE_Ceded_CASH_LOSS_ADV_AMT = 0
					,SUMMABLE_Ceded_CASH_LOSS_ADV_AMT_USD = 0
					,SUMMABLE_Ceded_CASH_LOSS_REFUND = 0
					,SUMMABLE_Ceded_CASH_LOSS_REFUND_USD = 0
					,SUMMABLE_Ceded_funds_released_losses = 0
					,SUMMABLE_Ceded_funds_released_losses_USD = 0
					,SUMMABLE_Ceded_reinstatement_premium = IIF(clpoi.assumed_ceded_flg = 'C', clpoi.SUMMABLE_reinstatement_premium, 0)
					,SUMMABLE_Ceded_reinstatement_premium_USD = IIF(clpoi.assumed_ceded_flg = 'C', clpoi.SUMMABLE_reinstatement_premium_USD, 0)
					,SUMMABLE_Ceded_OS_LOSS = IIF(clpoi.assumed_ceded_flg = 'C', clpoi.SUMMABLE_OS_LOSS, 0)
					,SUMMABLE_Ceded_OS_LOSS_EXP = IIF(clpoi.assumed_ceded_flg = 'C', clpoi.SUMMABLE_OS_LOSS_EXP, 0)
					,SUMMABLE_Ceded_OS_LOSS_USD = IIF(clpoi.assumed_ceded_flg = 'C', clpoi.SUMMABLE_OS_LOSS_USD, 0)
					,SUMMABLE_Ceded_OS_LOSS_EXP_USD = IIF(clpoi.assumed_ceded_flg = 'C', clpoi.SUMMABLE_OS_LOSS_EXP_USD, 0)
					,0 as FIRVIBNRBeg
					,0 as CededFIRVIBNRBeg
					,0 as FIRVIBNREnd
					,0 as CededFIRVIBNREnd
					,0 as FIRVIBNRBegUSD
					,0 as CededFIRVIBNRBegUSD
					,0 as FIRVIBNREndUSD
					,0 as CededFIRVIBNREndUSD		
						
				FROM EDW_Staging.assumed.TIRSClaimLossPaidOSLRInfo clpoi
				INNER JOIN #ContractFilter cf
					ON cf.Contract_NBR = clpoi.CONTRACT_NBR COLLATE DATABASE_DEFAULT
				WHERE clpoi.EndDate = '31 Dec 9999'
	
				UNION ALL

	SELECT TREATY_NBR = CAST(tm.trty_no AS VARCHAR(10)) COLLATE DATABASE_DEFAULT
	,UNDERWRITING_YEAR = tm.und_yr COLLATE DATABASE_DEFAULT
	,Ceded_CONTRACT_NBR = NULLIF(CONCAT(LEFT(ctm.trty_no, 5), ctm.und_yr), '') COLLATE DATABASE_DEFAULT
	,CONTRACT_NBR = CONCAT(LEFT(tm.trty_no, 5), tm.und_yr) COLLATE DATABASE_DEFAULT
	,SourceSystemKey = NULL
	,TransactionTypeCode = 'FIRV IBNR'
	,TransactionTypeCategory = 'FIRV IBNR'
	,DueDate = NULL
	,acct_from_dt = NULL
	,acct_to_dt = NULL
	,doc_key = NULL
	,ORIGCURR_CD = xcn.curr_iso_cd COLLATE DATABASE_DEFAULT
	,TIRS_ORIG_CURR_CD = mdo.curr_cd COLLATE DATABASE_DEFAULT
	,TIRS_ORIG_CURR_NAME = xcn.curr_nm COLLATE DATABASE_DEFAULT
	,lob_name = lob.desc_txt COLLATE DATABASE_DEFAULT
	,AccidentYear = tm.und_yr COLLATE DATABASE_DEFAULT
	,aslob = tacn.aslob COLLATE DATABASE_DEFAULT
	,TIRS_UW_ASSM_CEDED_NAME = CASE mdo.assumed_ceded_flg WHEN 'C' THEN 'Ceded' WHEN 'A' THEN 'Assumed' END COLLATE DATABASE_DEFAULT
	,reg_date = mdo.reg_dt
	,Claim_NBR = 'N/A' COLLATE DATABASE_DEFAULT
	,TIRS_CLM_CD = 'N/A' COLLATE DATABASE_DEFAULT
	,CatCode = '' COLLATE DATABASE_DEFAULT
	,CAT_KEY = '' COLLATE DATABASE_DEFAULT
	,solvency_II_regulatory_key = s2re.solvency_II_regulatory_key
	,CLAIMLOSSDATE = NULL
	,AdjustmentType = 'N/A' COLLATE DATABASE_DEFAULT
	,bill_co_br_key = NULL
	,Summable_LOSS_PAID = 0
	,SUMMABLE_LOSS_PAID_USD = 0
	,SUMMABLE_LOSS_EXP_PAID = 0
	,SUMMABLE_LOSS_EXP_PAID_USD = 0
	,SUMMABLE_LAE = 0
	,SUMMABLE_LAE_USD = 0
	,SUMMABLE_CASH_LOSS_ADV_AMT = 0
	,SUMMABLE_CASH_LOSS_ADV_AMT_USD = 0
	,SUMMABLE_CASH_LOSS_REFUND = 0
	,SUMMABLE_CASH_LOSS_REFUND_USD = 0
	,SUMMABLE_funds_released_losses = 0
	,SUMMABLE_funds_released_losses_USD = 0
	,SUMMABLE_reinstatement_premium = 0
	,SUMMABLE_reinstatement_premium_USD = 0
	,SUMMABLE_OS_LOSS = 0
	,SUMMABLE_OS_LOSS_EXP = 0
	,SUMMABLE_OS_LOSS_USD = 0
	,SUMMABLE_OS_LOSS_EXP_USD = 0
	,Summable_Ceded_LOSS_PAID = 0
	,SUMMABLE_Ceded_LOSS_PAID_USD = 0
	,SUMMABLE_Ceded_LOSS_EXP_PAID = 0
	,SUMMABLE_Ceded_LOSS_EXP_PAID_USD = 0
	,SUMMABLE_Ceded_LAE = 0
	,SUMMABLE_Ceded_LAE_USD = 0
	,SUMMABLE_Ceded_CASH_LOSS_ADV_AMT = 0
	,SUMMABLE_Ceded_CASH_LOSS_ADV_AMT_USD = 0
	,SUMMABLE_Ceded_CASH_LOSS_REFUND = 0
	,SUMMABLE_Ceded_CASH_LOSS_REFUND_USD = 0
	,SUMMABLE_Ceded_funds_released_losses = 0
	,SUMMABLE_Ceded_funds_released_losses_USD = 0
	,SUMMABLE_Ceded_reinstatement_premium = 0
	,SUMMABLE_Ceded_reinstatement_premium_USD = 0
	,SUMMABLE_Ceded_OS_LOSS = 0
	,SUMMABLE_Ceded_OS_LOSS_EXP = 0
	,SUMMABLE_Ceded_OS_LOSS_USD = 0
	,SUMMABLE_Ceded_OS_LOSS_EXP_USD = 0

	,FIRVIBNRBeg = SUM(CASE mdo.assumed_ceded_flg WHEN 'A' THEN mdo.rpt_ibnr_beg ELSE 0.0 END)
	,CededFIRVIBNRBeg = SUM(CASE mdo.assumed_ceded_flg WHEN 'C' THEN mdo.rpt_ibnr_beg ELSE 0.0 END)
	,FIRVIBNREnd = SUM(CASE mdo.assumed_ceded_flg WHEN 'A' THEN mdo.rpt_ibnr_end ELSE 0.0 END)
	,CededFIRVIBNREnd = SUM(CASE mdo.assumed_ceded_flg WHEN 'C' THEN mdo.rpt_ibnr_end ELSE 0.0 END)
	,FIRVIBNRBegUSD = SUM(CASE mdo.assumed_ceded_flg WHEN 'A' THEN ROUND(mdo.rpt_ibnr_beg * xcc.xch_rt, 2) ELSE 0.0 END)
	,CededFIRVIBNRBegUSD = SUM(CASE mdo.assumed_ceded_flg WHEN 'C' THEN ROUND(mdo.rpt_ibnr_beg * xcc.xch_rt, 2) ELSE 0.0 END)
	,FIRVIBNREndUSD = SUM(CASE mdo.assumed_ceded_flg WHEN 'A' THEN ROUND(mdo.rpt_ibnr_end * xcc.xch_rt, 2) ELSE 0.0 END)
	,CededFIRVIBNREndUSD = SUM(CASE mdo.assumed_ceded_flg WHEN 'C' THEN ROUND(mdo.rpt_ibnr_end * xcc.xch_rt, 2) ELSE 0.0 END)
	
		FROM SRC_TIRS_DB.dbo.m_detl_oc mdo
		INNER JOIN SRC_TIRS_DB.dbo.trty_master tm
			ON tm.trty_key = mdo.trty_key
		INNER JOIN #ContractFilter cf
			ON cf.Contract_NBR = CONCAT(LEFT(tm.trty_no, 5), tm.und_yr) COLLATE DATABASE_DEFAULT
		LEFT JOIN SRC_TIRS_DB.dbo.trty_master ctm
			ON ctm.trty_key = mdo.ceded_trty_key
		INNER JOIN SRC_TIRS_DB.dbo.xrf_rpt_ofc xro
			ON xro.rpt_ofc_cd = tm.rpt_ofc_cd
		INNER JOIN SRC_TIRS_DB.dbo.xrf_lob_cds lob
			ON lob.lob_cd = mdo.pr_cls_cd
		INNER JOIN SRC_TIRS_DB.dbo.xrf_curr_names xcn
			ON xcn.curr_cd = mdo.curr_cd
		LEFT JOIN SRC_TIRS_DB.dbo.xrf_curr_cds xcc
			ON xcc.curr_cd = xcn.curr_cd
			AND xcc.xch_rt_dt = mdo.reg_dt
		INNER JOIN SRC_TIRS_DB.dbo.xrf_annl_stmt_line xasl
			ON xasl.annl_stmt_key = lob.annl_stmt_key
		INNER JOIN SRC_TIRS_DB.dbo.xrf_sub_dept_cds xsdc
			ON xsdc.sub_dept_key = tm.sub_dept_key
		INNER JOIN EDW_STAGING.dbo.TIRS_ASLOBCodeMapping tacn
			ON tacn.pro_xol_flg = tm.pro_xol_flg COLLATE DATABASE_DEFAULT
			AND tacn.annl_stmt_ln = xasl.annl_stmt_ln COLLATE DATABASE_DEFAULT
		LEFT JOIN EDW_PREPROD.dbo.solvency_II_regulatory_etl s2re
			ON s2re.source = 'TIRS'
			AND s2re.assumed_or_direct = 'Assumed'
			AND COALESCE(s2re.branch_name, '') COLLATE DATABASE_DEFAULT = COALESCE(xro.rpt_ofc_nm, '')
			AND COALESCE(s2re.product_group_name, '') COLLATE DATABASE_DEFAULT = COALESCE(xsdc.division_nm, '')
			AND COALESCE(s2re.product_department_name, '') COLLATE DATABASE_DEFAULT = COALESCE(xsdc.dept_nm, '')
			AND COALESCE(s2re.sub_product, '') COLLATE DATABASE_DEFAULT = COALESCE(xsdc.sub_dept_nm, '')
			AND COALESCE(s2re.lob_name, '') COLLATE DATABASE_DEFAULT = COALESCE(lob.desc_txt, '')
			AND COALESCE(s2re.prorata_or_xol, '') COLLATE DATABASE_DEFAULT = COALESCE(CASE WHEN tm.pro_xol_flg = 'X' THEN 'XOL' ELSE 'Pro Rata' END, '')  
			AND COALESCE(s2re.treaty_or_fav, '') COLLATE DATABASE_DEFAULT = COALESCE(CASE WHEN tm.trty_or_fac_flg = 'F' THEN 'FAC' ELSE 'Treaty' END, '')
			AND COALESCE(s2re.property_or_casualty, '') COLLATE DATABASE_DEFAULT = COALESCE(CASE WHEN xsdc.division_nm LIKE '%property%' THEN 'PROPERTY' WHEN xsdc.division_nm like '%marine%' THEN 'PROPERTY' ELSE 'CASUALTY' END, '')
			AND COALESCE(s2re.is_lloyds, '') COLLATE DATABASE_DEFAULT = COALESCE(CASE WHEN xro.rpt_ofc_nm LIKE '%lloyd%' THEN 'Lloyds' ELSE 'Non-Lloyds' END, '')
			AND COALESCE(s2re.transaction_ASLOB_code, '') COLLATE DATABASE_DEFAULT = COALESCE(xasl.annl_stmt_ln, '')
			AND COALESCE(s2re.InceptionFrom, tm.inception_dt, '1 Jan 1900') <= COALESCE(tm.inception_dt, '1 Jan 1900')
			AND COALESCE(s2re.InceptionTo, tm.inception_dt, '1 Jan 1900') >= COALESCE(tm.inception_dt, '1 Jan 1900')
		WHERE xro.rpt_ofc_nm = 'FIRV'
		GROUP BY tm.trty_no
			,tm.und_yr
			,CONCAT(LEFT(ctm.trty_no, 5), ctm.und_yr)
			,CONCAT(LEFT(tm.trty_no, 5), tm.und_yr)
			,xcn.curr_iso_cd
			,mdo.curr_cd
			,xcn.curr_nm
			,lob.desc_txt
			,tm.und_yr
			,tacn.aslob
			,CASE mdo.assumed_ceded_flg WHEN 'C' THEN 'Ceded' WHEN 'A' THEN 'Assumed' END
			,mdo.reg_dt
			,s2re.solvency_II_regulatory_key
		HAVING NOT (SUM(CASE mdo.assumed_ceded_flg WHEN 'A' THEN mdo.rpt_ibnr_beg ELSE 0.0 END) = 0
				AND SUM(CASE mdo.assumed_ceded_flg WHEN 'C' THEN mdo.rpt_ibnr_beg ELSE 0.0 END) = 0
				AND SUM(CASE mdo.assumed_ceded_flg WHEN 'A' THEN mdo.rpt_ibnr_end ELSE 0.0 END) = 0
				AND SUM(CASE mdo.assumed_ceded_flg WHEN 'C' THEN mdo.rpt_ibnr_end ELSE 0.0 END) = 0
				)
				)

			,TIRS_ACCOUNTING_PERIOD_T2_Code AS (
				SELECT contract_NBR = H.contract_NBR
					,ActuarialLob = COALESCE(AME.ActuarialLob, am.ActuarialLob)
					,RPT_OFF_NAME = H.RPT_OFF_NAME
					,InsurerCode = TIM.InsurerCode
					,lob_name = H.lob_name
					,T2_code = T2_code
					,T7_CODE = H.T7_CODE
					,T8_CODE = T8_CODE
					,T9_CODE = T9_CODE
					,CLMS_PROCSS_CLM_DEPT = CLMS_PROCSS_CLM_DEPT
					,ICP_CEDED_FLG = ICP_CEDED_FLG
					--,Reg_Date = P.AccountingPeriodDate
					,MBU = MBU
					,L01 = L01
					,L02 = L02
					,L03 = L03
					,L06 = L06
					,L07 = L07
					,L10 = L10
					,GD1 = GD1
					,RPTCURR1_CD = RPTCURR1_CD
					,RPTCURR2_CD = RPTCURR2_CD
					,START_DATE = tcr.START_DATE
				--FROM #AccountingPeriod p
				FROM #Parameters prm
				INNER JOIN #TCodeRevisionExASLOB tcr
					ON tcr.START_DATE < prm.CurrentOffsetAccountingEndDate
				INNER JOIN edw_preprod.dbo.T_Code_history h
					--ON p.OffSetAccountingEndDate > h.START_DATE
					--	AND p.OffSetAccountingEndDate < h.end_date
					ON h.ID = tcr.ID
					AND h.END_DATE > prm.CurrentOffsetAccountingEndDate
				INNER JOIN #ContractFilter cf
					ON cf.Contract_NBR = h.Contract_NBR COLLATE DATABASE_DEFAULT
				LEFT JOIN edw_staging.dbo.TIRS_InsurerCodeMapping TIM
					ON H.RPT_OFF_NAME = TIM.rpt_ofc_nm
				LEFT JOIN EDW_Staging.dbo.TIRS_ActuarialLobMapping AM
					ON AM.rpt_ofc_nm = H.RPT_OFF_NAME
					AND AM.division_nm = H.DIV_NAME
					AND AM.dept_nm = H.DEPT_NAME
					AND AM.sub_dept_nm = H.SUB_DEPT_NAME
					AND am.UNDERWRITING_YEAR = RIGHT(RTRIM(h.Contract_NBR), 4) COLLATE DATABASE_DEFAULT
				LEFT JOIN EDW_Staging.dbo.TIRS_ActuarialLobMapping_Exceptions AME
					ON AME.CONTRACT_NBR = H.Contract_NBR
				--WHERE P.AccountingPeriodDate < DATEADD(MONTH, 1, GETDATE())
			)
		INSERT INTO #ClaimLoadWide
			(TREATY_NBR
			,UNDERWRITING_YEAR
			,Ceded_CONTRACT_NBR
			,CONTRACT_NBR
			,SourceSystemKey
			,TransactionTypeCode
			,TransactionTypeCategory
			,DueDate
			,acct_from_dt
			,acct_to_dt  
			,doc_key
			,ORIGCURR_CD
			,TIRS_ORIG_CURR_CD
			,SETTL_CURR_CD
			,TIRS_ORIG_CURR_NAME
			,lob_name
			,AccidentYear
			,aslob
			,TIRS_UW_ASSM_CEDED_NAME
			,reg_date
			,Claim_NBR
			,TIRS_CLM_CD
			,CatCode
			,CAT_KEY
			,solvency_II_regulatory_key
			,CLAIMLOSSDATE
			,bill_co_br_key
			,Summable_LOSS_PAID
			,SUMMABLE_LOSS_PAID_USD
			,SUMMABLE_LOSS_EXP_PAID
			,SUMMABLE_LOSS_EXP_PAID_USD
			,SUMMABLE_LAE
			,SUMMABLE_LAE_USD
			,SUMMABLE_CASH_LOSS_ADV_AMT
			,SUMMABLE_CASH_LOSS_ADV_AMT_USD
			,SUMMABLE_CASH_LOSS_REFUND
			,SUMMABLE_CASH_LOSS_REFUND_USD
			,SUMMABLE_funds_released_losses
			,SUMMABLE_funds_released_losses_USD
			,SUMMABLE_reinstatement_premium
			,SUMMABLE_reinstatement_premium_USD
			,SUMMABLE_OS_LOSS
			,SUMMABLE_OS_LOSS_EXP
			,SUMMABLE_OS_LOSS_USD
			,SUMMABLE_OS_LOSS_EXP_USD
			,Summable_Ceded_LOSS_PAID
			,SUMMABLE_Ceded_LOSS_PAID_USD
			,SUMMABLE_Ceded_LOSS_EXP_PAID
			,SUMMABLE_Ceded_LOSS_EXP_PAID_USD
			,SUMMABLE_Ceded_LAE
			,SUMMABLE_Ceded_LAE_USD
			,SUMMABLE_Ceded_CASH_LOSS_ADV_AMT
			,SUMMABLE_Ceded_CASH_LOSS_ADV_AMT_USD
			,SUMMABLE_Ceded_CASH_LOSS_REFUND
			,SUMMABLE_Ceded_CASH_LOSS_REFUND_USD
			,SUMMABLE_Ceded_funds_released_losses
			,SUMMABLE_Ceded_funds_released_losses_USD
			,SUMMABLE_Ceded_OS_LOSS
			,SUMMABLE_Ceded_OS_LOSS_EXP
			,SUMMABLE_Ceded_OS_LOSS_USD
			,SUMMABLE_Ceded_OS_LOSS_EXP_USD
			,SUMMABLE_Ceded_reinstatement_premium
			,SUMMABLE_Ceded_reinstatement_premium_USD
			
			,FIRVIBNRBeg
			,CededFIRVIBNRBeg
			,FIRVIBNREnd
			,CededFIRVIBNREnd
			,FIRVIBNRBegUSD
			,CededFIRVIBNRBegUSD
			,FIRVIBNREndUSD
			,CededFIRVIBNREndUSD
						
			,Source
			,adjustmenttype
			,financial_lob
			,T7_CODE
			,T8_CODE
			,T9_CODE
			,InsurerCode
			,CLMS_PROCSS_CLM_DEPT
			,ICP_CEDED_FLG
			,RPT_OFF_NAME
			,ActuarialLob
			,MBU
			,L01
			,L02
			,L03
			,L04
			,L06
			,L07
			,L10
			,GD1
			,RPTCURR1_CD
			,RPTCURR2_CD
			,RPTCURR1
			,RPTCURR2
			,SETTL_RPTCURR1
			,SETTL_RPTCURR2
			,Summable_SETTL_LOSS_PAID
			,Summable_SETTL_LOSS_PAID_USD
			,Summable_SETTL_LAE
			,Summable_SETTL_LAE_USD
			,AdjustedTCodeL04
			)
		SELECT DISTINCT TREATY_NBR = C.TREATY_NBR
			,UNDERWRITING_YEAR = C.UNDERWRITING_YEAR
			,Ceded_CONTRACT_NBR = C.Ceded_CONTRACT_NBR
			,CONTRACT_NBR = C.CONTRACT_NBR
			,SourceSystemKey = C.SourceSystemKey
			,TransactionTypeCode = c.TransactionTypeCode
			,TransactionTypeCategory = c.TransactionTypeCategory
			,DueDate = c.DueDate
			,acct_from_dt = c.acct_from_dt
			,acct_to_dt = c.acct_to_dt
			,doc_key = c.doc_key 
			,ORIGCURR_CD = C.ORIGCURR_CD
			,TIRS_ORIG_CURR_CD = C.TIRS_ORIG_CURR_CD
			,SETTL_CURR_CD = CAST('' AS VARCHAR(10)) COLLATE Latin1_General_CI_AI
			,TIRS_ORIG_CURR_NAME = C.TIRS_ORIG_CURR_NAME
			,lob_name = C.lob_name
			,AccidentYear = IIF(C.adjustmenttype IN ('minus informational'), C.AccidentYear, ISNULL(ld.AccidentYear, C.AccidentYear))
			,aslob = C.aslob
			,TIRS_UW_ASSM_CEDED_NAME = C.TIRS_UW_ASSM_CEDED_NAME
			,reg_date = C.reg_date
			,Claim_NBR = C.Claim_NBR
			,TIRS_CLM_CD = C.TIRS_CLM_CD
			,CatCode = IIF(C.adjustmenttype IN ('minus informational'), C.CatCode, ISNULL(ld.CatCode, ''))
			,CAT_KEY = IIF(C.adjustmenttype IN ('minus informational'), CAST(C.CAT_KEY AS VARCHAR(20)), ISNULL(ld.CAT_KEY, ''))
			,solvency_II_regulatory_key = C.solvency_II_regulatory_key
			,CLAIMLOSSDATE = C.CLAIMLOSSDATE
			,bill_co_br_key = C.bill_co_br_key
			,Summable_LOSS_PAID = C.Summable_LOSS_PAID
			,SUMMABLE_LOSS_PAID_USD = C.SUMMABLE_LOSS_PAID_USD
			,SUMMABLE_LOSS_EXP_PAID = C.SUMMABLE_LOSS_EXP_PAID
			,SUMMABLE_LOSS_EXP_PAID_USD = C.SUMMABLE_LOSS_EXP_PAID_USD
			,SUMMABLE_LAE = C.SUMMABLE_LAE
			,SUMMABLE_LAE_USD = C.SUMMABLE_LAE_USD
			,SUMMABLE_CASH_LOSS_ADV_AMT = C.SUMMABLE_CASH_LOSS_ADV_AMT
			,SUMMABLE_CASH_LOSS_ADV_AMT_USD = C.SUMMABLE_CASH_LOSS_ADV_AMT_USD
			,SUMMABLE_CASH_LOSS_REFUND = C.SUMMABLE_CASH_LOSS_REFUND
			,SUMMABLE_CASH_LOSS_REFUND_USD = C.SUMMABLE_CASH_LOSS_REFUND_USD
			,SUMMABLE_funds_released_losses = C.SUMMABLE_funds_released_losses
			,SUMMABLE_funds_released_losses_USD = C.SUMMABLE_funds_released_losses_USD
			,SUMMABLE_reinstatement_premium = C.SUMMABLE_reinstatement_premium
			,SUMMABLE_reinstatement_premium_USD = C.SUMMABLE_reinstatement_premium_USD
			,SUMMABLE_OS_LOSS = C.SUMMABLE_OS_LOSS
			,SUMMABLE_OS_LOSS_EXP = C.SUMMABLE_OS_LOSS_EXP
			,SUMMABLE_OS_LOSS_USD = C.SUMMABLE_OS_LOSS_USD
			,SUMMABLE_OS_LOSS_EXP_USD = C.SUMMABLE_OS_LOSS_EXP_USD
			,Summable_Ceded_LOSS_PAID = C.Summable_Ceded_LOSS_PAID
			,SUMMABLE_Ceded_LOSS_PAID_USD = C.SUMMABLE_Ceded_LOSS_PAID_USD
			,SUMMABLE_Ceded_LOSS_EXP_PAID = C.SUMMABLE_Ceded_LOSS_EXP_PAID
			,SUMMABLE_Ceded_LOSS_EXP_PAID_USD = C.SUMMABLE_Ceded_LOSS_EXP_PAID_USD
			,SUMMABLE_Ceded_LAE = C.SUMMABLE_Ceded_LAE
			,SUMMABLE_Ceded_LAE_USD = C.SUMMABLE_Ceded_LAE_USD
			,SUMMABLE_Ceded_CASH_LOSS_ADV_AMT = C.SUMMABLE_Ceded_CASH_LOSS_ADV_AMT
			,SUMMABLE_Ceded_CASH_LOSS_ADV_AMT_USD = C.SUMMABLE_Ceded_CASH_LOSS_ADV_AMT_USD
			,SUMMABLE_Ceded_CASH_LOSS_REFUND = C.SUMMABLE_Ceded_CASH_LOSS_REFUND
			,SUMMABLE_Ceded_CASH_LOSS_REFUND_USD = C.SUMMABLE_Ceded_CASH_LOSS_REFUND_USD
			,SUMMABLE_Ceded_funds_released_losses = C.SUMMABLE_Ceded_funds_released_losses
			,SUMMABLE_Ceded_funds_released_losses_USD = C.SUMMABLE_Ceded_funds_released_losses_USD
			,SUMMABLE_Ceded_OS_LOSS = C.SUMMABLE_Ceded_OS_LOSS
			,SUMMABLE_Ceded_OS_LOSS_EXP = C.SUMMABLE_Ceded_OS_LOSS_EXP
			,SUMMABLE_Ceded_OS_LOSS_USD = C.SUMMABLE_Ceded_OS_LOSS_USD
			,SUMMABLE_Ceded_OS_LOSS_EXP_USD = C.SUMMABLE_Ceded_OS_LOSS_EXP_USD
			,SUMMABLE_Ceded_reinstatement_premium = C.SUMMABLE_Ceded_reinstatement_premium
			,SUMMABLE_Ceded_reinstatement_premium_USD = c.SUMMABLE_Ceded_reinstatement_premium_USD
			,FIRVIBNRBeg
			,CededFIRVIBNRBeg
			,FIRVIBNREnd
			,CededFIRVIBNREnd
			,FIRVIBNRBegUSD
			,CededFIRVIBNRBegUSD
			,FIRVIBNREndUSD
			,CededFIRVIBNREndUSD

			,Source = CAST('TIRS' AS VARCHAR(20))
			,adjustmenttype = C.adjustmenttype
			,financial_lob = H.T2_code
			,T7_CODE = H.T7_CODE
			,T8_CODE = H.T8_CODE
			,T9_CODE = H.T9_CODE
			,InsurerCode = H.InsurerCode
			,CLMS_PROCSS_CLM_DEPT = H.CLMS_PROCSS_CLM_DEPT
			,ICP_CEDED_FLG = H.ICP_CEDED_FLG
			,RPT_OFF_NAME = H.RPT_OFF_NAME
			,ActuarialLob = H.ActuarialLob
			,MBU = H.MBU
			,L01 = H.L01
			,L02 = H.L02
			,L03 = H.L03
			,L04 = CAST(IIF(C.adjustmenttype IN ('minus informational'), CAST(C.AccidentYear AS VARCHAR(4)), ISNULL(ld.L04, CAST(C.AccidentYear AS VARCHAR(4)))) AS VARCHAR(20))
			,L06 = H.L06
			,L07 = H.L07
			,L10 = H.L10
			,GD1 = H.GD1
			,RPTCURR1_CD = H.RPTCURR1_CD
			,RPTCURR2_CD = H.RPTCURR2_CD
			,RPTCURR1 = CAST(IIF(R.K1CURRENCY_CODE = 'USD', 1, ROrig.ExchangeRate) * (1 / NULLIF(RT1.ExchangeRate, 0)) AS FLOAT)
			,RPTCURR2 = CAST(IIF(R.K1CURRENCY_CODE = 'USD', 1, ROrig.ExchangeRate) * (1 / NULLIF(RT2.ExchangeRate, 0)) AS FLOAT)
			,SETTL_RPTCURR1 = CAST(NULL AS FLOAT)
			,SETTL_RPTCURR2 = CAST(NULL AS FLOAT)
			,Summable_SETTL_LOSS_PAID = CAST(NULL AS MONEY)
			,Summable_SETTL_LOSS_PAID_USD = CAST(NULL AS MONEY)
			,Summable_SETTL_LAE = CAST(NULL AS MONEY)
			,Summable_SETTL_LAE_USD = CAST(NULL AS MONEY)
			,AdjustedTCodeL04 = CASE WHEN ap.OffSetAccountingEndDate > h.START_DATE AND ap.OffSetAccountingEndDate > COALESCE(ld.START_DATE, '1 Jan 1900') THEN 0 ELSE 1 END
		FROM CLM_LOAD C
		INNER JOIN #AccountingPeriod ap
			ON ap.AccountingPeriodDate = c.reg_date
		LEFT JOIN TIRS_ACCOUNTING_PERIOD_T2_Code H
			ON C.CONTRACT_NBR = H.contract_NBR
				--AND C.reg_date = H.Reg_Date
				AND C.lob_name = H.lob_name
		LEFT JOIN #L04 ld
			ON ld.TIRS_CLM_CD = C.TIRS_CLM_CD
				AND c.Claim_NBR != 'N/A'
		LEFT JOIN EDW_PREPROD.dbo.EDW_TIRS_ROE r
			ON C.TIRS_ORIG_CURR_CD = R.TIRS_CURRENCY_CODE
				AND R.K1PERIOD_OF_TIME = C.reg_date
		LEFT JOIN #FX rorig
			ON rorig.ISOCode = r.K1CURRENCY_CODE
			AND rorig.JoinMonth = c.reg_date
		LEFT JOIN #FX rt1
			ON rt1.ISOCode = h.RPTCURR1_CD
			AND rt1.JoinMonth = c.reg_date
		LEFT JOIN #FX rt2
			ON rt2.ISOCode = h.RPTCURR2_CD
			AND rt2.JoinMonth = c.reg_date
		UNION ALL
		SELECT TREATY_NBR = t.TREATY_NBR
			,UNDERWRITING_YEAR = t.UNDERWRITING_YEAR
			,Ceded_CONTRACT_NBR = t.Ceded_CONTRACT_NBR
			,CONTRACT_NBR = t.CONTRACT_NBR
			,SourceSystemKey = NULL
			,TransactionTypeCode = 'Topside'
			,TransactionTypeCategory = 'Topside'
			,DueDate = NULL
			,acct_from_dt = NULL
			,acct_to_dt = NULL
			,doc_key = NULL
			,ORIGCURR_CD = xcn.curr_iso_cd COLLATE DATABASE_DEFAULT
			,TIRS_ORIG_CURR_CD = t.TIRS_ORIG_CURR_CD
			,SETTL_CURR_CD = t.SETTL_CURR_CD COLLATE DATABASE_DEFAULT
			,TIRS_ORIG_CURR_NAME = t.TIRS_ORIG_CURR_NAME
			,lob_name = t.lob_name
			,AccidentYear = t.AccidentYear
			,aslob = t.aslob
			,TIRS_UW_ASSM_CEDED_NAME = t.TIRS_UW_ASSM_CEDED_NAME
			,reg_date = t.reg_date
			,Claim_NBR = t.Claim_NBR
			,TIRS_CLM_CD = t.TIRS_CLM_CD
			,CatCode = t.CatCode
			,CAT_KEY = t.CAT_KEY
			,solvency_II_regulatory_key = t.solvency_II_regulatory_key
			,CLAIMLOSSDATE = NULL
			,bill_co_br_key = NULL
			,Summable_LOSS_PAID = t.Summable_LOSS_PAID
			,SUMMABLE_LOSS_PAID_USD = t.SUMMABLE_LOSS_PAID_USD
			,SUMMABLE_LOSS_EXP_PAID = t.SUMMABLE_LOSS_EXP_PAID
			,SUMMABLE_LOSS_EXP_PAID_USD = t.SUMMABLE_LOSS_EXP_PAID_USD
			,SUMMABLE_LAE = t.SUMMABLE_LAE
			,SUMMABLE_LAE_USD = t.SUMMABLE_LAE_USD
			,SUMMABLE_CASH_LOSS_ADV_AMT = t.SUMMABLE_CASH_LOSS_ADV_AMT
			,SUMMABLE_CASH_LOSS_ADV_AMT_USD = t.SUMMABLE_CASH_LOSS_ADV_AMT_USD
			,SUMMABLE_CASH_LOSS_REFUND = t.SUMMABLE_CASH_LOSS_REFUND
			,SUMMABLE_CASH_LOSS_REFUND_USD = t.SUMMABLE_CASH_LOSS_REFUND_USD
			,SUMMABLE_funds_released_losses = t.SUMMABLE_funds_released_losses
			,SUMMABLE_funds_released_losses_USD = t.SUMMABLE_funds_released_losses_USD
			,SUMMABLE_reinstatement_premium = t.SUMMABLE_reinstatement_premium
			,SUMMABLE_reinstatement_premium_USD = t.SUMMABLE_reinstatement_premium_USD
			,SUMMABLE_OS_LOSS = t.SUMMABLE_OS_LOSS
			,SUMMABLE_OS_LOSS_EXP = t.SUMMABLE_OS_LOSS_EXP
			,SUMMABLE_OS_LOSS_USD = t.SUMMABLE_OS_LOSS_USD
			,SUMMABLE_OS_LOSS_EXP_USD = t.SUMMABLE_OS_LOSS_EXP_USD
			,Summable_Ceded_LOSS_PAID = t.Summable_Ceded_LOSS_PAID
			,SUMMABLE_Ceded_LOSS_PAID_USD = t.SUMMABLE_Ceded_LOSS_PAID_USD
			,SUMMABLE_Ceded_LOSS_EXP_PAID = t.SUMMABLE_Ceded_LOSS_EXP_PAID
			,SUMMABLE_Ceded_LOSS_EXP_PAID_USD = t.SUMMABLE_Ceded_LOSS_EXP_PAID_USD
			,SUMMABLE_Ceded_LAE = t.SUMMABLE_Ceded_LAE
			,SUMMABLE_Ceded_LAE_USD = t.SUMMABLE_Ceded_LAE_USD
			,SUMMABLE_Ceded_CASH_LOSS_ADV_AMT = t.SUMMABLE_Ceded_CASH_LOSS_ADV_AMT
			,SUMMABLE_Ceded_CASH_LOSS_ADV_AMT_USD = t.SUMMABLE_Ceded_CASH_LOSS_ADV_AMT_USD
			,SUMMABLE_Ceded_CASH_LOSS_REFUND = t.SUMMABLE_Ceded_CASH_LOSS_REFUND
			,SUMMABLE_Ceded_CASH_LOSS_REFUND_USD = t.SUMMABLE_Ceded_CASH_LOSS_REFUND_USD
			,SUMMABLE_Ceded_funds_released_losses = t.SUMMABLE_Ceded_funds_released_losses
			,SUMMABLE_Ceded_funds_released_losses_USD = t.SUMMABLE_Ceded_funds_released_losses_USD
			,SUMMABLE_Ceded_OS_LOSS = t.SUMMABLE_Ceded_OS_LOSS
			,SUMMABLE_Ceded_OS_LOSS_EXP = t.SUMMABLE_Ceded_OS_LOSS_EXP
			,SUMMABLE_Ceded_OS_LOSS_USD = t.SUMMABLE_Ceded_OS_LOSS_USD
			,SUMMABLE_Ceded_OS_LOSS_EXP_USD = t.SUMMABLE_Ceded_OS_LOSS_EXP_USD
			,SUMMABLE_Ceded_reinstatement_premium = t.SUMMABLE_Ceded_reinstatement_premium
			,SUMMABLE_Ceded_reinstatement_premium_USD = t.SUMMABLE_Ceded_reinstatement_premium_USD

			,0 as FIRVIBNRBeg
			,0 as CededFIRVIBNRBeg
			,0 as FIRVIBNREnd
			,0 as CededFIRVIBNREnd
			,0 as FIRVIBNRBegUSD
			,0 as CededFIRVIBNRBegUSD
			,0 as FIRVIBNREndUSD
			,0 as CededFIRVIBNREndUSD
			,Source = t.Source
			,adjustmenttype = t.AdjustmentType
			,financial_lob = t.FINANCIAL_LOB
			,T7_CODE = t.T7_CODE
			,T8_CODE = t.T8_CODE
			,T9_CODE = t.T9_CODE
			,InsurerCode = t.InsurerCode
			,CLMS_PROCSS_CLM_DEPT = t.CLMS_PROCSS_CLM_DEPT
			,ICP_CEDED_FLG = t.ICP_CEDED_FLG
			,RPT_OFF_NAME = t.RPT_OFC_NM
			,ActuarialLob = t.ActuarialLob
			,MBU = t.MBU
			,L01 = t.L01
			,L02 = t.L02
			,L03 = t.L03
			,L04 = t.L04
			,L06 = t.L06
			,L07 = t.L07
			,L10 = t.L10
			,GD1 = t.GD1
			,RPTCURR1_CD = t.RPTCURR1_CD
			,RPTCURR2_CD = t.RPTCURR2_CD
			,RPTCURR1 = t.RPTCURR1
			,RPTCURR2 = t.RPTCURR2
			,SETTL_RPTCURR1 = t.SETTL_RPTCURR1
			,SETTL_RPTCURR2 = t.SETTL_RPTCURR2
			,Summable_SETTL_LOSS_PAID = t.Summable_SETTL_LOSS_PAID
			,Summable_SETTL_LOSS_PAID_USD = CASE WHEN NULLIF(t.Summable_SETTL_LOSS_PAID, 0) IS NULL THEN 0 ELSE t.Summable_SETTL_LOSS_PAID * der_su.ExchangeRate END
			,Summable_SETTL_LAE = t.Summable_SETTL_LAE
			,Summable_SETTL_LAE_USD = CASE WHEN NULLIF(t.Summable_SETTL_LAE, 0) IS NULL THEN 0 ELSE t.Summable_SETTL_LAE * der_su.ExchangeRate END
			,AdjustedTCodeL04 = 0
		FROM EDW_PREPROD.dbo.RS_TIRS_CLAIMS_TOPSIDE t
		INNER JOIN #ContractFilter cf
			ON cf.Contract_NBR = t.CONTRACT_NBR COLLATE DATABASE_DEFAULT
		LEFT JOIN SRC_TIRS_DB.dbo.xrf_curr_names xcn
			ON xcn.curr_cd = t.TIRS_ORIG_CURR_CD COLLATE DATABASE_DEFAULT
		LEFT JOIN EDW_PREPROD.assumed.DimExchangeRate der_su
			ON der_su.EndDate = '31 Dec 9999'
			AND der_su.FromCurrency = t.SETTL_CURR_CD COLLATE DATABASE_DEFAULT
			AND der_su.ToCurrency = 'USD'
			AND der_su.AccountingPeriodDate = t.reg_date

		INSERT INTO #Timings SELECT SYSDATETIME(), 'Created #ClaimLoadWide', @@ERROR

		INSERT INTO #ClaimLoadWide
			(TREATY_NBR
			,UNDERWRITING_YEAR
			,CONTRACT_NBR
			,SourceSystemKey
			,TransactionTypeCode
			,TransactionTypeCategory
			,DueDate
			,ORIGCURR_CD
			,TIRS_ORIG_CURR_CD
			,settl_curr_cd
			,TIRS_ORIG_CURR_NAME
			,lob_name
			,ActuarialLob
			,AccidentYear
			,aslob
			,TIRS_UW_ASSM_CEDED_NAME
			,ICP_CEDED_FLG
			,reg_date
			,Claim_NBR
			,TIRS_CLM_CD
			,CatCode
			,CAT_KEY
			,bill_co_br_key
			,SUMMABLE_LOSS_PAID_USD
			,SUMMABLE_LAE_USD
			,SUMMABLE_OS_LOSS_USD
			,SUMMABLE_LOSS_PAID
			,SUMMABLE_LAE
			,SUMMABLE_OS_LOSS
			,Source
			,AdjustmentType
			,financial_lob
			,t7_code
			,t8_code
			,t9_code
			,Insurercode
			,RPT_OFF_NAME
			,solvency_II_regulatory_key
			,MBU
			,L01
			,L02
			,L03
			,L04
			,L06
			,L07
			,L10
			,GD1
			,RPTCURR1_CD
			,RPTCURR2_CD
			,RPTCURR1
			,RPTCURR2
			,SETTL_RPTCURR1
			,SETTL_RPTCURR2
			,Summable_SETTL_LOSS_PAID
			,Summable_SETTL_LOSS_PAID_USD
			,Summable_SETTL_LAE
			,Summable_SETTL_LAE_USD
			,AdjustedTCodeL04
			)
		SELECT TREATY_NBR = stg.TREATY_NBR
			,UNDERWRITING_YEAR = stg.UNDERWRITING_YEAR
			,CONTRACT_NBR = stg.contract_NBR
			,SourceSystemKey = stg.SourceSystemKey
			,TransactionTypeCode = stg.TransactionTypeCode
			,TransactionTypeCategory = stg.TransactionTypeCategory
			,DueDate = stg.DueDate
			,ORIGCURR_CD = stg.ORIGCURR_CD
			,TIRS_ORIG_CURR_CD = stg.TIRS_ORIG_CURR_CD
			,SETTL_CURR_CD = stg.SETTL_CURR_CD
			,TIRS_ORIG_CURR_NAME = stg.TIRS_ORIG_CURR_NAME
			,lob_name = stg.lob_name
			,ActuarialLob = stg.ActuarialLob
			,AccidentYear = stg.AccidentYear
			,aslob = stg.aslob
			,TIRS_UW_ASSM_CEDED_NAME = stg.TIRS_UW_ASSM_CEDED_NAME
			,ICP_CEDED_FLG = stg.ICP_CEDED_FLG
			,reg_date = stg.reg_date
			,Claim_NBR = stg.Claim_NBR
			,TIRS_CLM_CD = stg.TIRS_CLM_CD
			,CatCode = stg.CatCode
			,CAT_KEY = stg.CAT_KEY
			,bill_co_br_key =  stg.bill_co_br_key
			,SUMMABLE_LOSS_PAID_USD = stg.Summable_LOSS_PAID_USD
			,SUMMABLE_LAE_USD = stg.SUMMABLE_LAE_USD
			,SUMMABLE_OS_LOSS_USD = stg.SUMMABLE_OS_LOSS_USD
			,SUMMABLE_LOSS_PAID = stg.Summable_LOSS_PAID
			,SUMMABLE_LAE = stg.SUMMABLE_LAE
			,SUMMABLE_OS_LOSS = stg.SUMMABLE_OS_LOSS
			,Source = stg.Source
			,AdjustmentType = stg.adjustmenttype
			,financial_lob = stg.financial_lob
			,t7_code = stg.T7_Code
			,t8_code = stg.T8_Code
			,t9_code = stg.t9_code
			,Insurercode = stg.InsurerCode
			,RPT_OFF_NAME = stg.RPT_OFF_NAME
			,solvency_II_regulatory_key = stg.solvency_II_regulatory_key
			,MBU = stg.MBU
			,L01 = stg.L01
			,L02 = stg.L02
			,L03 = stg.L03
			,L04 = stg.L04
			,L06 = stg.L06
			,L07 = stg.L07
			,L10 = stg.L10
			,GD1 = stg.GD1
			,RPTCURR1_CD = stg.RPTCURR1_CD
			,RPTCURR2_CD = stg.RPTCURR2_CD
			,RPTCURR1 = stg.RPTCURR1
			,RPTCURR2 = stg.RPTCURR2
			,SETTL_RPTCURR1 = stg.SETTL_RPTCURR1
			,SETTL_RPTCURR2 = stg.SETTL_RPTCURR2
			,Summable_SETTL_LOSS_PAID = stg.Summable_SETTL_LOSS_PAID
			,Summable_SETTL_LOSS_PAID_USD = stg.Summable_SETTL_LOSS_PAID_USD
			,Summable_SETTL_LAE = stg.Summable_SETTL_LAE
			,Summable_SETTL_LAE_USD = stg.Summable_SETTL_LAE_USD
			,AdjustedTCodeL04 = 0
		FROM [EDW_Staging].[assumed].[OPENBOX_CLAIMS_staging] AS stg
		WHERE stg.EndDate = '9999-12-31'
		 AND EXISTS ( SELECT *
					  FROM #ContractFilter	AS cf
					  WHERE cf.CONTRACT_NBR = stg.CONTRACT_NBR COLLATE DATABASE_DEFAULT )
		

		INSERT INTO #Timings SELECT SYSDATETIME(), 'Added Openbox data to #ClaimLoadWide', @@ERROR

		UPDATE #ClaimLoadWide
		SET financial_lob = 'INRI'
			,L03 = 'RPR0102'
		WHERE CONTRACT_NBR = '151832013'
			AND reg_date < '3/1/2014'
			AND adjustmenttype != 'topside plus'
			AND (financial_lob != 'INRI'
			OR L03 != 'RPR0102')

		UPDATE c
		SET CatCode = ''
			,L04 = c.AccidentYear
		FROM #ClaimLoadWide c
		WHERE (NOT (c.ActuarialLob LIKE '%Property%'
			OR c.ActuarialLob LIKE '%Marine & Aviation%'
			OR c.ActuarialLob LIKE '%Specialty%'
			OR c.ActuarialLob LIKE '%A&H%'
			OR c.ActuarialLob LIKE 'IPC Re')
			OR c.Claim_NBR IN (SELECT Claim_NBR = tce.CLAIM_NBR FROM EDW_Staging.dbo.TIRS_Claim_Exceptions tce))
			AND (COALESCE(c.L04, '') != COALESCE(c.AccidentYear, '')
			OR COALESCE(c.CatCode, '') != '')

		UPDATE c
		SET AccidentYear = o.accidentyear
			,l04 = d.L4
		FROM #ClaimLoadWide c
		INNER JOIN EDW_PREPROD.dbo.RS_TIRS_AccidentYear_OverRide o
			ON c.CONTRACT_NBR = o.contract_NBR
		OUTER APPLY (
			SELECT TOP 1 *
			FROM DM_DataStandard.dbo.L4Mapping d
			WHERE 1 = 1
				AND ISNULL(NULLIF(CAST(d.AccidentYear AS VARCHAR(100)), '%'), ISNULL(o.AccidentYear COLLATE DATABASE_DEFAULT, '')) = ISNULL(o.AccidentYear COLLATE DATABASE_DEFAULT, '')
				AND ISNULL(NULLIF(CAST(d.CAT_KEY AS VARCHAR(100)), '%'), ISNULL(c.CAT_KEY COLLATE DATABASE_DEFAULT, '')) = ISNULL(c.CAT_KEY COLLATE DATABASE_DEFAULT, '')
				AND ISNULL(NULLIF(CAST(d.Source_System AS VARCHAR(100)), '%'), ISNULL(c.Source COLLATE DATABASE_DEFAULT, '')) = ISNULL(c.Source COLLATE DATABASE_DEFAULT, '')
			ORDER BY d.Priority_Key DESC
			) d
		WHERE o.AccidentYear != COALESCE(c.AccidentYear, '')
			OR COALESCE(c.L04, '') != d.L4

		UPDATE c
		SET AccidentYear = e.AccidentYear
			,L04 = e.AccidentYear
		FROM #ClaimLoadWide c
		INNER JOIN EDW_Staging.dbo.TIRS_AccidentYear_Exceptions e
			ON c.Claim_NBR = e.Claim_NBR
				AND COALESCE(c.AccidentYear, '') != e.AccidentYear

		INSERT INTO #Timings SELECT SYSDATETIME(), 'Apply ad-hoc adjustments', @@ERROR
		--------------------------------------------------------------------------------	
		-- Lookup DimContractID
		--------------------------------------------------------------------------------
		UPDATE clw
		SET DimContractID = COALESCE(d.DimContractID, prm.DimContractUncoded)
		FROM #ClaimLoadWide clw
		CROSS JOIN #Parameters prm
		LEFT JOIN EDW_PREPROD.assumed.DimContract d
			ON d.CONTRACT_NBR = clw.CONTRACT_NBR
			AND COALESCE(d.PLCY_SRC, clw.Source) = clw.Source
			AND prm.ProcessingDate BETWEEN d.StartDate AND d.EndDate

		INSERT INTO #Timings SELECT SYSDATETIME(), 'Looked up DimContractID', @@ERROR
		--------------------------------------------------------------------------------	
		-- Lookup Ceded_DimContractID
		--------------------------------------------------------------------------------
		UPDATE clw
		SET Ceded_DimContractID = CASE WHEN NULLIF(clw.Ceded_CONTRACT_NBR, '') IS NULL THEN prm.DimContractNA ELSE COALESCE(d.DimContractID, prm.DimContractUncoded) END
		FROM #ClaimLoadWide clw
		CROSS JOIN #Parameters prm
		LEFT JOIN EDW_PREPROD.assumed.DimContract d
			ON d.CONTRACT_NBR = clw.Ceded_CONTRACT_NBR
			AND COALESCE(d.PLCY_SRC, clw.Source) = clw.Source
			AND prm.ProcessingDate BETWEEN d.StartDate AND d.EndDate

		INSERT INTO #Timings SELECT SYSDATETIME(), 'Looked up Ceded_DimContractID', @@ERROR
		--------------------------------------------------------------------------------	
		-- Lookup DimClaimTransactionID
		--------------------------------------------------------------------------------
		UPDATE clw
		SET DimClaimTransactionID = CASE WHEN COALESCE(NULLIF(clw.TIRS_CLM_CD, ''), 'N/A') = 'N/A' THEN prm.DimClaimTransactionNA ELSE COALESCE(d.DimClaimTransactionID, prm.DimClaimTransactionUncoded) END
		FROM #ClaimLoadWide clw
		CROSS JOIN #Parameters prm
		LEFT JOIN EDW_PREPROD.assumed.DimClaimTransaction d
			ON d.Source = clw.Source
			AND d.ClaimTransactionCode = clw.TIRS_CLM_CD
			AND prm.ProcessingDate BETWEEN d.StartDate AND d.EndDate

		INSERT INTO #Timings SELECT SYSDATETIME(), 'Looked up DimClaimTransactionID', @@ERROR
		--------------------------------------------------------------------------------	
		-- Lookup DimTransactionTypeID
		--------------------------------------------------------------------------------
		UPDATE clw
		SET DimTransactionTypeID = CASE WHEN clw.TransactionTypeCode IS NULL THEN prm.DimTransactionTypeNA ELSE COALESCE(d.DimTransactionTypeID, prm.DimTransactionTypeUncoded) END
		FROM #ClaimLoadWide clw
		CROSS JOIN #Parameters prm
		LEFT JOIN EDW_PREPROD.assumed.DimTransactionType d
		ON d.TransactionTypeCode = clw.TransactionTypeCode
			AND d.Category = clw.TransactionTypeCategory
			AND (d.Source = clw.Source OR d.Source NOT IN ('TIRS','OPENBOX')  )
			AND prm.ProcessingDate BETWEEN d.StartDate AND d.EndDate

		INSERT INTO #Timings SELECT SYSDATETIME(), 'Looked up DimTransactionTypeID', @@ERROR
		--------------------------------------------------------------------------------	
		-- Lookup Intended_DimAccountingPeriodID
		--------------------------------------------------------------------------------
		UPDATE clw
		SET Intended_DimAccountingPeriodID = COALESCE(d.DimAccountingPeriodID, prm.DimAccountingPeriodUncoded)
		FROM #ClaimLoadWide clw
		CROSS JOIN #Parameters prm
		LEFT JOIN EDW_PREPROD.assumed.DimAccountingPeriod d
			ON d.AccountingPeriodDate = clw.reg_date
			AND prm.ProcessingDate BETWEEN d.StartDate AND d.EndDate

		INSERT INTO #Timings SELECT SYSDATETIME(), 'Looked up Intended_DimAccountingPeriodID', @@ERROR
		--------------------------------------------------------------------------------	
		-- Lookup DimAccidentYearID
		--------------------------------------------------------------------------------
		UPDATE clw
		SET DimAccidentYearID = COALESCE(d.DimAccidentYearID, prm.DimAccidentYearUncoded)
		FROM #ClaimLoadWide clw
		CROSS JOIN #Parameters prm
		LEFT JOIN EDW_PREPROD.assumed.DimAccidentYear d
			ON d.AccidentYear = clw.AccidentYear
			AND COALESCE(d.CAT_KEY, '%^&') = COALESCE(NULLIF(clw.CAT_KEY, ''), '%^&')
			AND COALESCE(d.CatCode, '%^&') = COALESCE(NULLIF(clw.CatCode, ''), '%^&')
			AND COALESCE(d.L04, '%^&') = COALESCE(NULLIF(clw.L04, ''), '%^&')
			AND prm.ProcessingDate BETWEEN d.StartDate AND d.EndDate

		INSERT INTO #Timings SELECT SYSDATETIME(), 'Looked up DimAccidentYearID', @@ERROR
		--------------------------------------------------------------------------------	
		-- Lookup Intended_DimAccountingID
		--------------------------------------------------------------------------------
		UPDATE clw
		SET Intended_DimAccountingID = COALESCE(d.DimAccountingID, prm.DimAccountingUncoded)
		FROM #ClaimLoadWide clw
		CROSS JOIN #Parameters prm
		LEFT JOIN EDW_PREPROD.assumed.DimAccounting d
			ON COALESCE(d.ActuarialLob, '%^&') = COALESCE(NULLIF(clw.ActuarialLob, ''), '%^&')
			AND COALESCE(d.RPT_OFF_NAME, '%^&') = COALESCE(NULLIF(clw.RPT_OFF_NAME, ''), '%^&')
			AND COALESCE(d.InsurerCode, '%^&') = COALESCE(NULLIF(clw.InsurerCode, ''), '%^&')
			AND COALESCE(d.FINANCIAL_LOB, '%^&') = COALESCE(NULLIF(clw.FINANCIAL_LOB, ''), '%^&')
			AND COALESCE(d.T7_CODE, '%^&') = COALESCE(NULLIF(clw.T7_CODE, ''), '%^&')
			AND COALESCE(d.T8_CODE, '%^&') = COALESCE(NULLIF(clw.T8_CODE, ''), '%^&')
			AND COALESCE(d.T9_CODE, '%^&') = COALESCE(NULLIF(clw.T9_CODE, ''), '%^&')
			AND COALESCE(d.CLMS_PROCSS_CLM_DEPT, '%^&') = COALESCE(NULLIF(clw.CLMS_PROCSS_CLM_DEPT, ''), '%^&')
			AND COALESCE(d.ICP_CEDED_FLG, '%^&') = COALESCE(NULLIF(clw.ICP_CEDED_FLG, ''), '%^&')
			AND COALESCE(d.MBU, '%^&') = COALESCE(NULLIF(clw.MBU, ''), '%^&')
			AND COALESCE(d.L01, '%^&') = COALESCE(NULLIF(clw.L01, ''), '%^&')
			AND COALESCE(d.L02, '%^&') = COALESCE(NULLIF(clw.L02, ''), '%^&')
			AND COALESCE(d.L03, '%^&') = COALESCE(NULLIF(clw.L03, ''), '%^&')
			AND COALESCE(d.L06, '%^&') = COALESCE(NULLIF(clw.L06, ''), '%^&')
			AND COALESCE(d.L07, '%^&') = COALESCE(NULLIF(clw.L07, ''), '%^&')
			AND COALESCE(d.L10, '%^&') = COALESCE(NULLIF(clw.L10, ''), '%^&')
			AND COALESCE(d.GD1, '%^&') = COALESCE(NULLIF(clw.GD1, ''), '%^&')
			AND COALESCE(d.RPTCURR1_CD, '%^&') = COALESCE(NULLIF(clw.RPTCURR1_CD, ''), '%^&')
			AND COALESCE(d.RPTCURR2_CD, '%^&') = COALESCE(NULLIF(clw.RPTCURR2_CD, ''), '%^&')
			AND COALESCE(d.ASLOB, '%^&') = COALESCE(NULLIF(clw.ASLOB, ''), '%^&')
			AND prm.ProcessingDate BETWEEN d.StartDate AND d.EndDate

		INSERT INTO #Timings SELECT SYSDATETIME(), 'Looked up Intended_DimAccountingID', @@ERROR
		--------------------------------------------------------------------------------	
		-- Lookup DimAccountingID
		--------------------------------------------------------------------------------
		UPDATE clw
		SET DimAccountingID = COALESCE(d.DimAccountingID, prm.DimAccountingUncoded)
		FROM #ClaimLoadWide clw
		CROSS JOIN #Parameters prm
		LEFT JOIN EDW_PREPROD.assumed.DimAccounting d
			ON COALESCE(d.ActuarialLob, '%^&') = COALESCE(NULLIF(clw.ActuarialLob, ''), '%^&')
			AND COALESCE(d.RPT_OFF_NAME, '%^&') = COALESCE(NULLIF(clw.RPT_OFF_NAME, ''), '%^&')
			AND COALESCE(d.InsurerCode, '%^&') = COALESCE(NULLIF(clw.InsurerCode, ''), '%^&')
			AND COALESCE(d.FINANCIAL_LOB, '%^&') = COALESCE(NULLIF(clw.FINANCIAL_LOB, ''), '%^&')
			AND COALESCE(d.T7_CODE, '%^&') = COALESCE(NULLIF(clw.T7_CODE, ''), '%^&')
			AND COALESCE(d.T8_CODE, '%^&') = COALESCE(NULLIF(clw.T8_CODE, ''), '%^&')
			AND COALESCE(d.T9_CODE, '%^&') = COALESCE(NULLIF(clw.T9_CODE, ''), '%^&')
			AND COALESCE(d.CLMS_PROCSS_CLM_DEPT, '%^&') = COALESCE(NULLIF(clw.CLMS_PROCSS_CLM_DEPT, ''), '%^&')
			AND COALESCE(d.ICP_CEDED_FLG, '%^&') = COALESCE(NULLIF(clw.ICP_CEDED_FLG, ''), '%^&')
			AND COALESCE(d.MBU, '%^&') = COALESCE(NULLIF(clw.MBU, ''), '%^&')
			AND COALESCE(d.L01, '%^&') = COALESCE(NULLIF(clw.L01, ''), '%^&')
			AND COALESCE(d.L02, '%^&') = COALESCE(NULLIF(clw.L02, ''), '%^&')
			AND COALESCE(d.L03, '%^&') = COALESCE(NULLIF(clw.L03, ''), '%^&')
			AND COALESCE(d.L06, '%^&') = COALESCE(NULLIF(clw.L06, ''), '%^&')
			AND COALESCE(d.L07, '%^&') = COALESCE(NULLIF(clw.L07, ''), '%^&')
			AND COALESCE(d.L10, '%^&') = COALESCE(NULLIF(clw.L10, ''), '%^&')
			AND COALESCE(d.GD1, '%^&') = COALESCE(NULLIF(CASE WHEN clw.AdjustedTCodeL04 = 1 AND clw.GD1 = 'TIRS' THEN 'TIRS ADJ' ELSE clw.GD1 END, ''), '%^&')
			AND COALESCE(d.RPTCURR1_CD, '%^&') = COALESCE(NULLIF(clw.RPTCURR1_CD, ''), '%^&')
			AND COALESCE(d.RPTCURR2_CD, '%^&') = COALESCE(NULLIF(clw.RPTCURR2_CD, ''), '%^&')
			AND COALESCE(d.ASLOB, '%^&') = COALESCE(NULLIF(clw.ASLOB, ''), '%^&')
			AND prm.ProcessingDate BETWEEN d.StartDate AND d.EndDate

		INSERT INTO #Timings SELECT SYSDATETIME(), 'Looked up DimAccountingID', @@ERROR
		--------------------------------------------------------------------------------	
		-- Lookup DimAdjustmentTypeID
		--------------------------------------------------------------------------------
		UPDATE clw
		SET DimAdjustmentTypeID = COALESCE(d.DimAdjustmentTypeID, prm.DimAdjustmentTypeUncoded)
		FROM #ClaimLoadWide clw
		CROSS JOIN #Parameters prm
		LEFT JOIN EDW_PREPROD.assumed.DimAdjustmentType d
			ON d.AdjustmentType = clw.adjustmenttype
			AND prm.ProcessingDate BETWEEN d.StartDate AND d.EndDate

		INSERT INTO #Timings SELECT SYSDATETIME(), 'Looked up DimAdjustmentTypeID', @@ERROR
		--------------------------------------------------------------------------------	
		-- Lookup DimLineOfBusiness
		--------------------------------------------------------------------------------
		UPDATE clw
		SET DimLineOfBusinessID = COALESCE(d.DimLineOfBusinessID, prm.DimLineOfBusinessUncoded)
		FROM #ClaimLoadWide clw
		CROSS JOIN #Parameters prm
		LEFT JOIN EDW_PREPROD.assumed.DimLineOfBusiness d
			ON d.LineOfBusinessName = clw.lob_name
			AND COALESCE(d.solvency_II_regulatory_key, -1) = COALESCE(clw.solvency_II_regulatory_key, -1)
			AND prm.ProcessingDate BETWEEN d.StartDate AND d.EndDate

		INSERT INTO #Timings SELECT SYSDATETIME(), 'Looked up DimLineOfBusiness', @@ERROR
		--------------------------------------------------------------------------------	
		-- Lookup Orig_DimCurrencyID
		--------------------------------------------------------------------------------
		UPDATE clw
		SET Orig_DimCurrencyID = COALESCE(d.DimCurrencyID, prm.DimCurrencyUncoded)
		FROM #ClaimLoadWide clw
		CROSS JOIN #Parameters prm
		LEFT JOIN EDW_PREPROD.assumed.DimCurrency d
			ON d.ISOCurrencyCode = clw.ORIGCURR_CD
			AND prm.ProcessingDate BETWEEN d.StartDate AND d.EndDate

		INSERT INTO #Timings SELECT SYSDATETIME(), 'Looked up Orig_DimCurrencyID', @@ERROR
		--------------------------------------------------------------------------------	
		-- Lookup Settl_DimCurrencyID
		--------------------------------------------------------------------------------
		UPDATE clw
		SET Settl_DimCurrencyID = CASE WHEN NULLIF(clw.SETTL_CURR_CD, '') IS NULL THEN prm.DimCurrencyNA ELSE COALESCE(d.DimCurrencyID, prm.DimCurrencyUncoded) END
		FROM #ClaimLoadWide clw
		CROSS JOIN #Parameters prm
		LEFT JOIN EDW_PREPROD.assumed.DimCurrency d
			ON d.ISOCurrencyCode = clw.SETTL_CURR_CD
			AND prm.ProcessingDate BETWEEN d.StartDate AND d.EndDate

		INSERT INTO #Timings SELECT SYSDATETIME(), 'Looked up Settl_DimCurrencyID', @@ERROR
		--------------------------------------------------------------------------------	
		-- Lookup OrigRpt1_DimExchangeRate
		--------------------------------------------------------------------------------
		UPDATE clw
		SET OrigRpt1_DimExchangeRateID = CASE WHEN NULLIF(clw.RPTCURR1_CD, '') IS NULL THEN prm.DimExchangeRateNA ELSE COALESCE(d.DimExchangeRateID, prm.DimExchangeRateUncoded) END
		FROM #ClaimLoadWide clw
		CROSS JOIN #Parameters prm
		LEFT JOIN EDW_PREPROD.assumed.DimExchangeRate d
			ON d.FromCurrency = clw.ORIGCURR_CD
			AND d.ToCurrency = clw.RPTCURR1_CD
			AND d.AccountingPeriodDate = clw.reg_date
			AND prm.ProcessingDate BETWEEN d.StartDate AND d.EndDate

		INSERT INTO #Timings SELECT SYSDATETIME(), 'Looked up OrigRpt1_DimExchangeRate', @@ERROR
		--------------------------------------------------------------------------------	
		-- Lookup OrigRpt2_DimExchangeRate
		--------------------------------------------------------------------------------
		UPDATE clw
		SET OrigRpt2_DimExchangeRateID = CASE WHEN NULLIF(clw.RPTCURR2_CD, '') IS NULL THEN prm.DimExchangeRateNA ELSE COALESCE(d.DimExchangeRateID, prm.DimExchangeRateUncoded) END
		FROM #ClaimLoadWide clw
		CROSS JOIN #Parameters prm
		LEFT JOIN EDW_PREPROD.assumed.DimExchangeRate d
			ON d.FromCurrency = clw.ORIGCURR_CD
			AND d.ToCurrency = clw.RPTCURR2_CD
			AND d.AccountingPeriodDate = clw.reg_date
			AND prm.ProcessingDate BETWEEN d.StartDate AND d.EndDate

		INSERT INTO #Timings SELECT SYSDATETIME(), 'Looked up OrigRpt2_DimExchangeRate', @@ERROR
		--------------------------------------------------------------------------------	
		-- Lookup SettlRpt1_DimExchangeRate
		--------------------------------------------------------------------------------
		UPDATE clw
		SET SettlRpt1_DimExchangeRateID = CASE WHEN NULLIF(clw.RPTCURR1_CD, '') IS NULL OR NULLIF(clw.SETTL_CURR_CD, '') IS NULL THEN prm.DimExchangeRateNA ELSE COALESCE(d.DimExchangeRateID, prm.DimExchangeRateUncoded) END
		FROM #ClaimLoadWide clw
		CROSS JOIN #Parameters prm
		LEFT JOIN EDW_PREPROD.assumed.DimExchangeRate d
			ON d.FromCurrency = clw.SETTL_CURR_CD
			AND d.ToCurrency = clw.RPTCURR1_CD
			AND d.AccountingPeriodDate = clw.reg_date
			AND prm.ProcessingDate BETWEEN d.StartDate AND d.EndDate

		INSERT INTO #Timings SELECT SYSDATETIME(), 'Looked up SettlRpt1_DimExchangeRate', @@ERROR
		--------------------------------------------------------------------------------	
		-- Lookup SettlRpt2_DimExchangeRateID
		--------------------------------------------------------------------------------
		UPDATE clw
		SET SettlRpt2_DimExchangeRateID = CASE WHEN NULLIF(clw.RPTCURR2_CD, '') IS NULL OR NULLIF(clw.SETTL_CURR_CD, '') IS NULL THEN prm.DimExchangeRateNA ELSE COALESCE(d.DimExchangeRateID, prm.DimExchangeRateUncoded) END
		FROM #ClaimLoadWide clw
		CROSS JOIN #Parameters prm
		LEFT JOIN EDW_PREPROD.assumed.DimExchangeRate d
			ON d.FromCurrency = clw.SETTL_CURR_CD
			AND d.ToCurrency = clw.RPTCURR2_CD
			AND d.AccountingPeriodDate = clw.reg_date
			AND prm.ProcessingDate BETWEEN d.StartDate AND d.EndDate

		INSERT INTO #Timings SELECT SYSDATETIME(), 'Looked up SettlRpt2_DimExchangeRateID', @@ERROR
		--------------------------------------------------------------------------------	
		-- Lookup DimDueDateID
		--------------------------------------------------------------------------------
		UPDATE clw
		SET DimDueDateID = CASE WHEN clw.DueDate IS NULL THEN prm.DimDateNA ELSE COALESCE(d.DimDateID, prm.DimDateUncoded) END
		FROM #ClaimLoadWide clw
		CROSS JOIN #Parameters prm
		LEFT JOIN EDW_PREPROD.assumed.DimDate d
			ON d.Date = clw.DueDate
			AND prm.ProcessingDate BETWEEN d.StartDate AND d.EndDate
			 
	    INSERT INTO #Timings SELECT SYSDATETIME(), 'Looked up DimDueDateID', @@ERROR
		--------------------------------------------------------------------------------	
		-- Lookup DimFromDateID and DimToDateID
		--------------------------------------------------------------------------------
		 UPDATE clw
        	 SET   DimFromDateID	= CASE WHEN clw.acct_from_dt IS NULL THEN prm.DimDateNA ELSE COALESCE(d.DimDateID, prm.DimDateUncoded) END
        		  ,DimToDateID		= CASE WHEN clw.acct_to_dt   IS NULL THEN prm.DimDateNA ELSE COALESCE(dd.DimDateID, prm.DimDateUncoded) END
         FROM #ClaimLoadWide	clw	
		 CROSS JOIN #Parameters			prm
         LEFT JOIN EDW_PREPROD.assumed.DimDate d	ON d.Date = clw.acct_from_dt
	       											AND prm.ProcessingDate BETWEEN d.StartDate AND d.EndDate
         LEFT JOIN EDW_PREPROD.assumed.DimDate dd	ON dd.Date = clw.acct_to_dt
													AND prm.ProcessingDate BETWEEN dd.StartDate AND dd.EndDate

	    INSERT INTO #Timings SELECT SYSDATETIME(), 'Lookup DimFromDateID and DimToDateID', @@ERROR
		--------------------------------------------------------------------------------	
		-- Lookup DimPayeeID
		--------------------------------------------------------------------------------
		UPDATE clw
           SET DimPayeeID	= CASE WHEN clw.bill_co_br_key IS NULL THEN prm.DimPayeeNA ELSE COALESCE(p.DimPayeeID, prm.DimPayeeUncoded) END
          FROM #ClaimLoadWide	clw	
		 CROSS JOIN #Parameters			prm
         LEFT JOIN EDW_PREPROD.assumed.DimPayee p	ON p.PayeeCode = clw.bill_co_br_key

	    INSERT INTO #Timings SELECT SYSDATETIME(), 'Lookup DimPayeeID', @@ERROR
		 --------------------------------------------------------------------------------	
		-- Lookup DimDocument
		--------------------------------------------------------------------------------
		UPDATE clw
		   SET DimDocumentID = CASE WHEN clw.doc_key IS NULL THEN prm.DimDocumentNA ELSE  COALESCE(d.DimDocumentID, prm.DimDocumentUncoded) END
		  FROM #ClaimLoadWide	clw
		 CROSS JOIN #Parameters	prm
		 LEFT  JOIN EDW_PREPROD.assumed.DimDocument d	ON  (d.doc_key = clw.doc_key)
														AND d.SourceSysKey = clw.SourceID
														AND prm.ProcessingDate BETWEEN d.StartDate AND d.EndDate
 
		INSERT INTO #Timings SELECT SYSDATETIME(), 'Lookup DimDocumentID', @@ERROR
		--------------------------------------------------------------------------------	
		-- #MapParticipant
		--------------------------------------------------------------------------------
		DROP TABLE IF EXISTS #MapParticipant

		SELECT x.Contract_NBR
			,DimParticipantID = COALESCE(dp.DimParticipantID, prm.DimParticipantUncoded)
			,x.Participant_Key
			,PreviousCumuluativeCessionShare = COALESCE(LAG(x.CumulativeCessionShare) OVER (PARTITION BY x.Contract_NBR ORDER BY x.Participant_Key), 0)
			,x.CumulativeCessionShare
			,x.TotalCessionShare
		INTO #MapParticipant
		FROM #Parameters prm
		CROSS JOIN (
			SELECT tph.Contract_NBR
				,tph.Participant_Key
				,tph.Participant
				,CumulativeCessionShare = SUM(tph.CessionPercent) OVER (PARTITION BY tph.Contract_NBR ORDER BY tph.Participant_Key)
				,TotalCessionShare = SUM(tph.CessionPercent) OVER (PARTITION BY tph.Contract_NBR)
			FROM EDW_PREPROD.dbo.TIRS_PARTICIPANT_HISTORY tph
			WHERE tph.END_DATE = '31 Dec 9999'
			) x
		LEFT JOIN EDW_PREPROD.assumed.DimParticipant dp
			ON dp.EndDate = '31 Dec 9999'
			AND dp.Participant_key = x.Participant_Key

		INSERT INTO #Timings SELECT SYSDATETIME(), 'Created #MapParticipant', @@ERROR
		 --------------------------------------------------------------------------------	
		-- #PayeeOverride (updating DimPayeeID for ceded claims)
		--------------------------------------------------------------------------------
		DROP TABLE IF EXISTS #PayeeOverride
		
		SELECT DISTINCT Ceded_DimContractID = dc.DimContractID
			,dp.DimParticipantID
			,dpay.DimPayeeID
		INTO #PayeeOverride
		FROM SRC_TIRS_DB.dbo.claim_trans ct
		INNER JOIN SRC_TIRS_DB.dbo.claim c
			ON c.clm_key = ct.clm_key
		INNER JOIN SRC_TIRS_DB.dbo.trty_master ctm
			ON ctm.trty_key = ct.ceded_trty_key
		INNER JOIN SRC_TIRS_DB.dbo.trty_participant tp
			ON tp.trty_key = ctm.trty_key
		INNER JOIN EDW_PREPROD.assumed.DimContract dc
			ON dc.CONTRACT_NBR = CONCAT(LEFT(ctm.trty_no, 5), ctm.und_yr) COLLATE DATABASE_DEFAULT
			AND dc.EndDate = '31 Dec 9999'
		INNER JOIN EDW_PREPROD.assumed.DimParticipant dp
			ON dp.Participant_Key = tp.participant_br_key
			AND dp.EndDate = '31 Dec 9999'
		INNER JOIN EDW_PREPROD.assumed.DimPayee dpay
			ON dpay.PayeeCode = tp.brkr_br_key
		UNION
		SELECT DISTINCT Ceded_DimContractID = dc.DimContractID
			,dp.DimParticipantID
			,dpay.DimPayeeID
		FROM SRC_TIRS_DB.dbo.acct_doc ad
		INNER JOIN SRC_TIRS_DB.dbo.trty_master ctm
			ON ctm.trty_key = ad.ceded_trty_key
		INNER JOIN SRC_TIRS_DB.dbo.trty_participant tp
			ON tp.trty_key = ctm.trty_key
		INNER JOIN EDW_PREPROD.assumed.DimContract dc
			ON dc.CONTRACT_NBR = CONCAT(LEFT(ctm.trty_no, 5), ctm.und_yr) COLLATE DATABASE_DEFAULT
			AND dc.EndDate = '31 Dec 9999'
		INNER JOIN EDW_PREPROD.assumed.DimParticipant dp
			ON dp.Participant_Key = tp.participant_br_key
			AND dp.EndDate = '31 Dec 9999'
		INNER JOIN EDW_PREPROD.assumed.DimPayee dpay
			ON dpay.PayeeCode = tp.brkr_br_key
			

		INSERT INTO #Timings SELECT SYSDATETIME(), 'Creating #PayeeOverride for updating DimPayeeID for ceded claims', @@ERROR
		--------------------------------------------------------------------------------	
		-- #CurrencyDecimalPlaces
		--------------------------------------------------------------------------------

		DROP TABLE IF EXISTS #CurrencyDecimalPlaces

		SELECT x.Orig_DimCurrencyID
			,x.Settl_DimCurrencyID
			,y.CurrencyType
			,DecPlaces = COALESCE(cdp.DecPlaces, 2)
		INTO #CurrencyDecimalPlaces
		FROM (
			SELECT DISTINCT ORIGCURR_CD, Orig_DimCurrencyID, SETTL_CURR_CD, Settl_DimCurrencyID
			FROM #ClaimLoadWide clw
			) x
		CROSS JOIN (
			VALUES('Original')
				,('Settlement')
			) y (CurrencyType)
		LEFT JOIN EDW_Staging.assumed.CurrencyDecimalPlaces cdp
			ON cdp.CurrencyCode COLLATE DATABASE_DEFAULT = CASE WHEN y.CurrencyType = 'Original' THEN x.ORIGCURR_CD ELSE x.SETTL_CURR_CD END
		WHERE y.CurrencyType = 'Original'
			OR (y.CurrencyType = 'Settlement' AND SETTL_CURR_CD != '')

		INSERT INTO #Timings SELECT SYSDATETIME(), 'Created #CurrencyDecimalPlaces', @@ERROR
		--------------------------------------------------------------------------------	
		-- #LoadClaim (create the new table structure)
		--------------------------------------------------------------------------------

		DROP TABLE IF EXISTS #LoadClaim

		SELECT ClaimLoadWideID = MAX(clw.ClaimLoadWideID)
			,clw.SourceSystemKey
			,clw.DimContractID
			,clw.DimClaimTransactionID
			,clw.Ceded_DimContractID
			,clw.Intended_DimAccountingPeriodID
			,clw.DimAccidentYearID
			,clw.Intended_DimAccountingID
			,clw.DimAccountingID
			,clw.DimAdjustmentTypeID
			,clw.Orig_DimCurrencyID
			,clw.Settl_DimCurrencyID	
			,clw.DimLineOfBusinessID
			,clw.OrigRpt1_DimExchangeRateID
			,clw.OrigRpt2_DimExchangeRateID
			,clw.SettlRpt1_DimExchangeRateID
			,clw.SettlRpt2_DimExchangeRateID
			,clw.DimTransactionTypeID
			,clw.DimDueDateID
			,clw.DimFromDateID  
			,clw.DimToDateID 
			,DimPayeeID			= COALESCE(po.DimPayeeID, clw.DimPayeeID)
			,DimParticipantID	= COALESCE(mp.DimParticipantID, prm.DimParticipantNA)
			,DimMeasureID		= COALESCE(m.DimMeasureID, prm.DimMeasureUncoded)
			,clw.DimDocumentID
			,Amount		= CAST(SUM(CASE WHEN mp.CumulativeCessionShare IS NULL 
										THEN ROUND(x.Amount , cdp.DecPlaces)
										ELSE ROUND(x.Amount * mp.CumulativeCessionShare / mp.TotalCessionShare, cdp.DecPlaces) 
										   - ROUND(x.Amount * mp.PreviousCumuluativeCessionShare / mp.TotalCessionShare, cdp.DecPlaces) END)
								AS DECIMAL(19,2))
			,AmountUSD	= CAST(SUM(CASE WHEN mp.CumulativeCessionShare IS NULL 
										THEN ROUND(x.AmountUSD , 2)
										ELSE ROUND(x.AmountUSD * mp.CumulativeCessionShare / mp.TotalCessionShare, 2)
										   - ROUND(x.AmountUSD * mp.PreviousCumuluativeCessionShare / mp.TotalCessionShare, 2) END)
								AS DECIMAL(19,2))
			,CreatedDate= prm.ProcessingDate
		INTO #LoadClaim
		FROM #ClaimLoadWide clw
		CROSS JOIN #Parameters prm
		CROSS APPLY (
			SELECT y.Business
				,y.CurrencyType
				,y.MeasureType
				,y.Amount
				,y.AmountUSD
			FROM (
				VALUES ('RI Assumed', 'Original', 'Loss Paid', clw.SUMMABLE_LOSS_PAID, clw.SUMMABLE_LOSS_PAID_USD)
					,('RI Assumed', 'Original', 'Loss Expense Paid', clw.SUMMABLE_LOSS_EXP_PAID, clw.SUMMABLE_LOSS_EXP_PAID_USD)
					,('RI Assumed', 'Original', 'Loss Adjustment Expense', clw.SUMMABLE_LAE, clw.SUMMABLE_LAE_USD)
					,('RI Assumed', 'Original', 'Cash Loss Advance', clw.SUMMABLE_CASH_LOSS_ADV_AMT, clw.SUMMABLE_CASH_LOSS_ADV_AMT_USD)
					,('RI Assumed', 'Original', 'Cash Loss Refund', clw.SUMMABLE_CASH_LOSS_REFUND, clw.SUMMABLE_CASH_LOSS_REFUND_USD)
					,('RI Assumed', 'Original', 'Funds Released Losses', clw.SUMMABLE_FUNDS_RELEASED_LOSSES, clw.SUMMABLE_FUNDS_RELEASED_LOSSES_USD)
					,('RI Assumed', 'Original', 'Reinstatement Premium', clw.SUMMABLE_REINSTATEMENT_PREMIUM, clw.SUMMABLE_REINSTATEMENT_PREMIUM_USD)
					,('RI Assumed', 'Original', 'Outstanding Loss', clw.SUMMABLE_OS_LOSS, clw.SUMMABLE_OS_LOSS_USD)
					,('RI Assumed', 'Original', 'Outstanding Loss Expense', clw.SUMMABLE_OS_LOSS_EXP, clw.SUMMABLE_OS_LOSS_EXP_USD)
					,('RI Ceded', 'Original', 'Loss Paid', clw.SUMMABLE_CEDED_LOSS_PAID, clw.SUMMABLE_CEDED_LOSS_PAID_USD)
					,('RI Ceded', 'Original', 'Loss Expense Paid', clw.SUMMABLE_CEDED_LOSS_EXP_PAID, clw.SUMMABLE_CEDED_LOSS_EXP_PAID_USD)
					,('RI Ceded', 'Original', 'Loss Adjustment Expense', clw.SUMMABLE_CEDED_LAE, clw.SUMMABLE_CEDED_LAE_USD)
					,('RI Ceded', 'Original', 'Cash Loss Advance', clw.SUMMABLE_CEDED_CASH_LOSS_ADV_AMT, clw.SUMMABLE_CEDED_CASH_LOSS_ADV_AMT_USD)
					,('RI Ceded', 'Original', 'Cash Loss Refund', clw.SUMMABLE_CEDED_CASH_LOSS_REFUND, clw.SUMMABLE_CEDED_CASH_LOSS_REFUND_USD)
					,('RI Ceded', 'Original', 'Funds Released Losses', clw.SUMMABLE_CEDED_FUNDS_RELEASED_LOSSES, clw.SUMMABLE_CEDED_FUNDS_RELEASED_LOSSES_USD)
					,('RI Ceded', 'Original', 'Outstanding Loss', clw.SUMMABLE_CEDED_OS_LOSS, clw.SUMMABLE_CEDED_OS_LOSS_USD)
					,('RI Ceded', 'Original', 'Outstanding Loss Expense', clw.SUMMABLE_CEDED_OS_LOSS_EXP, clw.SUMMABLE_CEDED_OS_LOSS_EXP_USD)
					,('RI Ceded', 'Original', 'Reinstatement Premium', clw.SUMMABLE_CEDED_REINSTATEMENT_PREMIUM, clw.SUMMABLE_CEDED_REINSTATEMENT_PREMIUM_USD)
					,('RI Assumed', 'Settlement', 'Loss Paid', clw.SUMMABLE_SETTL_LOSS_PAID, clw.SUMMABLE_SETTL_LOSS_PAID_USD)
					,('RI Assumed', 'Settlement', 'Loss Adjustment Expense', clw.SUMMABLE_SETTL_LAE, clw.SUMMABLE_SETTL_LAE_USD)
					,('RI Assumed', 'Original', 'FIRV IBNR Begin', clw.FIRVIBNRBeg, clw.FIRVIBNRBegUSD)
					,('RI Assumed', 'Original', 'FIRV IBNR End', clw.FIRVIBNREnd, clw.FIRVIBNREndUSD)
					,('RI Ceded','Original','FIRV IBNR Begin', clw.CededFIRVIBNRBeg, clw.CededFIRVIBNRBegUSD)
					,('RI Ceded','Original','FIRV IBNR End', clw.CededFIRVIBNREnd, clw.CededFIRVIBNREndUSD)
				) y (Business, CurrencyType, MeasureType, Amount, AmountUSD)
			WHERE NOT (y.Amount = 0 AND y.AmountUSD = 0)
			) x
		INNER JOIN #CurrencyDecimalPlaces cdp
			ON cdp.Orig_DimCurrencyID = clw.Orig_DimCurrencyID
			AND cdp.Settl_DimCurrencyID = clw.Settl_DimCurrencyID
			AND cdp.CurrencyType = x.CurrencyType
		LEFT JOIN EDW_PREPROD.assumed.DimMeasure m
			ON m.Entity = 'Claim'
			AND m.Business = x.Business	
			AND m.CurrencyType = x.CurrencyType
			AND m.MeasureType = x.MeasureType
			AND prm.ProcessingDate BETWEEN m.StartDate and m.EndDate
		LEFT JOIN #MapParticipant mp
			ON mp.Contract_NBR = clw.Contract_NBR
			AND m.Business = 'RI Ceded'
		LEFT JOIN #PayeeOverride po
			ON po.Ceded_DimContractID = clw.Ceded_DimContractID
			AND po.DimParticipantID = mp.DimParticipantID
		GROUP BY clw.SourceSystemKey
			,clw.DimContractID
			,clw.DimClaimTransactionID
			,clw.Ceded_DimContractID
			,clw.Intended_DimAccountingPeriodID
			,clw.DimAccidentYearID
			,clw.Intended_DimAccountingID
			,clw.DimAccountingID
			,clw.DimAdjustmentTypeID
			,clw.Orig_DimCurrencyID
			,clw.Settl_DimCurrencyID	
			,clw.DimLineOfBusinessID
			,clw.OrigRpt1_DimExchangeRateID
			,clw.OrigRpt2_DimExchangeRateID
			,clw.SettlRpt1_DimExchangeRateID
			,clw.SettlRpt2_DimExchangeRateID
			,clw.DimTransactionTypeID
			,clw.DimDueDateID
			,clw.DimFromDateID  
			,clw.DimToDateID 
			,COALESCE(po.DimPayeeID, clw.DimPayeeID)
			,COALESCE(mp.DimParticipantID, prm.DimParticipantNA)
			,COALESCE(m.DimMeasureID, prm.DimMeasureUncoded)
			,clw.DimDocumentID
			,prm.ProcessingDate
		HAVING NULLIF(SUM(x.Amount), 0) IS NOT NULL

		INSERT INTO #Timings SELECT SYSDATETIME(), 'Created #LoadClaim', @@ERROR

		-- To cater for TIRS and TIRS_ADJ in GD1 (which was original functionality, attempting to replicate), provide mappings from TIRS to TIRS ADJ, TIRS ADJ (and anything else) to itself
		-- Used to calculated DimAccountingID (the GD1 that will be reported and should be TIRS ADJ if was originally TIRS, but has undergone a T_Code_History change, or L04 change)
		DROP TABLE IF EXISTS #DimAccountingPairing

		SELECT DISTINCT z.Intended_DimAccountingID
			,z.DimAccountingID
		INTO #DimAccountingPairing
		FROM (
			SELECT Intended_DimAccountingID = MIN(CASE WHEN COALESCE(x.GD1, '') != 'TIRS ADJ' THEN x.DimAccountingID END)
				,DimAccountingID = COALESCE(MIN(CASE WHEN x.GD1 = 'TIRS ADJ' THEN x.DimAccountingID END), MIN(CASE WHEN COALESCE(x.GD1, '') != 'TIRS ADJ' THEN x.DimAccountingID END))
			FROM (
				SELECT da.DimAccountingID
					,UniqueCombination = DENSE_RANK() OVER (ORDER BY da.ActuarialLob
						,da.RPT_OFF_NAME
						,da.InsurerCode
						,da.FINANCIAL_LOB
						,da.T7_CODE
						,da.T8_CODE
						,da.T9_CODE
						,da.CLMS_PROCSS_CLM_DEPT
						,da.ICP_CEDED_FLG
						,da.MBU
						,da.L01
						,da.L02
						,da.L03
						,da.L06
						,da.L07
						,da.L10
						,da.RPTCURR1_CD
						,da.RPTCURR2_CD
						,da.ASLOB
						)
					,GD1
				FROM EDW_PREPROD.assumed.DimAccounting da
				WHERE da.EndDate = '31 Dec 9999'
				) x
			GROUP BY x.UniqueCombination
			) y
		CROSS APPLY (
			VALUES(y.Intended_DimAccountingID, y.DimAccountingID)
				,(y.DimAccountingID, y.DimAccountingID)
			) z (Intended_DimAccountingID, DimAccountingID)


	INSERT INTO #Timings SELECT SYSDATETIME(), 'Created #DimAccountingPairing', @@ERROR
	--------------------------------------------------------------------------------	
	-- FactClaimUncoded INSERT (new uncoded values)
	--------------------------------------------------------------------------------
	BEGIN TRANSACTION
		-- capture any lookup failures (uncoded values) - there shouldn't be any, so this information may be required for corrections if any do occur
		INSERT INTO EDW_Staging.assumed.FactClaimUncoded (
			 [StartDate]
			,[UncodedDescription]      
			--------------------------------
			,[DimContractID]					
			,[Ceded_DimContractID]			
			,[DimTransactionTypeID]			
			,[DimClaimTransactionID]			
			,[DimDueDateID]					
			,[Intended_DimAccountingPeriodID]
			,[DimAccidentYearID]				
			,[Intended_DimAccountingID]		
			,[DimAccountingID]				
			,[DimAdjustmentTypeID]			
			,[Orig_DimCurrencyID]			
			,[Settl_DimCurrencyID]			
			,[DimLineOfBusinessID]			
			,[OrigRpt1_DimExchangeRateID]	
			,[OrigRpt2_DimExchangeRateID]	
			,[SettlRpt1_DimExchangeRateID]	
			,[SettlRpt2_DimExchangeRateID]	
			,[DimParticipantID]				
			,[DimFromDateID]					
			,[DimToDateID]					
			,[DimPayeeID]					
			,[DimDocumentID]					
			,[DimMeasureID]					
			,[Amount]						
			,[AmountUSD]						
			--------------------------------
			,[TREATY_NBR] 					
			,[UNDERWRITING_YEAR] 			
			,[Ceded_CONTRACT_NBR] 			
			,[CONTRACT_NBR]					
			,[SourceSystemKey] 				
			,[doc_key]						
			,[bill_co_br_key]				
			,[TransactionTypeCode]			
			,[TransactionTypeCategory]		
			,[DueDate]						
			,[ORIGCURR_CD]					
			,[TIRS_ORIG_CURR_CD]				
			,[SETTL_CURR_CD]					
			,[TIRS_ORIG_CURR_NAME]			
			,[lob_name]						
			,[AccidentYear]					
			,[aslob]							
			,[TIRS_UW_ASSM_CEDED_NAME]		
			,[reg_date]						
			,[Claim_NBR]						
			,[TIRS_CLM_CD]					
			,[CatCode]						
			,[CAT_KEY]						
			,[solvency_II_regulatory_key]	
			,[CLAIMLOSSDATE]					
			,[Source]						
			,[AdjustmentType]				
			,[financial_lob]					
			,[T7_CODE]						
			,[T8_CODE]						
			,[T9_CODE]						
			,[InsurerCode]					
			,[CLMS_PROCSS_CLM_DEPT]			
			,[ICP_CEDED_FLG]					
			,[RPT_OFF_NAME]					
			,[ActuarialLob]					
			,[MBU]							
			,[L01]							
			,[L02]							
			,[L03]							
			,[L04]							
			,[L06]							
			,[L07]							
			,[L10]							
			,[GD1]							
			,[RPTCURR1_CD]					
			,[RPTCURR2_CD]					
			,[RPTCURR1]						
			,[RPTCURR2]						
			,[SETTL_RPTCURR1]				
			,[SETTL_RPTCURR2]
		)
		SELECT
			 [StartDate]			= prm.[ProcessingDate]
			,[UncodedDescription]	=  CONCAT_WS(',',
											 IIF(prm.DimContractUncoded			= lc.DimContractID					,'DimContract'					,NULL)
                                            ,IIF(prm.DimContractUncoded			= lc.Ceded_DimContractID			,'Ceded_DimContractID'			,NULL)
                                            ,IIF(prm.DimTransactionTypeUncoded	= lc.DimTransactionTypeID           ,'DimTransactionTypeID'			,NULL)
                                            ,IIF(prm.DimClaimTransactionUncoded	= lc.DimClaimTransactionID          ,'DimClaimTransactionID'		,NULL)
                                            ,IIF(prm.DimDateUncoded				= lc.DimDueDateID				    ,'DimDueDateID'		 			,NULL)
                                            ,IIF(prm.DimAccountingPeriodUncoded	= lc.Intended_DimAccountingPeriodID ,'Intended_DimAccountingPeriodID',NULL)
                                            ,IIF(prm.DimAccidentYearUncoded		= lc.DimAccidentYearID		        ,'DimAccidentYearID'			,NULL)
                                            ,IIF(prm.DimAccountingUncoded		= lc.Intended_DimAccountingID   	,'Intended_DimAccountingID'		,NULL)
                                            ,IIF(prm.DimAccountingUncoded		= lc.DimAccountingID		    	,'DimAccountingID'		 		,NULL)
                                            ,IIF(prm.DimAdjustmentTypeUncoded	= lc.DimAdjustmentTypeID        	,'DimAdjustmentTypeID'			,NULL)
                                            ,IIF(prm.DimCurrencyUncoded			= lc.Orig_DimCurrencyID             ,'Orig_DimCurrencyID'			,NULL)
                                            ,IIF(prm.DimCurrencyUncoded			= lc.Settl_DimCurrencyID            ,'Settl_DimCurrencyID'			,NULL)
                                            ,IIF(prm.DimLineOfBusinessUncoded	= lc.DimLineOfBusinessID        	,'DimLineOfBusinessID'			,NULL)
                                            ,IIF(prm.DimExchangeRateUncoded		= lc.OrigRpt1_DimExchangeRateID     ,'OrigRpt1_DimExchangeRateID'	,NULL)
                                            ,IIF(prm.DimExchangeRateUncoded		= lc.OrigRpt2_DimExchangeRateID     ,'OrigRpt2_DimExchangeRateID'	,NULL)
                                            ,IIF(prm.DimExchangeRateUncoded		= lc.SettlRpt1_DimExchangeRateID    ,'SettlRpt1_DimExchangeRateID'	,NULL)
                                            ,IIF(prm.DimExchangeRateUncoded		= lc.SettlRpt2_DimExchangeRateID    ,'SettlRpt2_DimExchangeRateID'	,NULL)
                                            ,IIF(prm.DimParticipantUncoded		= lc.DimParticipantID               ,'DimParticipantID'				,NULL)
                                            ,IIF(prm.DimDateUncoded				= lc.DimFromDateID                  ,'DimFromDateID'				,NULL)
                                            ,IIF(prm.DimDateUncoded				= lc.DimToDateID                    ,'DimToDateID'		 			,NULL)
                                            ,IIF(prm.DimPayeeUncoded			= lc.DimPayeeID	                	,'DimPayeeID'		 			,NULL)
                                            ,IIF(prm.DimDocumentUncoded			= lc.DimDocumentID	                ,'DimDocumentID'				,NULL)
                                            ,IIF(prm.DimMeasureUncoded			= lc.DimMeasureID                   ,'DimMeasureID'		 			,NULL)
											)
			-------------------------------
			,lc.[DimContractID]					
			,lc.[Ceded_DimContractID]			
			,lc.[DimTransactionTypeID]			
			,lc.[DimClaimTransactionID]			
			,lc.[DimDueDateID]					
			,lc.[Intended_DimAccountingPeriodID]
			,lc.[DimAccidentYearID]				
			,lc.[Intended_DimAccountingID]		
			,lc.[DimAccountingID]				
			,lc.[DimAdjustmentTypeID]			
			,lc.[Orig_DimCurrencyID]			
			,lc.[Settl_DimCurrencyID]			
			,lc.[DimLineOfBusinessID]			
			,lc.[OrigRpt1_DimExchangeRateID]	
			,lc.[OrigRpt2_DimExchangeRateID]	
			,lc.[SettlRpt1_DimExchangeRateID]	
			,lc.[SettlRpt2_DimExchangeRateID]	
			,lc.[DimParticipantID]				
			,lc.[DimFromDateID]					
			,lc.[DimToDateID]					
			,lc.[DimPayeeID]					
			,lc.[DimDocumentID]					
			,lc.[DimMeasureID]					
			,lc.[Amount]						
			,lc.[AmountUSD]						
			--------------------------------
			,clw.[TREATY_NBR] 					
			,clw.[UNDERWRITING_YEAR] 			
			,clw.[Ceded_CONTRACT_NBR] 			
			,clw.[CONTRACT_NBR]					
			,clw.[SourceSystemKey] 				
			,clw.[doc_key]						
			,clw.[bill_co_br_key]				
			,clw.[TransactionTypeCode]			
			,clw.[TransactionTypeCategory]		
			,clw.[DueDate]						
			,clw.[ORIGCURR_CD]					
			,clw.[TIRS_ORIG_CURR_CD]				
			,clw.[SETTL_CURR_CD]					
			,clw.[TIRS_ORIG_CURR_NAME]			
			,clw.[lob_name]						
			,clw.[AccidentYear]					
			,clw.[aslob]							
			,clw.[TIRS_UW_ASSM_CEDED_NAME]		
			,clw.[reg_date]						
			,clw.[Claim_NBR]						
			,clw.[TIRS_CLM_CD]					
			,clw.[CatCode]						
			,clw.[CAT_KEY]						
			,clw.[solvency_II_regulatory_key]	
			,clw.[CLAIMLOSSDATE]					
			,clw.[Source]						
			,clw.[AdjustmentType]				
			,clw.[financial_lob]					
			,clw.[T7_CODE]						
			,clw.[T8_CODE]						
			,clw.[T9_CODE]						
			,clw.[InsurerCode]					
			,clw.[CLMS_PROCSS_CLM_DEPT]			
			,clw.[ICP_CEDED_FLG]					
			,clw.[RPT_OFF_NAME]					
			,clw.[ActuarialLob]					
			,clw.[MBU]							
			,clw.[L01]							
			,clw.[L02]							
			,clw.[L03]							
			,clw.[L04]							
			,clw.[L06]							
			,clw.[L07]							
			,clw.[L10]							
			,clw.[GD1]							
			,clw.[RPTCURR1_CD]					
			,clw.[RPTCURR2_CD]					
			,clw.[RPTCURR1]						
			,clw.[RPTCURR2]						
			,clw.[SETTL_RPTCURR1]				
			,clw.[SETTL_RPTCURR2]	

		FROM #LoadClaim lc
		INNER JOIN #ClaimLoadWide 	clw		ON clw.ClaimLoadWideID = lc.ClaimLoadWideID
		INNER JOIN #Parameters		prm		ON prm.DimContractUncoded			= lc.DimContractID			
											OR prm.DimContractUncoded			= lc.Ceded_DimContractID			
											OR prm.DimTransactionTypeUncoded	= lc.DimTransactionTypeID
											OR prm.DimClaimTransactionUncoded	= lc.DimClaimTransactionID
											OR prm.DimDateUncoded				= lc.DimDueDateID				
											OR prm.DimAccountingPeriodUncoded	= lc.Intended_DimAccountingPeriodID
											OR prm.DimAccidentYearUncoded		= lc.DimAccidentYearID		
											OR prm.DimAccountingUncoded			= lc.Intended_DimAccountingID
											OR prm.DimAccountingUncoded			= lc.DimAccountingID		
											OR prm.DimAdjustmentTypeUncoded		= lc.DimAdjustmentTypeID
											OR prm.DimCurrencyUncoded			= lc.Orig_DimCurrencyID
											OR prm.DimCurrencyUncoded			= lc.Settl_DimCurrencyID
											OR prm.DimLineOfBusinessUncoded		= lc.DimLineOfBusinessID
											OR prm.DimExchangeRateUncoded		= lc.OrigRpt1_DimExchangeRateID
											OR prm.DimExchangeRateUncoded		= lc.OrigRpt2_DimExchangeRateID
											OR prm.DimExchangeRateUncoded		= lc.SettlRpt1_DimExchangeRateID
											OR prm.DimExchangeRateUncoded		= lc.SettlRpt2_DimExchangeRateID
											OR prm.DimParticipantUncoded		= lc.DimParticipantID
											OR prm.DimDateUncoded				= lc.DimFromDateID
											OR prm.DimDateUncoded				= lc.DimToDateID
											OR prm.DimPayeeUncoded				= lc.DimPayeeID	
											OR prm.DimDocumentUncoded			= lc.DimDocumentID	
											OR prm.DimMeasureUncoded			= lc.DimMeasureID
		WHERE NOT EXISTS (SELECT * 
							FROM EDW_Staging.Assumed.FactclaimUncoded u
						   WHERE prm.ProcessingDate BETWEEN u.StartDate AND u.EndDate
							  AND ISNULL(u.SourceSystemKey,-1)		= ISNULL(lc.SourceSystemKey,-1)
							  AND u.DimContractID					= lc.DimContractID 
							  AND u.Ceded_DimContractID				= lc.Ceded_DimContractID
							  AND u.DimTransactionTypeID			= lc.DimTransactionTypeID
							  AND u.DimClaimTransactionID			= lc.DimClaimTransactionID
							  AND u.DimDueDateID					= lc.DimDueDateID				
							  AND u.Intended_DimAccountingPeriodID	= lc.Intended_DimAccountingPeriodID
							  AND u.DimAccidentYearID				= lc.DimAccidentYearID		
							  AND u.Intended_DimAccountingID		= lc.Intended_DimAccountingID
							  AND u.DimAccountingID					= lc.DimAccountingID		
							  AND u.DimAdjustmentTypeID				= lc.DimAdjustmentTypeID
							  AND u.Orig_DimCurrencyID				= lc.Orig_DimCurrencyID
							  AND u.Settl_DimCurrencyID				= lc.Settl_DimCurrencyID
							  AND u.DimLineOfBusinessID				= lc.DimLineOfBusinessID
							  AND u.OrigRpt1_DimExchangeRateID		= lc.OrigRpt1_DimExchangeRateID
							  AND u.OrigRpt2_DimExchangeRateID		= lc.OrigRpt2_DimExchangeRateID
							  AND u.SettlRpt1_DimExchangeRateID		= lc.SettlRpt1_DimExchangeRateID
							  AND u.SettlRpt2_DimExchangeRateID		= lc.SettlRpt2_DimExchangeRateID
							  AND u.DimParticipantID				= lc.DimParticipantID
							  AND u.DimFromDateID					= lc.DimFromDateID
							  AND u.DimToDateID						= lc.DimToDateID
							  AND u.DimPayeeID						= lc.DimPayeeID	
							  AND u.DimDocumentID					= lc.DimDocumentID	
							  AND u.DimMeasureID					= lc.DimMeasureID
						)

		INSERT INTO #Timings SELECT SYSDATETIME(), 'Created and uncoded entries in EDW_Staging.assumed.FactClaimUncoded', @@ERROR

		DROP TABLE IF EXISTS #DetectReversalAdjustment

		SELECT x.DimContractID
			,x.DimClaimTransactionID
			,x.DimLineOfBusinessID
			,x.Intended_DimAccountingPeriodID
			,IsAdjustment = CAST(CASE WHEN COALESCE(tcr.ID, -1) = COALESCE(otcr.ID, -1) AND COALESCE(ccr.ID, -1) = COALESCE(occr.ID, -1) THEN 0 ELSE 1 END AS BIT)
		INTO #DetectReversalAdjustment
		FROM (
			SELECT DISTINCT t.DimContractID
				,t.DimClaimTransactionID
				,t.DimLineOfBusinessID
				,t.Intended_DimAccountingPeriodID
			FROM (
				SELECT t.*
				FROM assumed.FactClaim t
				LEFT JOIN assumed.FactClaim r
					ON r.ReversalOfFactClaimID = t.FactClaimID
				WHERE r.ReversalOfFactClaimID IS NULL
					AND t.ReversalOfFactClaimID IS NULL
				) t
			INNER JOIN EDW_PREPROD.assumed.DimContract dc
				ON dc.DimContractID = t.DimContractID
			INNER JOIN #ContractFilter cf
				ON cf.CONTRACT_NBR = dc.CONTRACT_NBR COLLATE DATABASE_DEFAULT
			) x
		CROSS JOIN #Parameters prm
		INNER JOIN EDW_PREPROD.assumed.DimContract dc
			ON dc.DimContractID = x.DimContractID
		INNER JOIN EDW_PREPROD.assumed.DimAccountingPeriod dap
			ON dap.DimAccountingPeriodID = x.Intended_DimAccountingPeriodID
		INNER JOIN #AccountingPeriod ap
			ON ap.AccountingPeriodDate = dap.AccountingPeriodDate
		INNER JOIN EDW_PREPROD.assumed.DimLineOfBusiness dlob
			ON dlob.DimLineOfBusinessID = x.DimLineOfBusinessID
		INNER JOIN EDW_PREPROD.assumed.DimClaimTransaction dct
			ON dct.DimClaimTransactionID = x.DimClaimTransactionID
		LEFT JOIN (
			EDW_PREPROD.dbo.T_Code_History otch
			INNER JOIN #TCodeRevisionExASLOB otcr
				ON otcr.ID = otch.ID
			)
			ON otch.Contract_NBR = dc.CONTRACT_NBR
			AND otch.lob_name = dlob.LineOfBusinessName
			AND otch.END_DATE > ap.OffsetAccountingEndDate
			AND otcr.START_DATE < ap.OffsetAccountingEndDate
		LEFT JOIN (
			EDW_PREPROD.dbo.T_Code_History tch
			INNER JOIN #TCodeRevisionExASLOB tcr
				ON tcr.ID = tch.ID
			)
			ON tch.Contract_NBR = dc.CONTRACT_NBR
			AND tch.lob_name = dlob.LineOfBusinessName
			AND tch.END_DATE > prm.CurrentOffsetAccountingEndDate
			AND tcr.START_DATE < prm.CurrentOffsetAccountingEndDate
		LEFT JOIN (
			EDW_PREPROD.dbo.TIRS_CATCODE_HISTORY otcat
			INNER JOIN #CatCodeRevisionExCatCodeCatKey occr
				ON occr.ID = otcat.ID
			)
			ON otcat.TIRS_CLM_CD = dct.ClaimTransactionCode
			AND otcat.END_DATE > ap.OffsetAccountingEndDate
			AND otcat.START_DATE < ap.OffsetAccountingEndDate
		LEFT JOIN (
			EDW_PREPROD.dbo.TIRS_CATCODE_HISTORY tcat
			INNER JOIN #CatCodeRevisionExCatCodeCatKey ccr
				ON ccr.ID = tcat.ID
			)
			ON tcat.TIRS_CLM_CD = dct.ClaimTransactionCode
			AND tcat.END_DATE > prm.CurrentOffsetAccountingEndDate
			AND tcat.START_DATE < prm.CurrentOffsetAccountingEndDate

		INSERT INTO #Timings SELECT SYSDATETIME(), 'Created #DetectReversalAdjustment', @@ERROR

		--------------------------------------------------------------------------------
		-- FactClaim INSERT 1 (Reversals)
		--------------------------------------------------------------------------------	
		INSERT INTO assumed.FactClaim
		(SourceSystemKey
		,DimTransactionTypeID
		,DimContractID
		,Ceded_DimContractID
		,DimClaimTransactionID
		,DimDueDateID
		,DimFromDateID
		,DimToDateID
		,Intended_DimAccountingPeriodID
		,Actual_DimAccountingPeriodID
		,DimAccidentYearID
		,Intended_DimAccountingID
		,DimAccountingID
		,DimAdjustmentTypeID
		,Orig_DimCurrencyID
		,Settl_DimCurrencyID
		,DimLineOfBusinessID
		,OrigRpt1_DimExchangeRateID
		,OrigRpt2_DimExchangeRateID
		,SettlRpt1_DimExchangeRateID
		,SettlRpt2_DimExchangeRateID
		,DimParticipantID
		,DimMeasureID
		,DimPayeeID
		,DimDocumentID
		,Amount
		,AmountUSD
		,CreatedDate
		,ReversalOfFactClaimID
		)
		SELECT SourceSystemKey = t.SourceSystemKey
			,DimTransactionTypeID = t.DimTransactionTypeID
			,DimContractID = t.DimContractID
			,Ceded_DimContractID = t.Ceded_DimContractID
			,DimClaimTransactionID = t.DimClaimTransactionID
			,DimDueDateID = t.DimDueDateID
			,DimFromDateID = t.DimFromDateID
			,DimToDateID =t.DimToDateID
			,Intended_DimAccountingPeriodID = t.Intended_DimAccountingPeriodID
			,Actual_DimAccountingPeriodID = COALESCE(aapo.Actual_DimAccountingPeriodID, CASE
													WHEN dap.AccountingPeriodDate < prm.CurrentAccountingPeriod THEN prm.Current_DimAccountingPeriodID
													ELSE t.Intended_DimAccountingPeriodID
													END)
			,DimAccidentYearID = t.DimAccidentYearID
			,Intended_DimAccountingID = t.Intended_DimAccountingID
			,DimAccountingID = CASE WHEN IsAdjustment = 0 THEN t.DimAccountingID ELSE pair.DimAccountingID END
			,DimAdjustmentTypeID = t.DimAdjustmentTypeID
			,Orig_DimCurrencyID = t.Orig_DimCurrencyID
			,Settl_DimCurrencyID = t.Settl_DimCurrencyID
			,DimLineOfBusinessID = t.DimLineOfBusinessID
			,OrigRpt1_DimExchangeRateID = t.OrigRpt1_DimExchangeRateID
			,OrigRpt2_DimExchangeRateID = t.OrigRpt2_DimExchangeRateID
			,SettlRpt1_DimExchangeRateID = t.SettlRpt1_DimExchangeRateID
			,SettlRpt2_DimExchangeRateID = t.SettlRpt2_DimExchangeRateID
			,DimParticipantID = t.DimParticipantID
			,DimMeasureID = t.DimMeasureID
			,DimPayeeID = t.DimPayeeID
			,DimDocumentID = t.DimDocumentID
			,Amount = -t.Amount
			,AmountUSD = -t.AmountUSD
			,CreatedDate = prm.ProcessingDate
			,ReversalOfFactClaimID = t.FactClaimID
		FROM (
			SELECT t.*
			FROM assumed.FactClaim t
			LEFT JOIN assumed.FactClaim r
				ON r.ReversalOfFactClaimID = t.FactClaimID
			WHERE r.ReversalOfFactClaimID IS NULL
				AND t.ReversalOfFactClaimID IS NULL
			) t
		CROSS JOIN #Parameters prm
		INNER JOIN EDW_PREPROD.assumed.DimContract dc
			ON dc.DimContractID = t.DimContractID
		INNER JOIN #ContractFilter cf
			ON cf.CONTRACT_NBR = dc.CONTRACT_NBR COLLATE DATABASE_DEFAULT
		LEFT JOIN #LoadClaim s
			ON COALESCE(s.SourceSystemKey, -1) = COALESCE(t.SourceSystemKey, -1)
			AND s.DimTransactionTypeID = t.DimTransactionTypeID
			AND s.DimContractID = t.DimContractID
			AND s.Ceded_DimContractID = t.Ceded_DimContractID
			AND s.DimClaimTransactionID = t.DimClaimTransactionID
			AND s.DimDueDateID = t.DimDueDateID
			AND s.DimFromDateID = t.DimFromDateID
			AND s.DimToDateID =t.DimToDateID
			AND s.Intended_DimAccountingPeriodID = t.Intended_DimAccountingPeriodID
			AND s.DimAccidentYearID = t.DimAccidentYearID
			AND s.Intended_DimAccountingID = t.Intended_DimAccountingID
			AND s.DimAdjustmentTypeID = t.DimAdjustmentTypeID
			AND s.Orig_DimCurrencyID = t.Orig_DimCurrencyID
			AND s.Settl_DimCurrencyID = t.Settl_DimCurrencyID
			AND s.DimLineOfBusinessID = t.DimLineOfBusinessID
			AND s.OrigRpt1_DimExchangeRateID = t.OrigRpt1_DimExchangeRateID
			AND s.OrigRpt2_DimExchangeRateID = t.OrigRpt2_DimExchangeRateID
			AND s.SettlRpt1_DimExchangeRateID = t.SettlRpt1_DimExchangeRateID
			AND s.SettlRpt2_DimExchangeRateID = t.SettlRpt2_DimExchangeRateID
			AND s.DimParticipantID = t.DimParticipantID
			AND s.DimPayeeID = t.DimPayeeID
			AND s.DimMeasureID = t.DimMeasureID
			AND s.DimDocumentID = t.DimDocumentID
		LEFT JOIN #ActualAccountingPeriodOverride aapo
			ON aapo.Intended_DimAccountingPeriodID = t.Intended_DimAccountingPeriodID
		INNER JOIN #DetectReversalAdjustment dra
			ON dra.DimContractID = t.DimContractID
			AND dra.DimClaimTransactionID = t.DimClaimTransactionID
			AND dra.DimLineOfBusinessID = t.DimLineOfBusinessID
			AND dra.Intended_DimAccountingPeriodID = t.Intended_DimAccountingPeriodID
		INNER JOIN EDW_PREPROD.assumed.DimAccountingPeriod dap
			ON dap.DimAccountingPeriodID = t.Intended_DimAccountingPeriodID
		INNER JOIN #DimAccountingPairing pair
			ON pair.Intended_DimAccountingID = t.Intended_DimAccountingID
		WHERE s.ClaimLoadWideID IS NULL
		OPTION (MAXDOP 1)


		DECLARE @ReversalCount INT = @@ROWCOUNT
		INSERT INTO #Timings SELECT SYSDATETIME(), 'Perform reversals in assumed.FactClaim', @@ERROR
		--------------------------------------------------------------------------------
		--#ConsolidatedTarget
		--------------------------------------------------------------------------------
		DROP TABLE IF EXISTS #ConsolidatedTarget

		SELECT t.SourceSystemKey
			,t.DimTransactionTypeID
			,t.DimContractID
			,t.Ceded_DimContractID
			,t.DimClaimTransactionID
			,t.DimDueDateID
			,t.DimFromDateID
			,t.DimToDateID
			,t.Intended_DimAccountingPeriodID
			,t.DimAccidentYearID
			,t.Intended_DimAccountingID
			,t.DimAdjustmentTypeID
			,t.Orig_DimCurrencyID
			,t.Settl_DimCurrencyID
			,t.DimLineOfBusinessID
			,t.OrigRpt1_DimExchangeRateID
			,t.OrigRpt2_DimExchangeRateID
			,t.SettlRpt1_DimExchangeRateID
			,t.SettlRpt2_DimExchangeRateID
			,t.DimParticipantID
			,t.DimPayeeID
			,t.DimMeasureID
			,t.DimDocumentID
			,Amount = SUM(t.Amount)
			,AmountUSD = SUM(t.AmountUSD)
		INTO #ConsolidatedTarget
		FROM assumed.FactClaim t
		CROSS JOIN #Parameters prm
		INNER JOIN EDW_PREPROD.assumed.DimContract dac
			ON dac.DimContractID = t.DimContractID
		INNER JOIN #ContractFilter cf
			ON cf.CONTRACT_NBR = dac.CONTRACT_NBR COLLATE DATABASE_DEFAULT
		GROUP BY t.SourceSystemKey
			,t.DimTransactionTypeID
			,t.DimContractID
			,t.Ceded_DimContractID
			,t.DimClaimTransactionID
			,t.DimDueDateID
			,t.DimFromDateID
			,t.DimToDateID
			,t.Intended_DimAccountingPeriodID
			,t.DimAccidentYearID
			,t.Intended_DimAccountingID
			,t.DimAdjustmentTypeID
			,t.Orig_DimCurrencyID
			,t.Settl_DimCurrencyID
			,t.DimLineOfBusinessID
			,t.OrigRpt1_DimExchangeRateID
			,t.OrigRpt2_DimExchangeRateID
			,t.SettlRpt1_DimExchangeRateID
			,t.SettlRpt2_DimExchangeRateID
			,t.DimParticipantID
			,t.DimPayeeID
			,t.DimMeasureID
			,t.DimDocumentID


		INSERT INTO #Timings SELECT SYSDATETIME(), 'Created #ConsolidatedTarget', @@ERROR

		DROP TABLE IF EXISTS #DetectAdjustment

		SELECT x.DimContractID
			,x.DimClaimTransactionID
			,x.DimLineOfBusinessID
			,x.Intended_DimAccountingPeriodID
			,IsAdjustment = CAST(CASE WHEN COALESCE(tcr.ID, -1) = COALESCE(otcr.ID, -1) AND COALESCE(ccr.ID, -1) = COALESCE(occr.ID, -1) THEN 0 ELSE 1 END AS BIT)
		INTO #DetectAdjustment
		FROM (
			SELECT DISTINCT s.DimContractID
				,s.DimClaimTransactionID
				,s.DimLineOfBusinessID
				,s.Intended_DimAccountingPeriodID
			FROM #LoadClaim s
			INNER JOIN EDW_PREPROD.assumed.DimContract dc
				ON dc.DimContractID = s.DimContractID
			INNER JOIN #ContractFilter cf
				ON cf.CONTRACT_NBR = dc.CONTRACT_NBR COLLATE DATABASE_DEFAULT
			) x
		CROSS JOIN #Parameters prm
		INNER JOIN EDW_PREPROD.assumed.DimContract dc
			ON dc.DimContractID = x.DimContractID
		INNER JOIN EDW_PREPROD.assumed.DimAccountingPeriod dap
			ON dap.DimAccountingPeriodID = x.Intended_DimAccountingPeriodID
		INNER JOIN #AccountingPeriod ap
			ON ap.AccountingPeriodDate = dap.AccountingPeriodDate
		INNER JOIN EDW_PREPROD.assumed.DimLineOfBusiness dlob
			ON dlob.DimLineOfBusinessID = x.DimLineOfBusinessID
		INNER JOIN EDW_PREPROD.assumed.DimClaimTransaction dct
			ON dct.DimClaimTransactionID = x.DimClaimTransactionID
		LEFT JOIN (
			EDW_PREPROD.dbo.T_Code_History otch
			INNER JOIN #TCodeRevisionExASLOB otcr
				ON otcr.ID = otch.ID
			)
			ON otch.Contract_NBR = dc.CONTRACT_NBR
			AND otch.lob_name = dlob.LineOfBusinessName
			AND otch.END_DATE > ap.OffsetAccountingEndDate
			AND otcr.START_DATE < ap.OffsetAccountingEndDate
		LEFT JOIN (
			EDW_PREPROD.dbo.T_Code_History tch
			INNER JOIN #TCodeRevisionExASLOB tcr
				ON tcr.ID = tch.ID
			)
			ON tch.Contract_NBR = dc.CONTRACT_NBR
			AND tch.lob_name = dlob.LineOfBusinessName
			AND tch.END_DATE > prm.CurrentOffsetAccountingEndDate
			AND tcr.START_DATE < prm.CurrentOffsetAccountingEndDate
		LEFT JOIN (
			EDW_PREPROD.dbo.TIRS_CATCODE_HISTORY otcat
			INNER JOIN #CatCodeRevisionExCatCodeCatKey occr
				ON occr.ID = otcat.ID
			)
			ON otcat.TIRS_CLM_CD = dct.ClaimTransactionCode
			AND otcat.END_DATE > ap.OffsetAccountingEndDate
			AND otcat.START_DATE < ap.OffsetAccountingEndDate
		LEFT JOIN (
			EDW_PREPROD.dbo.TIRS_CATCODE_HISTORY tcat
			INNER JOIN #CatCodeRevisionExCatCodeCatKey ccr
				ON ccr.ID = tcat.ID
			)
			ON tcat.TIRS_CLM_CD = dct.ClaimTransactionCode
			AND tcat.END_DATE > prm.CurrentOffsetAccountingEndDate
			AND tcat.START_DATE < prm.CurrentOffsetAccountingEndDate

		INSERT INTO #Timings SELECT SYSDATETIME(), 'Created #DetectAdjustment', @@ERROR

		--------------------------------------------------------------------------------
		-- FactClaim INSERT 2 (new data)
		--------------------------------------------------------------------------------
		INSERT INTO assumed.FactClaim
		(SourceSystemKey
		,DimTransactionTypeID
		,DimContractID
		,Ceded_DimContractID
		,DimClaimTransactionID
		,DimDueDateID
		,DimFromDateID
		,DimToDateID
		,Intended_DimAccountingPeriodID
		,Actual_DimAccountingPeriodID
		,DimAccidentYearID
		,Intended_DimAccountingID
		,DimAccountingID
		,DimAdjustmentTypeID
		,Orig_DimCurrencyID
		,Settl_DimCurrencyID
		,DimLineOfBusinessID
		,OrigRpt1_DimExchangeRateID
		,OrigRpt2_DimExchangeRateID
		,SettlRpt1_DimExchangeRateID
		,SettlRpt2_DimExchangeRateID
		,DimParticipantID
		,DimPayeeID
		,DimMeasureID
		,DimDocumentID
		,Amount
		,AmountUSD
		,CreatedDate
		)
		SELECT SourceSystemKey = s.SourceSystemKey
			,DimTransactionTypeID = s.DimTransactionTypeID
			,DimContractID = s.DimContractID
			,Ceded_DimContractID = s.Ceded_DimContractID
			,DimClaimTransactionID = s.DimClaimTransactionID
			,DimDueDateID = s.DimDueDateID
			,DimFromDateID = s.DimFromDateID
			,DimToDateID = s.DimToDateID
			,Intended_DimAccountingPeriodID = s.Intended_DimAccountingPeriodID
			,Actual_DimAccountingPeriodID = COALESCE(aapo.Actual_DimAccountingPeriodID, CASE
				WHEN dap.AccountingPeriodDate < prm.CurrentAccountingPeriod THEN prm.Current_DimAccountingPeriodID
				ELSE s.Intended_DimAccountingPeriodID
				END)
			,DimAccidentYearID = s.DimAccidentYearID
			,Intended_DimAccountingID = s.Intended_DimAccountingID
			,DimAccountingID = CASE WHEN da.IsAdjustment = 0 THEN s.Intended_DimAccountingID ELSE pair.DimAccountingID END
			,DimAdjustmentTypeID = s.DimAdjustmentTypeID
			,Orig_DimCurrencyID = s.Orig_DimCurrencyID
			,Settl_DimCurrencyID = s.Settl_DimCurrencyID
			,DimLineOfBusinessID = s.DimLineOfBusinessID
			,OrigRpt1_DimExchangeRateID = s.OrigRpt1_DimExchangeRateID
			,OrigRpt2_DimExchangeRateID = s.OrigRpt2_DimExchangeRateID
			,SettlRpt1_DimExchangeRateID = s.SettlRpt1_DimExchangeRateID
			,SettlRpt2_DimExchangeRateID = s.SettlRpt2_DimExchangeRateID
			,DimParticipantID = s.DimParticipantID
			,DimPayeeID = s.DimPayeeID
			,DimMeasureID = s.DimMeasureID
			,DimDocumentID = s.DimDocumentID
			,Amount = COALESCE(s.Amount, 0) - COALESCE(t.Amount, 0)
			,AmountUSD = COALESCE(s.AmountUSD, 0) - COALESCE(t.AmountUSD, 0)
			,CreatedDate = prm.ProcessingDate
		FROM #LoadClaim s
		LEFT JOIN #ConsolidatedTarget t
			ON COALESCE(t.SourceSystemKey, -1) = COALESCE(s.SourceSystemKey, -1)
			AND t.DimTransactionTypeID = s.DimTransactionTypeID
			AND t.DimContractID = s.DimContractID
			AND t.Ceded_DimContractID = s.Ceded_DimContractID
			AND t.DimClaimTransactionID = s.DimClaimTransactionID
			AND t.DimDueDateID = s.DimDueDateID
			AND t.DimFromDateID = s.DimFromDateID
			AND t.DimToDateID = s.DimToDateID
			AND t.Intended_DimAccountingPeriodID = s.Intended_DimAccountingPeriodID
			AND t.DimAccidentYearID = s.DimAccidentYearID
			AND t.Intended_DimAccountingID = s.Intended_DimAccountingID
			AND t.DimAdjustmentTypeID = s.DimAdjustmentTypeID
			AND t.Orig_DimCurrencyID = s.Orig_DimCurrencyID
			AND t.Settl_DimCurrencyID = s.Settl_DimCurrencyID
			AND t.DimLineOfBusinessID = s.DimLineOfBusinessID
			AND t.OrigRpt1_DimExchangeRateID = s.OrigRpt1_DimExchangeRateID
			AND t.OrigRpt2_DimExchangeRateID = s.OrigRpt2_DimExchangeRateID
			AND t.SettlRpt1_DimExchangeRateID = s.SettlRpt1_DimExchangeRateID
			AND t.SettlRpt2_DimExchangeRateID = s.SettlRpt2_DimExchangeRateID
			AND t.DimParticipantID = s.DimParticipantID
			AND t.DimPayeeID = s.DimPayeeID
			AND t.DimMeasureID = s.DimMeasureID
			AND t.DimDocumentID = s.DimDocumentID
		CROSS JOIN #Parameters prm
		INNER JOIN EDW_PREPROD.assumed.DimAccountingPeriod dap
			ON dap.DimAccountingPeriodID = s.Intended_DimAccountingPeriodID
		INNER JOIN #DetectAdjustment da
			ON da.DimContractID = s.DimContractID
			AND da.DimClaimTransactionID = s.DimClaimTransactionID
			AND da.DimLineOfBusinessID = s.DimLineOfBusinessID
			AND da.Intended_DimAccountingPeriodID = s.Intended_DimAccountingPeriodID
		INNER JOIN #AccountingPeriod ap
			ON ap.AccountingPeriodDate = dap.AccountingPeriodDate
		INNER JOIN EDW_PREPROD.assumed.DimContract dc
			ON dc.DimContractID = s.DimContractID
		INNER JOIN #DimAccountingPairing pair
			ON pair.Intended_DimAccountingID = s.Intended_DimAccountingID
		LEFT JOIN #ActualAccountingPeriodOverride aapo
			ON aapo.Intended_DimAccountingPeriodID = s.Intended_DimAccountingPeriodID
		WHERE ABS(COALESCE(s.Amount, 0) - COALESCE(t.Amount, 0)) >= 0.01
			OR ABS(COALESCE(s.AmountUSD, 0) - COALESCE(t.AmountUSD, 0)) >= 0.01
		OPTION (MAXDOP 1)


		DECLARE @TransactionCount INT = @@ROWCOUNT
		INSERT INTO #Timings SELECT SYSDATETIME(), 'Appended transactions to assumed.FactClaim', @@ERROR

		--------------------------------------------------------------------------------	
		-- FactClaimUncoded UPDATE (recheck uncoded values and close EndDate for unactual records)
		--------------------------------------------------------------------------------
		UPDATE u
		   SET EndDate = prm.ProcessingDate
		  FROM EDW_Staging.Assumed.FactClaimUncoded u
		 CROSS JOIN #Parameters	prm 
		 WHERE prm.ProcessingDate BETWEEN u.StartDate AND u.EndDate
		   AND NOT EXISTS (SELECT * 
							 FROM EDW_PREPROD.assumed.FactClaim	f
							WHERE f.ReversalOfFactClaimID IS NULL
								AND NOT EXISTS (SELECT * FROM EDW_PREPROD.assumed.FactClaim rr WHERE f.FactClaimID = rr.ReversalOfFactClaimID)
								----
								AND ISNULL(u.SourceSystemKey,-1)	= ISNULL(f.SourceSystemKey,-1)
								AND u.DimContractID					= f.DimContractID 
								AND u.Ceded_DimContractID			= f.Ceded_DimContractID
								AND u.DimTransactionTypeID			= f.DimTransactionTypeID
								AND u.DimClaimTransactionID			= f.DimClaimTransactionID
								AND u.DimDueDateID					= f.DimDueDateID				
								AND u.Intended_DimAccountingPeriodID= f.Intended_DimAccountingPeriodID
								AND u.DimAccidentYearID				= f.DimAccidentYearID		
								AND u.Intended_DimAccountingID		= f.Intended_DimAccountingID
								AND u.DimAccountingID				= f.DimAccountingID		
								AND u.DimAdjustmentTypeID			= f.DimAdjustmentTypeID
								AND u.Orig_DimCurrencyID			= f.Orig_DimCurrencyID
								AND u.Settl_DimCurrencyID			= f.Settl_DimCurrencyID
								AND u.DimLineOfBusinessID			= f.DimLineOfBusinessID
								AND u.OrigRpt1_DimExchangeRateID	= f.OrigRpt1_DimExchangeRateID
								AND u.OrigRpt2_DimExchangeRateID	= f.OrigRpt2_DimExchangeRateID
								AND u.SettlRpt1_DimExchangeRateID	= f.SettlRpt1_DimExchangeRateID
								AND u.SettlRpt2_DimExchangeRateID	= f.SettlRpt2_DimExchangeRateID
								AND u.DimParticipantID				= f.DimParticipantID
								AND u.DimFromDateID					= f.DimFromDateID
								AND u.DimToDateID					= f.DimToDateID
								AND u.DimPayeeID					= f.DimPayeeID	
								AND u.DimDocumentID					= f.DimDocumentID	
								AND u.DimMeasureID					= f.DimMeasureID
							)

		INSERT INTO #Timings SELECT SYSDATETIME(), 'Close unactual uncoded entries in EDW_Staging.assumed.FactClaimUncoded', @@ERROR
		COMMIT TRANSACTION

	-------------------------------------------------------
	-- Update etl_controller, flag SUCCESS
	-------------------------------------------------------
	SET @v_RowsProcessed	= @ReversalCount + @TransactionCount
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
		DECLARE @v_ErrorDescription	VARCHAR(800)= LEFT(CONCAT('Error: ', ERROR_NUMBER(), ' - ', ERROR_MESSAGE(), '; ', 'Occurred in procedure: ' + ERROR_PROCEDURE() + ', ', 'Line ', ERROR_LINE()), 800)
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
