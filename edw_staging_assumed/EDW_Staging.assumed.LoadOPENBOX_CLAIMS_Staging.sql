-- Database: EDW_Staging
-- Schema: assumed
-- Procedure: LoadOPENBOX_CLAIMS_Staging

CREATE   PROCEDURE [assumed].[LoadOPENBOX_CLAIMS_Staging]
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
	--#OpenBox_UW_Stage
	----------------------------------------------------------------
	DROP TABLE IF EXISTS #OpenBox_CLAIMS_Stage

	CREATE TABLE #OpenBox_CLAIMS_Stage 
	(
		TREATY_NBR varchar(5) NULL,
		UNDERWRITING_YEAR varchar(4) NULL,
		Ceded_CONTRACT_NBR varchar(9) NULL,
		CONTRACT_NBR varchar(20) NULL,
		SourceSystemKey bigint NULL,
		TransactionTypeCode varchar(10) NULL,
		TransactionTypeCategory varchar(30) NULL,
		DueDate date NULL,
		acct_from_dt date NULL,
		acct_to_dt date NULL,
		doc_key varchar(25) NULL,
		ORIGCURR_CD varchar(3) NULL,
		TIRS_ORIG_CURR_CD varchar(3) NULL,
		SETTL_CURR_CD varchar(3) NULL,
		TIRS_ORIG_CURR_NAME varchar(50) NULL,
		lob_name varchar(100) NULL,
		AccidentYear char(4) NULL,
		aslob varchar(20) NULL,
		TIRS_UW_ASSM_CEDED_NAME varchar(7) NULL,
		reg_date date NULL,
		Claim_NBR varchar(10) NULL,
		TIRS_CLM_CD varchar(20) NULL,
		CatCode varchar(10) NULL,
		CAT_KEY varchar(20) NULL,
		solvency_II_regulatory_key int NULL,
		CLAIMLOSSDATE datetime NULL,
		bill_co_br_key int NULL,

		Summable_LOSS_PAID money NULL,
		SUMMABLE_LOSS_PAID_USD money NULL,
		
		SUMMABLE_LAE money NULL,
		SUMMABLE_LAE_USD money NULL,
		SUMMABLE_OS_LOSS money NULL,
		SUMMABLE_OS_LOSS_USD money NULL,
		Source varchar(20) NULL,
		adjustmenttype varchar(100) NULL,
		financial_lob varchar(10) NULL,
		T7_CODE varchar(20) NULL,
		T8_CODE varchar(20) NULL,
		T9_CODE char(1) NULL,
		InsurerCode varchar(20) NULL,
		CLMS_PROCSS_CLM_DEPT char(1) NULL,
		ICP_CEDED_FLG char(1) NULL,
		RPT_OFF_NAME varchar(40) NULL,
		ActuarialLob varchar(100) NULL,
		MBU char(3) NULL,
		L01 char(3) NULL,
		L02 char(3) NULL,
		L03 varchar(7) NULL,
		L04 varchar(20) NULL,
		L06 char(4) NULL,
		L07 varchar(15) NULL,
		L10 varchar(10) NULL,
		GD1 varchar(10) NULL,
		RPTCURR1_CD char(3) NULL,
		RPTCURR2_CD char(3) NULL,
		RPTCURR1 float NULL,
		RPTCURR2 float NULL,
		SETTL_RPTCURR1 float NULL,
		SETTL_RPTCURR2 float NULL,
		Summable_SETTL_LOSS_PAID money NULL,
		Summable_SETTL_LOSS_PAID_USD money NULL,
		Summable_SETTL_LAE money NULL,
		Summable_SETTL_LAE_USD money NULL,
		-------------------------------				
		[DataHash] [varbinary](500) NULL
	)	
	----------------------------------------------------------------------------------
	--#OpenBox_CLAIMS_Stage
	----------------------------------------------------------------------------------
	INSERT INTO #OpenBox_CLAIMS_Stage
	(
	   TREATY_NBR
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
      ,ActuarialLob
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
      ,SUMMABLE_LAE
      ,SUMMABLE_LAE_USD
      ,SUMMABLE_OS_LOSS
      ,SUMMABLE_OS_LOSS_USD
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
	)    	  
		SELECT TREATY_NBR = 'OB'
		,UNDERWRITING_YEAR = yoa
		,Ceded_CONTRACT_NBR = NULL
		,CONTRACT_NBR = M.contract_NBR
		,SourceSystemKey = 30000000000 + R.lClaimMovementKey
		,TransactionTypeCode = ISNULL(tt.sTransactionCode,'N/A')
		,TransactionTypeCategory = 'Claim Transaction Type'
		,DueDate = cmm.dtMovementDate
		,acct_from_dt = NULL
		,acct_to_dt = NULL
		,doc_key = NULL
		,ORIGCURR_CD = R.OrigCurrCode
		,TIRS_ORIG_CURR_CD = R.OrigCurrCode
		,SETTL_CURR_CD = ISNULL(R.SettCurrCode, '')
		,TIRS_ORIG_CURR_NAME = ROE.CURRENCY_NAME
		,lob_name = ISNULL(M.sub_dept_name,'N/A')
		,ActuarialLob = M.ActuarialLob
		,AccidentYear = ISNULL(YEAR(dateofloss), yoa)
		,aslob = 0
		,TIRS_UW_ASSM_CEDED_NAME = 'N/A'
		,reg_date = accounting_Period_date
		,Claim_NBR = 'N/A'
		,TIRS_CLM_CD = R.lClaimMovementKey
		,CatCode = NULL
		,CAT_KEY = NULLIF(CATCODE, '-9999')
		,solvency_II_regulatory_key = solII.solvency_II_regulatory_key
		,CLAIMLOSSDATE = NULL
		,bill_co_br_key = NULL
		,SUMMABLE_LOSS_PAID = CAST(SUM(CASE WHEN ClaimMovementTypeCode != 'ALA' THEN totalPaidOriginal ELSE 0 END) AS MONEY)
		,SUMMABLE_LOSS_PAID_USD = CAST(SUM(CASE WHEN ClaimMovementTypeCode != 'ALA' THEN totalPaidUSD ELSE 0 END) AS MONEY)		
		,SUMMABLE_LAE = CAST(SUM(CASE WHEN ClaimMovementTypeCode = 'ALA' THEN totalPaidOriginal ELSE 0 END) AS MONEY)
		,SUMMABLE_LAE_USD = CAST(SUM(CASE WHEN ClaimMovementTypeCode = 'ALA' THEN totalPaidUSD ELSE 0 END) AS MONEY)
		,SUMMABLE_OS_LOSS = CAST(SUM(TOTALOUTSTANDINGOriginal) AS MONEY)
		,SUMMABLE_OS_LOSS_USD = CAST(SUM(TOTALOUTSTANDINGUSD) AS MONEY)
		,Source = 'OPENBOX'
		,AdjustmentType = 'N/A'
		,financial_lob = M.financial_lob
		,t7_code = M.T7_Code
		,t8_code = M.T8_Code
		,t9_code = M.t9_code
		,Insurercode = M.InsurerCode
		,CLMS_PROCSS_CLM_DEPT = NULL
		,ICP_CEDED_FLG = M.ICPFLAG
		,RPT_OFF_NAME = M.RPT_OFF_NAME
		,MBU = 'LYC'
		,L01 = 'LSL'
		,L02 = LMAP.L02
		,L03 = LMAP.l03
		,L04 = COALESCE(NULLIF(DL4M.l4, ''), r.YOA)
		,L06 = 'LLON'
		,L07 = SOLII_L.Fairfax_LOB_LCode + ISNULL(CM.FairFaxAbbrv_Code, 'ZZZ') COLLATE database_default
		,l10 = yoa
		,gd1 = 'OPENBOX'
		,RPTCURR1_CD = 'GBP'
		,RPTCURR2_CD = NULL
		,RPTCURR1 = CAST(IIF(R.OrigCurrCode = 'USD', 1, RA.EXCHANGERATE) * (1 / RT1.EXCHANGERATE) AS FLOAT)
		,RPTCURR2 = NULL
		,SETTL_RPTCURR1 = CAST(IIF(R.SettCurrCode = 'USD', 1, SRA.EXCHANGERATE) * (1 / SRT1.EXCHANGERATE) AS FLOAT)
		,SETTL_RPTCURR2 = NULL			
		,Summable_SETTL_LOSS_PAID = CAST(SUM(CASE WHEN ClaimMovementTypeCode != 'ALA' THEN TotalPaidSettlement ELSE 0 END) AS MONEY)
		,Summable_SETTL_LOSS_PAID_USD = CAST(SUM(CASE WHEN r.ClaimMovementTypeCode != 'ALA' AND NULLIF(r.TotalPaidSettlement, 0) IS NOT NULL THEN r.TotalPaidSettlement * der_su.ExchangeRate ELSE 0 END) AS MONEY)
		,Summable_SETTL_LAE = CAST(SUM(CASE WHEN ClaimMovementTypeCode = 'ALA' THEN TotalPaidSettlement ELSE 0 END) AS MONEY)
		,Summable_SETTL_LAE_USD = CAST(SUM(CASE WHEN r.ClaimMovementTypeCode = 'ALA' AND NULLIF(r.TotalPaidSettlement, 0) IS NOT NULL THEN r.TotalPaidSettlement * der_su.ExchangeRate ELSE 0 END) AS MONEY)


	FROM EDW_PREPROD.lloyds.TBL_CLAIM_LLYDS R
	INNER JOIN SRC_LLOYDS_DB.dbo.ClaimMovement cmm
	ON cmm.lClaimMovementKey = r.lClaimMovementKey
	LEFT JOIN SRC_LLOYDS_DB.dbo.TRANSACTIONTYPE tt
	ON tt.lTransactionTypeKey = cmm.lTransactionTypeKey
	LEFT JOIN (
		SELECT DISTINCT plcy_SRC = plcy_SRC
			,RPT_OFF_NAME = RPT_OFF_NAME
			,DIV_NAME = DIV_NAME
			,SUB_DEPT_CD = SUB_DEPT_CD
			,PRO_RATA_XOL_NAME = PRO_RATA_XOL_NAME
			,TRTY_FAC_NAME = TRTY_FAC_NAME
			,DEPT_NAME = DEPT_NAME
			,DEPT_CD = DEPT_CD
			,ICPFLAG = ICPFLAG
			,CEDNG_COMPANY_NAME = CEDNG_COMPANY_NAME
			,contract_NBR = contract_NBR
			,Contract_Reference = Contract_Reference
			,actuariallob = actuariallob
			,sub_dept_name = sub_dept_name
			,financial_lob = financial_lob
			,T7_Code = SunBranchCode
			,T8_Code = sif_OIF
			,t9_code = t9_code
			,insurercode = insurercode
			,INCEPT_DT = INCEPT_DT
		FROM EDW_PREPROD.dbo.MAP_CONTRACT_EDW mce
		WHERE plcy_SRC = 'OPENBOX'
		) M
		ON M.Contract_Reference = R.policyNumber
	--INNER JOIN #ContractFilter cf
		--ON cf.Contract_NBR = m.contract_NBR COLLATE DATABASE_DEFAULT
	LEFT JOIN EDW_PREPROD.dbo.solvency_II_regulatory_etl solII
		ON solII.source = M.PLCY_SRC
			AND ISNULL(solII.branch_name, 'Uncoded') = ISNULL(M.RPT_OFF_NAME, 'Uncoded')
			AND ISNULL(solII.product_group_name, 'Uncoded') = ISNULL(M.DIV_NAME, 'Uncoded')
			AND ISNULL(solII.product_department_name, 'Uncoded') = ISNULL(M.DEPT_NAME, 'Uncoded')
			AND ISNULL(solII.product_department_code, 'Uncoded') = ISNULL(M.DEPT_CD, 'Uncoded')
			AND ISNULL(solII.lob_name, 'Uncoded') = ISNULL(M.SUB_DEPT_NAME, 'Uncoded')
			AND ISNULL(solII.lob_code, 'Uncoded') = ISNULL(M.SUB_DEPT_CD, 'Uncoded')
			AND ISNULL(solII.prorata_or_xol, 'Uncoded') = ISNULL(M.PRO_RATA_XOL_NAME, 'Uncoded')
			AND ISNULL(solII.treaty_or_fav, 'Uncoded') = ISNULL(M.TRTY_FAC_NAME, 'Uncoded')
			AND ISNULL(solII.property_or_casualty, 'Uncoded') = ISNULL(CASE WHEN M.DIV_NAME LIKE '%property%' THEN 'PROPERTY' WHEN M.DIV_NAME LIKE '%marine%' THEN 'PROPERTY' ELSE 'CASUALTY' END, 'Uncoded')
			AND solII.assumed_or_direct = 'assumed'
			AND COALESCE(solII.InceptionFrom, M.INCEPT_DT, '1 Jan 1900') <= COALESCE(M.INCEPT_DT, '1 Jan 1900')
			AND COALESCE(solII.InceptionTo, M.INCEPT_DT, '1 Jan 1900') >= COALESCE(M.INCEPT_DT, '1 Jan 1900')
	LEFT JOIN EDW_PREPROD..solvency_II_regulatory_lookup SOLII_L
		ON SOLII_L.solvency_II_regulatory_key = solII.solvency_II_regulatory_key
	LEFT JOIN MDS.MDM.Ceding_Company CM
		ON CM.Code = M.CEDNG_COMPANY_NAME COLLATE database_default
	OUTER APPLY (
		SELECT TOP 1 *
		FROM DM_DataStandard.TIRS.l02_L03_mapping LMAP
		WHERE 1 = 1
			AND ISNULL(NULLIF(CAST(LMAP.rpt_ofc_nm AS VARCHAR(100)), '%'), ISNULL(M.RPT_OFF_NAME COLLATE DATABASE_DEFAULT, '')) = ISNULL(M.RPT_OFF_NAME COLLATE DATABASE_DEFAULT, '')
			AND ISNULL(NULLIF(CAST(LMAP.DIV_NAME AS VARCHAR(100)), '%'), ISNULL(M.DIV_NAME COLLATE DATABASE_DEFAULT, '')) = ISNULL(M.DIV_NAME COLLATE DATABASE_DEFAULT, '')
			AND ISNULL(NULLIF(CAST(LMAP.DEPT_NAME AS VARCHAR(100)), '%'), ISNULL(M.DEPT_NAME COLLATE DATABASE_DEFAULT, '')) = ISNULL(M.DEPT_NAME COLLATE DATABASE_DEFAULT, '')
			AND ISNULL(NULLIF(CAST(LMAP.SUB_DEPT_NAME AS VARCHAR(100)), '%'), ISNULL(M.SUB_DEPT_NAME COLLATE DATABASE_DEFAULT, '')) = ISNULL(M.SUB_DEPT_NAME COLLATE DATABASE_DEFAULT, '')
			AND ISNULL(NULLIF(CAST(LMAP.YearOfAccount AS VARCHAR(100)), '%'), ISNULL(CAST(R.YOA COLLATE DATABASE_DEFAULT AS CHAR(4)), '')) = ISNULL(CAST(R.YOA COLLATE DATABASE_DEFAULT AS CHAR(4)), '')
			AND ISNULL(NULLIF(CAST(LMAP.t9 AS VARCHAR(100)), '%'), ISNULL(M.t9_code COLLATE DATABASE_DEFAULT, '')) = ISNULL(M.t9_code COLLATE DATABASE_DEFAULT, '')
			AND ISNULL(NULLIF(CAST(LMAP.PolicySource AS VARCHAR(100)), '%'), ISNULL(M.PLCY_SRC COLLATE DATABASE_DEFAULT, '')) = ISNULL(M.PLCY_SRC COLLATE DATABASE_DEFAULT, '')
		ORDER BY Priority_Key DESC
		) LMAP
	OUTER APPLY (
		SELECT TOP 1 *
		FROM DM_DataStandard.dbo.L4Mapping DL4M
		WHERE ISNULL(NULLIF(DL4M.accidentyear, '%'), ISNULL(YEAR(R.DateOfLoss), '')) = ISNULL(YEAR(R.DateOfLoss), '')
			AND ISNULL(NULLIF(DL4M.cat_key, '%'), COALESCE(R.CatCode, '')) = COALESCE(R.CatCode, '')
			AND ISNULL(NULLIF(DL4M.Source_System, '%'), 'Openbox') = 'Openbox'
		ORDER BY Priority_Key DESC
		) DL4M
	LEFT JOIN EDW_PREPROD.dbo.LOOKUP_GENIUS_CURRENCYRATES RA
		ON RA.ISOCode COLLATE DATABASE_DEFAULT = R.OrigCurrCode
			AND RA.JoinMonth = FORMAT(accounting_Period_date, 'yyyy/MM', 'en-US')
	LEFT JOIN EDW_PREPROD.dbo.LOOKUP_GENIUS_CURRENCYRATES RT1
		ON RT1.ISOCode COLLATE DATABASE_DEFAULT = 'GBP'
			AND RT1.JoinMonth = FORMAT(accounting_Period_date, 'yyyy/MM', 'en-US')
	LEFT JOIN EDW_PREPROD.dbo.LOOKUP_GENIUS_CURRENCYRATES SRA
		ON SRA.ISOCode COLLATE DATABASE_DEFAULT = R.SettCurrCode
			AND SRA.JoinMonth = FORMAT(accounting_Period_date, 'yyyy/MM', 'en-US')
	LEFT JOIN EDW_PREPROD.dbo.LOOKUP_GENIUS_CURRENCYRATES SRT1
		ON SRT1.ISOCode COLLATE DATABASE_DEFAULT = 'GBP'
			AND SRT1.JoinMonth = FORMAT(accounting_Period_date, 'yyyy/MM', 'en-US')
	LEFT JOIN EDW_PREPROD.assumed.DimExchangeRate der_su
		ON der_su.EndDate = '31 Dec 9999'
		AND der_su.FromCurrency = r.SettCurrCode
		AND der_su.ToCurrency = 'USD'
		AND der_su.AccountingPeriodDate = r.accounting_period_date
	OUTER APPLY (
		SELECT TOP 1 TIRS_CURRENCY_CODE = ROE.TIRS_CURRENCY_CODE
			,CURRENCY_NAME = ROE.CURRENCY_NAME
		FROM EDW_PREPROD.dbo.EDW_TIRS_ROE ROE
		WHERE R.OrigCurrCode = ROE.TIRS_CURRENCY_CODE
		ORDER BY ROE.K1PERIOD_OF_TIME DESC
		) ROE
	WHERE R.businesstype = 'Assumed'
		AND R.PolicySource = 'Openbox'
	GROUP BY M.ActuarialLob
		,M.contract_NBR
		,ISNULL(tt.sTransactionCode,'N/A')
		,cmm.dtMovementDate
		,M.T7_Code
		,yoa
		,ISNULL(YEAR(dateofloss), yoa)
		,solII.solvency_II_regulatory_key
		,dateofloss
		,R.lClaimMovementKey
		,ROE.CURRENCY_NAME
		,M.sub_dept_name
		,SOLII_L.Fairfax_LOB_LCode + ISNULL(CM.FairFaxAbbrv_Code, 'ZZZ') COLLATE database_default
		,accounting_Period_date
		,ISNULL(CONVERT(nvarchar(30), dateofloss, 101), yoa) + ISNULL(CATCODE, '')
		,CATCODE
		,M.financial_lob
		,M.T8_Code
		,M.t9_code
		,M.insurercode
		,M.ICPFLAG
		,LMAP.L02
		,LMAP.L03
		,DL4M.l4
		,CAST(IIF(R.OrigCurrCode = 'USD', 1, RA.EXCHANGERATE) * (1 / RT1.EXCHANGERATE) AS FLOAT)
		,M.RPT_OFF_NAME
		,R.OrigCurrCode
		,R.SettCurrCode
		,CAST(IIF(R.SettCurrCode = 'USD', 1, SRA.EXCHANGERATE) * (1 / SRT1.EXCHANGERATE) AS FLOAT)

 
	----------------------------------------------------------------------------------
	--Populate DataHash
	----------------------------------------------------------------------------------
	UPDATE s
	SET DataHash = HASHBYTES('SHA1',
							CONCAT(  s.TREATY_NBR
							  , '|', s.UNDERWRITING_YEAR
							  , '|', s.Ceded_CONTRACT_NBR
							  , '|', s.CONTRACT_NBR
							  , '|', s.SourceSystemKey
							  , '|', s.TransactionTypeCode
							  , '|', s.TransactionTypeCategory
							  , '|', s.DueDate
							  , '|', s.acct_from_dt
							  , '|', s.acct_to_dt
							  , '|', s.doc_key
							  , '|', s.ORIGCURR_CD
							  , '|', s.TIRS_ORIG_CURR_CD
							  , '|', s.SETTL_CURR_CD
							  , '|', s.TIRS_ORIG_CURR_NAME
							  , '|', s.lob_name
							  , '|', s.ActuarialLob
							  , '|', s.AccidentYear
							  , '|', s.aslob
							  , '|', s.TIRS_UW_ASSM_CEDED_NAME
							  , '|', s.reg_date
							  , '|', s.Claim_NBR
							  , '|', s.TIRS_CLM_CD
							  , '|', s.CatCode
							  , '|', s.CAT_KEY
							  , '|', s.solvency_II_regulatory_key
							  , '|', s.CLAIMLOSSDATE
							  , '|', s.bill_co_br_key
							  , '|', s.Summable_LOSS_PAID
							  , '|', s.SUMMABLE_LOSS_PAID_USD
							  , '|', s.SUMMABLE_LAE
							  , '|', s.SUMMABLE_LAE_USD
							  , '|', s.SUMMABLE_OS_LOSS
							  , '|', s.SUMMABLE_OS_LOSS_USD
							  , '|', s.Source
							  , '|', s.adjustmenttype
							  , '|', s.financial_lob
							  , '|', s.T7_CODE
							  , '|', s.T8_CODE
							  , '|', s.T9_CODE
							  , '|', s.InsurerCode
							  , '|', s.CLMS_PROCSS_CLM_DEPT
							  , '|', s.ICP_CEDED_FLG
							  , '|', s.RPT_OFF_NAME
							  , '|', s.MBU
							  , '|', s.L01
							  , '|', s.L02
							  , '|', s.L03
							  , '|', s.L04
							  , '|', s.L06
							  , '|', s.L07
							  , '|', s.L10
							  , '|', s.GD1
							  , '|', s.RPTCURR1_CD
							  , '|', s.RPTCURR2_CD
							  , '|', s.RPTCURR1
							  , '|', s.RPTCURR2
							  , '|', s.SETTL_RPTCURR1
							  , '|', s.SETTL_RPTCURR2
							  , '|', s.Summable_SETTL_LOSS_PAID
							  , '|', s.Summable_SETTL_LOSS_PAID_USD
							  , '|', s.Summable_SETTL_LAE
							  , '|', s.Summable_SETTL_LAE_USD
					))
	FROM #OpenBox_CLAIMS_Stage s
	----------------------------------------------------------------------------------
	--Populate #ClaimsLoadOperation
	----------------------------------------------------------------------------------
	DROP TABLE IF EXISTS #ClaimsLoadOperation

	CREATE TABLE #ClaimsLoadOperation 
	(
		[CONTRACT_NBR]							VARCHAR(20) COLLATE DATABASE_DEFAULT NOT NULL,
		[UNDERWRITING_YEAR]						VARCHAR(4) COLLATE DATABASE_DEFAULT NOT NULL,
		[reg_date]								DATE NOT NULL,
		[TIRS_ORIG_CURR_CD]						VARCHAR(10) COLLATE DATABASE_DEFAULT NOT NULL,
		[TIRS_UW_ASSM_CEDED_NAME]				VARCHAR(10) COLLATE DATABASE_DEFAULT NOT NULL,
		[lob_name]								VARCHAR(255) COLLATE DATABASE_DEFAULT NOT NULL,
		[ActuarialLob]							VARCHAR(255) NULL,
		[solvency_II_regulatory_key]			INT NULL,
		[TIRS_CLM_CD]							VARCHAR(20),
		[SourceSystemKey]						BIGINT NULL, 
		[Operation]								CHAR(1) NOT NULL,
		UNIQUE([CONTRACT_NBR],[UNDERWRITING_YEAR],[reg_date],[TIRS_ORIG_CURR_CD],[TIRS_UW_ASSM_CEDED_NAME],[lob_name],[ActuarialLob],[solvency_II_regulatory_key]
		,[TIRS_CLM_CD],[SourceSystemKey])
	)
	INSERT INTO #ClaimsLoadOperation
	(
		 [CONTRACT_NBR]				
		,[UNDERWRITING_YEAR]
		,[reg_date]
		,[TIRS_ORIG_CURR_CD]		
		,[TIRS_UW_ASSM_CEDED_NAME]
		,[lob_name]
		,[ActuarialLob]
		,[solvency_II_regulatory_key]
		,[TIRS_CLM_CD]
		,[SourceSystemKey]
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
		,[TIRS_CLM_CD]							= COALESCE(t.TIRS_CLM_CD COLLATE DATABASE_DEFAULT, s.TIRS_CLM_CD COLLATE DATABASE_DEFAULT, '')
		,[SourceSystemKey]						= COALESCE(t.SourceSystemKey, s.SourceSystemKey, -1)
		,[Operation]							= CASE WHEN t.OPENBOX_CLAIMS_stagingID IS NULL THEN 'I' WHEN s.DataHash IS NULL THEN 'D' ELSE 'U' END
	FROM (
		SELECT *
		  FROM assumed.OPENBOX_CLAIMS_staging
		 WHERE EndDate = '9999-12-31'
		) t
	FULL JOIN #OpenBox_CLAIMS_Stage s	ON  s.CONTRACT_NBR										= t.CONTRACT_NBR COLLATE DATABASE_DEFAULT
										AND s.UNDERWRITING_YEAR									= t.UNDERWRITING_YEAR COLLATE DATABASE_DEFAULT
										AND COALESCE(s.reg_date,'1900-01-01')					= COALESCE(t.reg_date,'1900-01-01')
										AND COALESCE(s.TIRS_ORIG_CURR_CD, '^&*')				= COALESCE(t.TIRS_ORIG_CURR_CD, '^&*') COLLATE DATABASE_DEFAULT
										AND COALESCE(s.TIRS_UW_ASSM_CEDED_NAME, '^&*')			= COALESCE(t.TIRS_UW_ASSM_CEDED_NAME, '^&*') COLLATE DATABASE_DEFAULT
										AND COALESCE(s.LOB_NAME, '^&*')							= COALESCE(t.LOB_NAME, '^&*') COLLATE DATABASE_DEFAULT
										AND COALESCE(s.ActuarialLob, '^&*')						= COALESCE(t.ActuarialLob, '^&*') COLLATE DATABASE_DEFAULT
										AND COALESCE(s.solvency_II_regulatory_key, -1)			= COALESCE(t.solvency_II_regulatory_key, -1)
										AND COALESCE(s.TIRS_CLM_CD, '^&*')						= COALESCE(t.TIRS_CLM_CD, '^&*') COLLATE DATABASE_DEFAULT
										AND COALESCE(s.SourceSystemKey, -1)						= COALESCE(t.SourceSystemKey, -1)

	WHERE  t.DataHash IS NULL
	   OR s.DataHash IS NULL
	   OR t.DataHash != s.DataHash  	  

	----------------------------------------------------------------------------------
	--OpenBox_UW_Staging
	----------------------------------------------------------------------------------
	BEGIN TRANSACTION
	
	UPDATE t
	   SET EndDate = p.ClosingValidTo
	  FROM assumed.OPENBOX_CLAIMS_staging t
	 CROSS JOIN #Parameters				p
	 INNER JOIN #ClaimsLoadOperation	lo	ON  lo.CONTRACT_NBR											= t.CONTRACT_NBR COLLATE DATABASE_DEFAULT
											AND lo.UNDERWRITING_YEAR									= t.UNDERWRITING_YEAR COLLATE DATABASE_DEFAULT
											AND COALESCE(lo.reg_date,'1900-01-01')						= COALESCE(t.reg_date,'1900-01-01')
											AND COALESCE(lo.TIRS_ORIG_CURR_CD, '^&*')					= COALESCE(t.TIRS_ORIG_CURR_CD, '^&*') COLLATE DATABASE_DEFAULT
											AND COALESCE(lo.TIRS_UW_ASSM_CEDED_NAME, '^&*')				= COALESCE(t.TIRS_UW_ASSM_CEDED_NAME, '^&*') COLLATE DATABASE_DEFAULT
											AND COALESCE(lo.LOB_NAME, '^&*')							= COALESCE(t.LOB_NAME, '^&*') COLLATE DATABASE_DEFAULT
											AND COALESCE(lo.ActuarialLob, '^&*')						= COALESCE(t.ActuarialLob, '^&*') COLLATE DATABASE_DEFAULT
											AND COALESCE(lo.solvency_II_regulatory_key, -1)				= COALESCE(t.solvency_II_regulatory_key, -1)
											AND COALESCE(lo.TIRS_CLM_CD, '^&*')							= COALESCE(t.TIRS_CLM_CD, '^&*') COLLATE DATABASE_DEFAULT
											AND COALESCE(lo.SourceSystemKey, -1)						= COALESCE(t.SourceSystemKey, -1)
											AND lo.Operation IN ('U', 'D')
	WHERE t.EndDate = '9999-12-31';

	INSERT INTO assumed.OPENBOX_CLAIMS_staging
	(	   [StartDate]
		  ,[TREATY_NBR]
		  ,[UNDERWRITING_YEAR]
		  ,[Ceded_CONTRACT_NBR]
		  ,[CONTRACT_NBR]
		  ,[SourceSystemKey]
		  ,[TransactionTypeCode]
		  ,[TransactionTypeCategory]
		  ,[DueDate]
		  ,[acct_from_dt]
		  ,[acct_to_dt]
		  ,[doc_key]
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
		  ,[bill_co_br_key]
		  ,[Summable_LOSS_PAID]
		  ,[SUMMABLE_LOSS_PAID_USD]
		  ,[SUMMABLE_LAE]
		  ,[SUMMABLE_LAE_USD]
		  ,[SUMMABLE_OS_LOSS]
		  ,[SUMMABLE_OS_LOSS_USD]
		  ,[Source]
		  ,[adjustmenttype]
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
		  ,[Summable_SETTL_LOSS_PAID]
		  ,[Summable_SETTL_LOSS_PAID_USD]
		  ,[Summable_SETTL_LAE]
		  ,[Summable_SETTL_LAE_USD]
		  ,[DataHash]
		)
	SELECT  
	[StartDate] = p.NewValidFrom
		,s.[TREATY_NBR]
		,s.[UNDERWRITING_YEAR]
		,s.[Ceded_CONTRACT_NBR]
		,s.[CONTRACT_NBR]
		,s.[SourceSystemKey]
		,s.[TransactionTypeCode]
		,s.[TransactionTypeCategory]
		,s.[DueDate]
		,s.[acct_from_dt]
		,s.[acct_to_dt]
		,s.[doc_key]
		,s.[ORIGCURR_CD]
		,s.[TIRS_ORIG_CURR_CD]
		,s.[SETTL_CURR_CD]
		,s.[TIRS_ORIG_CURR_NAME]
		,s.[lob_name]
		,s.[AccidentYear]
		,s.[aslob]
		,s.[TIRS_UW_ASSM_CEDED_NAME]
		,s.[reg_date]
		,s.[Claim_NBR]
		,s.[TIRS_CLM_CD]
		,s.[CatCode]
		,s.[CAT_KEY]
		,s.[solvency_II_regulatory_key]
		,s.[CLAIMLOSSDATE]
		,s.[bill_co_br_key]
		,s.[Summable_LOSS_PAID]
		,s.[SUMMABLE_LOSS_PAID_USD]
		,s.[SUMMABLE_LAE]
		,s.[SUMMABLE_LAE_USD]
		,s.[SUMMABLE_OS_LOSS]
		,s.[SUMMABLE_OS_LOSS_USD]
		,s.[Source]
		,s.[adjustmenttype]
		,s.[financial_lob]
		,s.[T7_CODE]
		,s.[T8_CODE]
		,s.[T9_CODE]
		,s.[InsurerCode]
		,s.[CLMS_PROCSS_CLM_DEPT]
		,s.[ICP_CEDED_FLG]
		,s.[RPT_OFF_NAME]
		,s.[ActuarialLob]
		,s.[MBU]
		,s.[L01]
		,s.[L02]
		,s.[L03]
		,s.[L04]
		,s.[L06]
		,s.[L07]
		,s.[L10]
		,s.[GD1]
		,s.[RPTCURR1_CD]
		,s.[RPTCURR2_CD]
		,s.[RPTCURR1]
		,s.[RPTCURR2]
		,s.[SETTL_RPTCURR1]
		,s.[SETTL_RPTCURR2]
		,s.[Summable_SETTL_LOSS_PAID]
		,s.[Summable_SETTL_LOSS_PAID_USD]
		,s.[Summable_SETTL_LAE]
		,s.[Summable_SETTL_LAE_USD]
		,s.[DataHash]
	FROM #OpenBox_CLAIMS_Stage		s
	CROSS JOIN #Parameters			p
	INNER JOIN #ClaimsLoadOperation	lo	ON  lo.CONTRACT_NBR											= s.CONTRACT_NBR COLLATE DATABASE_DEFAULT
										AND lo.UNDERWRITING_YEAR									= s.UNDERWRITING_YEAR COLLATE DATABASE_DEFAULT
										AND COALESCE(lo.reg_date,'1900-01-01')						= COALESCE(s.reg_date,'1900-01-01')
										AND COALESCE(lo.TIRS_ORIG_CURR_CD, '^&*')					= COALESCE(s.TIRS_ORIG_CURR_CD, '^&*') COLLATE DATABASE_DEFAULT
										AND COALESCE(lo.TIRS_UW_ASSM_CEDED_NAME, '^&*')				= COALESCE(s.TIRS_UW_ASSM_CEDED_NAME, '^&*') COLLATE DATABASE_DEFAULT
										AND COALESCE(lo.LOB_NAME, '^&*')							= COALESCE(s.LOB_NAME, '^&*') COLLATE DATABASE_DEFAULT
										AND COALESCE(lo.ActuarialLob, '^&*')						= COALESCE(s.ActuarialLob, '^&*') COLLATE DATABASE_DEFAULT
										AND COALESCE(lo.solvency_II_regulatory_key, -1)				= COALESCE(s.solvency_II_regulatory_key, -1)
										AND COALESCE(lo.TIRS_CLM_CD, '^&*')							= COALESCE(s.TIRS_CLM_CD, '^&*') COLLATE DATABASE_DEFAULT
										AND COALESCE(lo.SourceSystemKey, -1)						= COALESCE(s.SourceSystemKey, -1)						
										AND lo.Operation IN ('I', 'U')
	COMMIT TRANSACTION

	-------------------------------------------------------
	-- Update etl_controller, flag SUCCESS
	-------------------------------------------------------
	SET @v_RowsProcessed	= COALESCE((SELECT COUNT(0) FROM #ClaimsLoadOperation WHERE Operation IN ('I', 'U', 'D')), 0)
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
