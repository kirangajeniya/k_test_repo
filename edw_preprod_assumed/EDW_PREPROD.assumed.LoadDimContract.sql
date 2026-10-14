-- Database: EDW_PREPROD
-- Schema: assumed
-- Procedure: LoadDimContract

CREATE   PROCEDURE [assumed].[LoadDimContract]
AS
BEGIN
	BEGIN TRY
		DROP TABLE IF EXISTS #Parameters

		SELECT
			 ClosingEndDate	= DATEADD(NANOSECOND, -100, SYSDATETIME())
			,NewStartDate	= SYSDATETIME()
		INTO #Parameters

		-- Staging logic
		
		--Underwriting piece of Code START
		DROP TABLE IF EXISTS #contractnumber
		DROP TABLE IF EXISTS #policynumber
		DROP TABLE IF EXISTS #edwcontract
		DROP TABLE IF EXISTS #cededcontracttemp
		DROP TABLE IF EXISTS #cededcontract
		
		SELECT DISTINCT 
			 CONTRACT_NBR		= RTRIM(LTRIM(CAST (ad.trty_no as char(5)) + cast (ad.und_yr as char(4))))COLLATE Latin1_General_CI_AI	
			,CEDED_CONTRACT_NBR	= RTRIM(LTRIM(CAST (ceded_tm.trty_no as char(5)) + cast (ceded_tm.und_yr as char(4))))COLLATE Latin1_General_CI_AI
		 INTO #cededcontracttemp				
		 FROM src_tirs_db.dbo.acct_byline 		ab WITH(nolock)
		INNER JOIN SRC_TIRS_DB.dbo.acct_doc		ad WITH(nolock) 		ON ab.doc_key = ad.doc_key
		LEFT  JOIN SRC_TIRS_DB.dbo.trty_master 	ceded_tm WITH(nolock)	ON ceded_tm.trty_key = ad.Ceded_trty_key;
		
		SELECT * 
		  INTO #cededcontract
		  FROM (
				SELECT DISTINCT CONTRACT_NBR
				  FROM #cededcontracttemp
				UNION
				SELECT DISTINCT CEDED_CONTRACT_NBR
				  FROM #cededcontracttemp
		) CEDED;
				
		SELECT DISTINCT contract_NBR, Contract_Reference
		  INTO #contractnumber	--(#mapping)
		  FROM EDW_PREPROD.dbo.MAP_CONTRACT_EDW WITH(nolock)
		 WHERE plcy_SRC='OPENBOX';

		SELECT E.PolicyNumber
		  INTO #policynumber	--(#EGL) 
		  FROM EDW_PREPROD.lloyds.tbl_ep_gp_llyds	E WITH(nolock)
		 OUTER APPLY (SELECT TOP 1 R.TIRS_CURRENCY_CODE, R.CURRENCY_NAME
						FROM EDW_PREPROD.dbo.EDW_TIRS_ROE	R WITH(nolock)
					   WHERE E.OriginalCurrencyCode = R.TIRS_CURRENCY_CODE ORDER BY R.K1PERIOD_OF_TIME DESC) R	
		 WHERE businesstype='Assumed'
		   AND PolicySource='Openbox';
				
		SELECT *
		  INTO #edwcontract
		  FROM (
				SELECT contract_NBR
				  from #contractnumber 		A
				  LEFT JOIN #policynumber 	B	ON A.CONTRACT_REFERENCE = B.PolicyNumber
				 UNION
				SELECT H.Contract_NBR
				  FROM Insight.dbo.accounting_periods 		P WITH(nolock)
				 INNER JOIN EDW_PREPROD.dbo.T_Code_History  H WITH(nolock)	ON  DATEADD(DAY,1,P.accounting_period_close_date) > H.START_DATE
																			AND DATEADD(DAY,1,P.accounting_period_close_date) < H.end_date
				 UNION
				SELECT DISTINCT CONTRACT_NBR
				  FROM #cededcontract
		) undwcontract;	
		--Underwriting piece of Code END

		--------------------------------------------------------
		--#DimContract0
		--------------------------------------------------------
		DROP TABLE IF EXISTS #DimContract0
		
		SELECT
			 BE_ID				= c.BE_ID
			,CONTRACT_NBR		= c.CONTRACT_NBR
			,PLCY_SRC			= c.PLCY_SRC
			,UNDERWRITING_YEAR	= c.UNDERWRITING_YEAR
			,Assumed_Ceded_Flg	= CAST(NULL AS VARCHAR)
		INTO #DimContract0
		FROM EDW_PREPROD.dbo.ATT_CONTRACT c
		LEFT JOIN SRC_TIRS_DB.dbo.trty_master s
		ON c.CONTRACT_NBR COLLATE DATABASE_DEFAULT = CONCAT(LEFT(s.trty_no, 5), s.und_yr)  COLLATE DATABASE_DEFAULT
		and c.PLCY_SRC = 'TIRS'
		WHERE SYSDATETIME() BETWEEN c.START_DATE AND c.END_DATE
		  AND c.BE_NAME != 'UNCODED'
		  AND (
        (c.PLCY_SRC = 'TIRS'   AND s.trty_no IS NOT NULL  AND s.und_yr IS NOT NULL)
        OR c.PLCY_SRC = 'OPENBOX' 
		OR c.PLCY_SRC = 'Not classified at this level'
		)
		UNION ALL
		SELECT
			 c.BE_ID
			,CONTRACT_NBR		= 'Uncoded'
			,PLCY_SRC			= 'Uncoded'
			,UNDERWRITING_YEAR	= 'Uncoded'
			,Assumed_Ceded_Flg	= CAST(NULL AS VARCHAR)
		FROM EDW_PREPROD.dbo.ATT_CONTRACT c
		WHERE SYSDATETIME() BETWEEN c.START_DATE AND c.END_DATE
		  AND BE_NAME = 'UNCODED'
		UNION ALL
		SELECT
			 BE_ID 				= NULL
			,CONTRACT_NBR 		= 'N/A'
			,PLCY_SRC 			= 'N/A'
			,UNDERWRITING_YEAR	= 'N/A'
			,Assumed_Ceded_Flg	= CAST(NULL AS VARCHAR)
		--Underwriting piece of Code START
		UNION
		SELECT DISTINCT
			 BE_ID				= c.BE_ID 
			,CONTRACT_NBR		= c.CONTRACT_NBR
			,PLCY_SRC			= c.PLCY_SRC
			,UNDERWRITING_YEAR	= c.UNDERWRITING_YEAR 
			,Assumed_Ceded_Flg	= CAST(NULL AS VARCHAR)
		FROM EDW_PREPROD.dbo.MAP_CONTRACT_edw	c WITH(NOLOCK)
		WHERE CONTRACT_NBR IN (SELECT CONTRACT_NBR FROM #edwcontract)
		  AND (c.cntrct_sec = '$NOOID')
		UNION
		SELECT DISTINCT
			 BE_ID				= NULL
			,CONTRACT_NBR		= rtct.CONTRACT_NBR COLLATE DATABASE_DEFAULT
			,PLCY_SRC			= rtct.SOURCE --'TOPSIDES'
			,UNDERWRITING_YEAR	= rtct.UNDERWRITING_YEAR COLLATE DATABASE_DEFAULT
			,Assumed_Ceded_Flg	= CAST(NULL AS VARCHAR)
		FROM EDW_PREPROD.dbo.RS_TIRS_UNDERWRITING_TOPSIDE rtct
		WHERE NOT EXISTS (
		    SELECT 1
		    FROM EDW_PREPROD.dbo.MAP_CONTRACT_EDW c WITH (NOLOCK)
		    WHERE c.CONTRACT_NBR COLLATE DATABASE_DEFAULT = rtct.CONTRACT_NBR COLLATE DATABASE_DEFAULT
		      AND c.cntrct_sec = '$NOOID'
		      AND c.CONTRACT_NBR IN (SELECT CONTRACT_NBR FROM #edwcontract)
		);

		-----------------------------------------------------------------------
		--#DimContract0:
		--Postupdate column Assumed_Ceded_Flg 
		--   Add new column SourceCreatedDate
		-----------------------------------------------------------------------
		ALTER TABLE #DimContract0 ADD SourceCreatedDate DATETIME NULL;

		UPDATE dc
		   SET dc.Assumed_Ceded_Flg = x.assumed_ceded_flg
			  ,dc.SourceCreatedDate = x.create_dt
		  FROM #DimContract0 dc
		  LEFT JOIN (
				SELECT
					 CONTRACT_NBR		= RTRIM(LTRIM(CAST(tm.trty_no AS CHAR(5)) + CAST(tm.und_yr AS CHAR(4)))) COLLATE Latin1_General_CI_AI
					,assumed_ceded_flg	= tm.assumed_ceded_flg
					,create_dt			= MIN(tm.create_dt) 
				FROM SRC_TIRS_DB.dbo.trty_master tm
				GROUP BY
					 RTRIM(LTRIM(CAST(tm.trty_no AS CHAR(5)) + CAST(tm.und_yr AS CHAR(4))))
					,tm.assumed_ceded_flg
		) AS x
		  ON dc.CONTRACT_NBR = x.CONTRACT_NBR;

		-----------------------------------------------------------------------
		--#ContractAttributes
		-----------------------------------------------------------------------
		DROP TABLE IF EXISTS #ContractAttributes
		
		SELECT *
		  INTO #ContractAttributes
		  FROM (
				SELECT DISTINCT
					 CONTRACT_NBR		= mce.CONTRACT_NBR
					,ReportingOfficeCode= mce.RPT_OFF_CD
					,ReportingOffice	= mce.RPT_OFF_NAME
					,L01				= 'LSL'
					,PLCY_SRC			= PLCY_SRC
					,CONTRACT_REFERENCE = mce.CONTRACT_REFERENCE
				 FROM dbo.MAP_CONTRACT_EDW	AS mce
				WHERE mce.PLCY_SRC = 'OPENBOX'
				  AND mce.END_DATE = '31 Dec 9999'
				UNION ALL

				

				SELECT DISTINCT
					 CONTRACT_NBR			= mce.CONTRACT_NBR
					,ReportingOfficeCode	= mce.RPT_OFF_CD
					,ReportingOffice		= mce.RPT_OFF_NAME
					,L01					= ISNULL(tch.L01, ContractTIRSL01.L01)
					,PLCY_SRC				= mce.PLCY_SRC
					,CONTRACT_REFERENCE		= 'N/A'
				FROM dbo.MAP_CONTRACT_EDW		AS mce
				LEFT JOIN dbo.T_Code_History	AS tch	ON tch.Contract_NBR = mce.CONTRACT_NBR AND tch.END_DATE = '31 Dec 9999'
				LEFT JOIN (
							SELECT CONTRACT_NBR = CONCAT(LEFT(ctm.trty_no, 5), ctm.und_yr) COLLATE DATABASE_DEFAULT
							,L01 = MIN(tch.L01)
							FROM (
							  SELECT ad.trty_key,ad.ceded_trty_key
							  FROM SRC_TIRS_DB.dbo.acct_doc ad
							  UNION
							  SELECT ad.trty_key,ad.ceded_trty_key
							  FROM SRC_TIRS_DB.dbo.acct_doc ad
							  WHERE ad.ceded_trty_key != -999
							  ) x
							INNER JOIN SRC_TIRS_DB.dbo.trty_master tm
								ON tm.trty_key = x.trty_key
							INNER JOIN SRC_TIRS_DB.dbo.trty_master ctm
								ON ctm.trty_key = x.ceded_trty_key
							INNER JOIN dbo.T_Code_History tch
								ON tch.CONTRACT_NBR = CONCAT(LEFT(tm.trty_no, 5), tm.und_yr) COLLATE DATABASE_DEFAULT
								AND tch.RowIsCurrent = 'Y'
							GROUP BY CONCAT(LEFT(ctm.trty_no, 5), ctm.und_yr)
									) as ContractTIRSL01 ON	ContractTIRSL01.CONTRACT_NBR = mce.CONTRACT_NBR
				WHERE mce.PLCY_SRC = 'TIRS'
				AND mce.END_DATE = '31 Dec 9999'				
				
		) as ca
		-----------------------------------------------------------------------
		--#ContractAttributes
		-----------------------------------------------------------------------
		DROP TABLE IF EXISTS #ContractLimits
		
		SELECT *
		  INTO #ContractLimits
		  FROM (
				SELECT
					 [PLCY_SRC]
					,[CONTRACT_NBR]
					,[AWAC_limit_USD]
					,[limit_attachment_USD]
					,[pml_amount_USD]
				FROM (
					SELECT
						 [PLCY_SRC]				= 'TIRS'
						,[CONTRACT_NBR]			= CONCAT(CONVERT(CHAR(5),t.trty_no), CONVERT(CHAR(4),t.und_yr))
						,[Currency_CNT]			= COUNT(DISTINCT l.[curr_cd])
						,[AWAC_limit_USD]		= SUM(CONVERT(numeric(18,0), ISNULL(l.trc_trty_lmt	*cd.xch_rt,0)))
						,[limit_attachment_USD]	= SUM(CONVERT(numeric(18,0), ISNULL(l.retention_amt	*cd.xch_rt,0)))
						,[pml_amount_USD]		= SUM(CONVERT(numeric(18,0), ISNULL(l.pml_amt		*cd.xch_rt,0)))
					 FROM [SRC_TIRS_DB].dbo.trty_master			AS t 
					INNER JOIN [SRC_TIRS_DB].dbo.trty_limit		AS l	ON l.trty_key = t.trty_key
					 LEFT JOIN [SRC_TIRS_DB].dbo.xrf_curr_cds	AS cd	ON cd.curr_cd = l.curr_cd AND cd.latest_rates_flg='Y'
					WHERE l.delete_flg = 'N'
					  AND l.accum_lmt_flg = 'Y'					 
					GROUP BY
						CONCAT(CONVERT(CHAR(5),t.trty_no), CONVERT(CHAR(4),t.und_yr))
					UNION ALL
					SELECT
						 [PLCY_SRC]				= m.PLCY_SRC
						,[CONTRACT_NBR]			= m.CONTRACT_NBR COLLATE database_default
						,[Currency_CNT]			= COUNT(DISTINCT o.PolicyLimitCurrency)
						,[AWAC_limit_USD]		= SUM(CONVERT(NUMERIC(18,0), ISNULL(o.PolicyExcessUSD, 0)))
						,[limit_attachment_USD]	= SUM(CONVERT(NUMERIC(18,0), ISNULL(o.PolicyExposureUSD, 0)))
						,[pml_amount_USD]		= SUM(CONVERT(NUMERIC(18,0), ISNULL(o.PolicyLimitUSD, 0)))
					  FROM EDW_PREPROD.dbo.MAP_CONTRACT_EDW				AS m
					  LEFT JOIN EDW_PREPROD.dbo.LOOKUP_LLOYDS_OPENBOX	AS o	ON o.PolicyNumber = m.CONTRACT_REFERENCE AND o.BusinessType ='Assumed'
					 WHERE m.END_DATE   = '9999-12-31'
					   AND m.PLCY_SRC   = 'OPENBOX'
					   AND m.CNTRCT_SEC = '$NOOID'
					 GROUP BY
						 m.CONTRACT_NBR
						,m.PLCY_SRC
				) src
				WHERE Currency_CNT <> 0				
		) s
		-----------------------------------------------------------------------
		--#DimContract
		-----------------------------------------------------------------------
		DROP TABLE IF EXISTS #DimContract
		
		CREATE TABLE #DimContract
		(
				[StartDate]					[DATETIME2](7) NULL,
				[EndDate] 					[DATETIME2](7) NULL,
				[BE_ID] 					[VARCHAR](10)  NULL,
				[CONTRACT_NBR] 				[VARCHAR](255) NULL,
				[PLCY_SRC] 					[VARCHAR](255) NULL,
				[UNDERWRITING_YEAR] 		[VARCHAR](255) NULL,
				[ASSUMED_CEDED_FLG] 		[VARCHAR](1)   NULL,
				[inception_date] 			[VARCHAR](255) NULL,
				[expiry_date] 				[VARCHAR](255) NULL,
				[new_renewal] 				[VARCHAR](255) NULL,
				[policy_coverage_type] 		[VARCHAR](255) NULL,
				[underwriter_code] 			[VARCHAR](255) NULL,
				[policy_source] 			[VARCHAR](255) NULL,
				[source_key] 				[TINYINT] NULL,
				[policy_status] 			[VARCHAR](255) NULL,
				[cedant_code] 				[VARCHAR](255) NULL,
				[broker_code] 				[VARCHAR](255) NULL,
				[broker_ref] 				[VARCHAR](255) NULL,
				[branch_code] 				[VARCHAR](255) NULL,
				[sif_oif] 					[VARCHAR](10)  NULL,
				[division_code] 			[VARCHAR](255) NULL,
				[department_code] 			[VARCHAR](255) NULL,
				[sub_department_code] 		[VARCHAR](255) NULL,
				[division_name]				[VARCHAR](255) NULL,
				[department_name] 			[VARCHAR](255) NULL,
				[sub_department_name]		[VARCHAR](255) NULL,
				[attachment_basis_name] 	[VARCHAR](255) NULL,
				[pro_rata_xol_name] 		[VARCHAR](255) NULL,
				[ceding_company_reference]	[VARCHAR](255) NULL,
				[group_name] 				[VARCHAR](255) NULL,
				[is_processed_by_claims_department] [VARCHAR](255) NULL,
				[billing_company_code] 		[VARCHAR](255) NULL,
				[billing_company_reference] [VARCHAR](255) NULL,
				[policy_name] 				[VARCHAR](255) NULL,
				[policy_type] 				[VARCHAR](255) NULL,
				[effective_date] 			[VARCHAR](255) NULL,
				[awac_lead] 				[VARCHAR](255) NULL,
				[puk_code] 					[VARCHAR](255) NULL,
				[puk_name] 					[VARCHAR](255) NULL,
				[DimBillingID] 				[INT] NULL,
				[DimAssuredID] 				[INT] NULL,
				[DimBrokerID] 				[INT] NULL,
				[DimMGAID] 					[INT] NULL,
				[DimSchdlCompanyNameID]		[INT] NULL,
				[DimTPAID] 					[INT] NULL,
				[ReportingOfficeCode] 		[VARCHAR] (255) NULL,
				[ReportingOffice] 			[VARCHAR] (255) NULL,
				[L01] 						[CHAR] (3)		NULL,
				[AWAC_Estimated_Premium]	[NUMERIC](16,2) NULL,
				[ROL]						[NUMERIC](16,7) NULL,
				[Free]                      [VARCHAR](255)  NULL,
				[NumberAllowed]             [VARCHAR](255)  NULL,
				[ProRataAsToTime]           [VARCHAR](255)  NULL,
				[ProRataAsToAmt]            [VARCHAR](255)  NULL,
				[ReinstatementBrokeragePct] [VARCHAR](255)  NULL,
				[ReinstatementPremiumPct]   [VARCHAR](255)  NULL,
				[management_base]           [VARCHAR](30)   NULL,
				[Management_Expense_%]      [NUMERIC](10,6) NULL,
				[First_adjustment_date]     [DATETIME]		NULL,
				[Last_adjustment_date]      [DATETIME]		NULL,
				[Deficit_carry_forward]     [INT]			NULL,
				[Profit_comission]          [NUMERIC](10,6)	NULL,
				[Broker_Fee_Basis]          [VARCHAR](30)   NULL,
				[BrokerFee_Percentage]      [NUMERIC](10,6) NULL,
				[cedng_comm_flat_pct]       [VARCHAR](30)   NULL,
				[cedng_comm_ovrrd_orig_pls] [VARCHAR](30)   NULL,
				[block_basis_start]         [DATETIME]		NULL,
				[block_basis_end]           [DATETIME]		NULL,
				[expos_cd]                  [VARCHAR](255)  NULL,
				[expos_name]                [VARCHAR](255)  NULL,
				[premium_frequency_cd]      [CHAR](1)       NULL,
			    [premium_frequency]         [VARCHAR](30)   NULL,
			    [remittance_days]           [INT]           NULL,
				[prem_tax_pct]				[NUMERIC](10,6)	NULL,
				[Ultimate_Loss_Ratio]		[NUMERIC](12,6)	NULL,
				[treaty_type]				[VARCHAR](3)    NULL,
				[treaty_accounting_mode]	[VARCHAR](2)    NULL,
				[policy_coverage_type_cd]	[INT]           NULL,
				[original_underwriter_name] [VARCHAR](255)	NULL,
				[SourceCreatedDate]         [DATETIME]      NULL,
				[AWAC_limit_USD]			[NUMERIC](18,2) NULL,
				[limit_attachment_USD]	    [NUMERIC](18,2) NULL,
				[pml_amount_USD]	        [NUMERIC](18,2) NULL,
				[CONTRACT_REFERENCE]		[VARCHAR](255)  NULL
		);
		
		INSERT INTO #DimContract (
			 [BE_ID]
			,[CONTRACT_NBR]
			,[PLCY_SRC]
			,[UNDERWRITING_YEAR]
			,[ASSUMED_CEDED_FLG]
			,[inception_date]
			,[expiry_date]
			,[new_renewal]
			,[policy_coverage_type]
			,[underwriter_code]
			,[policy_source]
			,[source_key]
			,[policy_status]
			,[cedant_code]
			,[broker_code]
			,[broker_ref]
			,[branch_code]
			,[sif_oif]
			,[division_code]
			,[department_code]
			,[sub_department_code]
			,[division_name]
			,[department_name]
			,[sub_department_name]
			,[attachment_basis_name]
			,[pro_rata_xol_name]
			,[ceding_company_reference]
			,[group_name]
			,[is_processed_by_claims_department]
			,[billing_company_code]
			,[billing_company_reference]
			,[policy_name]
			,[policy_type]
			,[effective_date]
			,[awac_lead]
			,[puk_code]
			,[puk_name]
			,[expos_cd]
			,[expos_name]
			,[DimBillingID]
			,[DimAssuredID]
			,[DimBrokerID]
			,[DimMGAID]
			,[DimSchdlCompanyNameID]
			,[DimTPAID]
			,[treaty_accounting_mode]
			,[ReportingOfficeCode]		
			,[ReportingOffice]			
			,[L01]		
			,[original_underwriter_name]
			,[SourceCreatedDate]
			,[AWAC_limit_USD]
			,[limit_attachment_USD]	
			,[pml_amount_USD]	 
			,[CONTRACT_REFERENCE]
		)
		SELECT
			 [BE_ID] 					= c.BE_ID
			,[CONTRACT_NBR] 			= c.CONTRACT_NBR
			,[PLCY_SRC] 				= c.PLCY_SRC
			,[UNDERWRITING_YEAR]		= c.UNDERWRITING_YEAR
			,[ASSUMED_CEDED_FLG]		= c.ASSUMED_CEDED_FLG
			,[inception_date] 			= inception_date
			,[expiry_date] 				= expiry_date
			,[new_renewal] 				= new_renewal
			,[policy_coverage_type] 	= policy_coverage_type
			,[underwriter_code] 		= underwriter_code
			,[policy_source] 			= policy_source
			,[source_key] 				= source_key
			,[policy_status] 			= policy_status
			,[cedant_code] 				= cedant_code
			,[broker_code] 				= broker_code
			,[broker_ref] 				= broker_ref
			,[branch_code] 				= branch_code
			,[sif_oif] 					= sif_oif
			,[division_code] 			= division_code
			,[department_code] 			= department_code
			,[sub_department_code]		= sub_department_code
			,[division_name] 			= division_name
			,[department_name] 			= department_name
			,[sub_department_name] 		= sub_department_name
			,[attachment_basis_name]	= attachment_basis_name
			,[pro_rata_xol_name] 		= pro_rata_xol_name
			,[ceding_company_reference] = ceding_company_reference
			,[group_name] 				= group_name
			,[is_processed_by_claims_department] = is_processed_by_claims_department
			,[billing_company_code] 	= billing_company_code
			,[billing_company_reference]= billing_company_reference
			,[policy_name] 				= policy_name
			,[policy_type] 				= policy_type
			,[effective_date] 			= effective_date
			,[awac_lead] 				= awac_lead
			,[puk_code] 				= puk_code
			,[puk_name] 				= puk_name
			,[expos_cd] 				= expos_cd
			,[expos_name] 				= expos_name
			,[DimBillingID] 			= db.DimBillingID
			,[DimAssuredID] 			= da.DimAssuredID
			,[DimBrokerID]				= dbr.DimBrokerID
			,[DimMGAID] 				= dmga.DimMGAID
			,[DimSchdlCompanyNameID]	= ds.DimSchdlCompanyNameID
			,[DimTPAID] 				= dtpa.DimTPAID
			,[treaty_accounting_mode]	=  CASE WHEN c.PLCY_SRC = 'OPENBOX' OR COALESCE(a.ATTACH_BASIS_CD, '') = '2' 
												THEN 'RA' 
												ELSE 'LO' END
			,[ReportingOfficeCode]		= ca.ReportingOfficeCode
			,[ReportingOffice]			= ca.ReportingOffice
			,[L01]						= ca.L01
			,[original_underwriter_name]= a.ORIG_UW_NAME
			,[SourceCreatedDate]        = c.SourceCreatedDate
			,[AWAC_limit_USD]			= ll.AWAC_limit_USD
			,[limit_attachment_USD]		= ll.limit_attachment_USD
			,[pml_amount_USD]			= ll.pml_amount_USD
			,[CONTRACT_REFERENCE]		= ca.CONTRACT_REFERENCE
		FROM #DimContract0	AS c
		LEFT JOIN (
					  SELECT c.INCEPT_DT 		AS inception_date
							,c.EXP_DT 			AS expiry_date
							,c.underwriting_year AS underwriting_year
							,c.NEW_RENW_NAME 	AS new_renewal
							,c.RI_COV_NAME 		AS policy_coverage_type
							,c.CUR_UW_CD 		AS underwriter_code
							,c.[PLCY_SRC] 		AS policy_source
							,c.source_key 		AS source_key
							,c.CNTRCT_STATUS_CD AS policy_status
							,c.CEDNG_COMPANY_CD AS cedant_code
							,c.BRKR_COMPANY_CD 	AS broker_code
							,c.BRKR_REF 		AS broker_ref
							,c.SunBranchCode 	AS branch_code
							,c.SIF_OIF 			AS sif_oif
							,c.DIV_CD 			AS division_code
							,c.DEPT_CD 			AS department_code
							,c.SUB_DEPT_CD 		AS sub_department_code
							,c.DIV_NAME 		AS division_name
							,c.DEPT_NAME 		AS department_name
							,c.SUB_DEPT_NAME 	AS sub_department_name
							,c.ATTACH_BASIS_NAME AS attachment_basis_name
							,c.PRO_RATA_XOL_NAME AS pro_rata_xol_name
							,c.CDNG_COMPANY_REF AS ceding_company_reference
							,c.GRP_NAME 		AS group_name
							,c.CLMS_PROCSS_CLM_DEPT AS is_processed_by_claims_department
							,c.BILL_COMPANY_CD 	AS billing_company_code
							,c.BILL_COMPANY_REF AS billing_company_reference
							,c.CONTRACT_NAME 	AS policy_name
							,c.TRTY_FAC_NAME 	AS policy_type
							,c.EFF_DT 			AS effective_date
							,c.AWAC_LEAD 		AS awac_lead
							,c.PSAC_NBR 		AS puk_code
							,c.LIRMA_BUS 		AS puk_name
							,c.expos_cd
							,c.expos_name
							,c.CONTRACT_NBR
							,c.BILL_COMPANY_CD
                            ,c.CEDNG_COMPANY_CD
                            ,c.BRKR_COMPANY_CD
                            ,c.MGA_COMPANY_CD
                            ,c.SCHDL_COMPANY_CD
                            ,c.CLM_TPA_COMPANY_CD
							,c.ATTACH_BASIS_CD
							,c.ORIG_UW_NAME
						 FROM EDW_PREPROD.dbo.MAP_CONTRACT_EDW c WITH(NOLOCK)
						WHERE c.cntrct_sec = '$NOOID'
			) AS a
			  ON a.[CONTRACT_NBR] COLLATE DATABASE_DEFAULT = c.[CONTRACT_NBR]
			LEFT JOIN #ContractAttributes	AS ca	ON  ca.CONTRACT_NBR  COLLATE DATABASE_DEFAULT = c.CONTRACT_NBR
													AND ca.PLCY_SRC		 COLLATE DATABASE_DEFAULT IN (c.PLCY_SRC,a.policy_source)
			LEFT JOIN #ContractLimits		AS ll	ON  ll.CONTRACT_NBR  COLLATE DATABASE_DEFAULT = c.CONTRACT_NBR
													AND ll.PLCY_SRC		 COLLATE DATABASE_DEFAULT IN (c.PLCY_SRC,a.policy_source)
			LEFT JOIN (SELECT BILL_COMPANY_CD= IIF(BILL_COMPANY_CD = 'Not classified at this level', 'Uncoded', BILL_COMPANY_CD)
							 ,DimBillingID	 = MIN(DimBillingID)
						 FROM assumed.DimBilling
						 WHERE EndDate = '31 Dec 9999'
						GROUP BY IIF(BILL_COMPANY_CD = 'Not classified at this level', 'Uncoded', BILL_COMPANY_CD)
			) AS db
			  ON a.BILL_COMPANY_CD = db.BILL_COMPANY_CD
			LEFT JOIN (SELECT CEDNG_COMPANY_CD= IIF(CEDNG_COMPANY_CD = 'Not classified at this level', 'Uncoded', CEDNG_COMPANY_CD)
							 ,DimAssuredID	  = MIN(DimAssuredID)
						 FROM assumed.DimAssured
						 WHERE EndDate = '31 Dec 9999'
						GROUP BY IIF(CEDNG_COMPANY_CD = 'Not classified at this level', 'Uncoded', CEDNG_COMPANY_CD)
			) AS da
			  ON a.CEDNG_COMPANY_CD = da.CEDNG_COMPANY_CD
			LEFT JOIN (SELECT BRKR_COMPANY_CD = IIF(BRKR_COMPANY_CD = 'Not classified at this level', 'Uncoded', BRKR_COMPANY_CD)
							 ,DimBrokerID     = MIN(DimBrokerID)
						 FROM assumed.DimBroker
						 WHERE EndDate = '31 Dec 9999'
						GROUP BY IIF(BRKR_COMPANY_CD = 'Not classified at this level', 'Uncoded', BRKR_COMPANY_CD)
			) AS dbr
			  ON a.BRKR_COMPANY_CD = dbr.BRKR_COMPANY_CD
			LEFT JOIN (SELECT MGA_COMPANY_CD = IIF(MGA_COMPANY_CD = 'Not classified at this level', 'Uncoded', MGA_COMPANY_CD)
							 ,DimMGAID       = MIN(DimMGAID)
						 FROM assumed.DimMGA
						 WHERE EndDate = '31 Dec 9999'
						GROUP BY IIF(MGA_COMPANY_CD = 'Not classified at this level', 'Uncoded', MGA_COMPANY_CD)
			) AS dmga
			  ON a.MGA_COMPANY_CD = dmga.MGA_COMPANY_CD
			LEFT JOIN ( SELECT SCHDL_COMPANY_CD		 = IIF(SCHDL_COMPANY_CD = 'Not classified at this level', 'Uncoded', SCHDL_COMPANY_CD)
							  ,DimSchdlCompanyNameID = MIN(DimSchdlCompanyNameID)
						 FROM assumed.DimSchdlCompanyName
						 WHERE EndDate = '31 Dec 9999'
						GROUP BY IIF(SCHDL_COMPANY_CD = 'Not classified at this level', 'Uncoded', SCHDL_COMPANY_CD)
			) AS ds
			  ON a.SCHDL_COMPANY_CD = ds.SCHDL_COMPANY_CD
			LEFT JOIN (SELECT CLM_TPA_COMPANY_CD = IIF(CLM_TPA_COMPANY_CD = 'Not classified at this level', 'Uncoded', CLM_TPA_COMPANY_CD)
							 ,DimTPAID			 = MIN(DimTPAID)
						 FROM assumed.DimTPA
						 WHERE EndDate = '31 Dec 9999'
						GROUP BY IIF(CLM_TPA_COMPANY_CD = 'Not classified at this level', 'Uncoded', CLM_TPA_COMPANY_CD)
			) AS dtpa
			  ON a.CLM_TPA_COMPANY_CD = dtpa.CLM_TPA_COMPANY_CD;

		--------------------------------------------------------------------------------
		--#ContractAttributes2
		--------------------------------------------------------------------------------				
		DROP TABLE IF EXISTS #ContractAttributes2
		
		SELECT
			CONTRACT_NBR		= RTRIM(LTRIM(CAST (Treaty.trty_no AS CHAR(5)) + CAST (Treaty.und_yr AS CHAR(4))))COLLATE Latin1_General_CI_AI,
			effective_date		= Treaty.effective_dt,
			expiry_date			= Treaty.expiration_dt,
			AWAC_Estimated_Premium = SUM(SectionRecap.trc_estim_prem_us),
			ROL					= NULLIF(SUM(SectionRecap.trc_estim_prem_us), 0) / NULLIF(SUM(SectionRecap.trc_limit_us), 0)
		 INTO #ContractAttributes2
		 FROM SRC_TIRS_DB.dbo.trty_master Treaty
		INNER JOIN SRC_TIRS_DB.dbo.trty_section			Section			ON Treaty.trty_key = Section.trty_key
		INNER JOIN SRC_TIRS_DB.dbo.trty_section_recap 	SectionRecap	ON Section.section_key = SectionRecap.section_key
		WHERE Section.delete_flg = 'N'
		GROUP BY
			RTRIM(LTRIM(CAST (Treaty.trty_no AS CHAR(5)) + CAST (Treaty.und_yr AS CHAR(4)))) COLLATE Latin1_General_CI_AI,
			Treaty.effective_dt,
			Treaty.expiration_dt;
		
		UPDATE dc
		   SET dc.AWAC_Estimated_Premium= src.AWAC_Estimated_Premium,
			   dc.ROL 					= src.ROL
		  FROM #DimContract dc
		  JOIN #ContractAttributes2 src WITH (NOLOCK)
		    ON dc.CONTRACT_NBR = src.CONTRACT_NBR COLLATE DATABASE_DEFAULT
			AND dc.effective_date = src.effective_date
			AND dc.expiry_date = src.expiry_date
		--------------------------------------------------------------------------------
		--BridgeContractSections
		--------------------------------------------------------------------------------			
		DROP TABLE IF EXISTS #BridgeContractSections
		CREATE TABLE #BridgeContractSections(
			[CONTRACT_NBR]                VARCHAR(255)  NULL,
			[Free]                        VARCHAR(255)  NULL,
			[NumberAllowed]               VARCHAR(255)  NULL,
			[ProRataAsToTime]             VARCHAR(255)  NULL,
			[ProRataAsToAmt]              VARCHAR(255)  NULL,
			[ReinstatementBrokeragePct]   VARCHAR(255)  NULL,
			[ReinstatementPremiumPct]     VARCHAR(255)  NULL
		)
		
		INSERT INTO #BridgeContractSections (
			 CONTRACT_NBR
			,Free
			,NumberAllowed
			,ProRataAsToTime
			,ProRataAsToAmt
			,ReinstatementBrokeragePct
			,ReinstatementPremiumPct
		)
		SELECT DISTINCT
			 CONTRACT_NBR		= CONTRACT_NBR
			,Free				= REINSTMT_FREE
			,NumberAllowed		= REINSTMT_NBR_ALLWD
			,ProRataAsToTime	= REINSTMT_PRO_RATA_TIME
			,ProRataAsToAmt		= REINSTMT_PRO_RATA_AMT
			,ReinstatementBrokeragePct	= REINSTMT_BRKR_PCT
			,ReinstatementPremiumPct	= s.REINSTMT_PREM_PCT
		FROM dbo.MAP_CONTRACT_EDW 		c
		LEFT JOIN dbo.ATT_CNTRCT_SEC 	s	ON c.CNTRCT_SEC = s.BE_ID
		WHERE c.CNTRCT_SEC <> '$nooid'
		  AND s.REINSTMT_FREE IS NOT NULL
		  AND RIGHT(CNTRCT_SEC_NBR,1 ) ='1'
		  AND s.END_DATE='9999-12-31 00:00:00.000'
		
		UPDATE dc
		SET Free                      = bcs.Free,
            NumberAllowed             = bcs.NumberAllowed,
		    ProRataAsToTime           = bcs.ProRataAsToTime,
		    ProRataAsToAmt            = bcs.ProRataAsToAmt,
		    ReinstatementBrokeragePct = bcs.ReinstatementBrokeragePct,
		    ReinstatementPremiumPct   = bcs.ReinstatementPremiumPct
		FROM #DimContract dc
		JOIN #BridgeContractSections bcs
		    ON dc.CONTRACT_NBR = bcs.CONTRACT_NBR COLLATE DATABASE_DEFAULT
			
		DROP TABLE IF EXISTS #ProfitComission
		CREATE TABLE #ProfitComission (
			[CONTRACT_NBR]                VARCHAR(255)  NULL,
			[management_base]             VARCHAR(30)   NULL,
			[Management_Expense_%]        NUMERIC(10,6) NULL,
			[First_adjustment_date]       DATETIME		NULL,
			[Last_adjustment_date]        DATETIME		NULL,
			[Deficit_carry_forward]       INT			NULL,
			[Profit_comission]            NUMERIC(10,6)	NULL,
			[block_basis_start]           DATETIME		NULL,
			[block_basis_end]             DATETIME		NULL
		)
		
		INSERT INTO #ProfitComission (
			[CONTRACT_NBR],
			[management_base],
			[Management_Expense_%],
			[First_adjustment_date],
			[Last_adjustment_date],
			[Deficit_carry_forward],
			[Profit_comission],
			[block_basis_start],
			[block_basis_end]
		)
		SELECT
			CONCAT(T.trty_no, T.und_yr) AS contract_nbr,
			M.desc_txt                  AS management_base,       -- Management Base (Section A of treaty) 
			P.mgt_xpns1_pct             AS [Management_Expense_%],
			P.pft_first_adj_dt          AS First_adjustment_date,
			P.pft_final_adj_dt          AS Last_adjustment_date,
			P.carry_fwd_cr_idx          AS Deficit_carry_forward, -- Deficit / Other Adjustment  notes  Do we need to  pull
			P.pft_comm1_pct             AS Profit_comission,
			P.pft_beg_block_dt			AS block_basis_start,
			P.pft_end_block_dt			AS block_basis_end
		FROM SRC_TIRS_DB.dbo.trty_acq_xpns 			A
		INNER JOIN SRC_TIRS_DB.dbo.trty_pft_comm 	P 	ON A.acq_key = P.acq_key
		INNER JOIN SRC_TIRS_DB.dbo.trty_section 	sec ON A.section_key = sec.section_key ---added by rmotiani 09/03/2009 to get section_no
		RIGHT JOIN SRC_TIRS_DB.dbo.trty_master 		T 	ON P.trty_key = T.trty_key
		INNER JOIN SRC_TIRS_DB.dbo.xrf_mgt_base_cds M 	ON M.mgt_xpns_base_cd = P.mgt_xpns1_base_cd
		WHERE sec.section_no = 1
		
		UPDATE dc
		SET [management_base] 		= pc.[management_base],
			[Management_Expense_%] 	= pc.[Management_Expense_%],
			[First_adjustment_date] = pc.[First_adjustment_date],
			[Last_adjustment_date] 	= pc.[Last_adjustment_date],
			[Deficit_carry_forward] = pc.[Deficit_carry_forward],
			[Profit_comission] 		= pc.[Profit_comission],
			[block_basis_start] 	= pc.[block_basis_start],
			[block_basis_end] 		= pc.[block_basis_end]
		FROM #DimContract 		dc
		JOIN #ProfitComission 	pc	ON dc.CONTRACT_NBR = pc.CONTRACT_NBR COLLATE DATABASE_DEFAULT
			
		DROP TABLE IF EXISTS #BrokerFee
		CREATE TABLE #BrokerFee (
			[CONTRACT_NBR]                VARCHAR(255)  NULL,
			[Broker_Fee_Basis]            VARCHAR(30)   NULL,
			[BrokerFee_Percentage]        NUMERIC(10,6) NULL,
			[cedng_comm_flat_pct]         VARCHAR(30)   NULL,
			[cedng_comm_ovrrd_orig_pls]   VARCHAR(30)   NULL
		)

		INSERT INTO #BrokerFee
			([CONTRACT_NBR]
			,[Broker_Fee_Basis]
			,[BrokerFee_Percentage]
			,[cedng_comm_flat_pct]
			,[cedng_comm_ovrrd_orig_pls])
		SELECT
			 [CONTRACT_NBR]			= RTRIM(LTRIM(CAST(trty_no AS CHAR(5)) + CAST(und_yr AS CHAR(4)))) COLLATE Latin1_General_CI_AI
			,[Broker_Fee_Basis]		= BRKRG_OF
			,[BrokerFee_Percentage] = BRKRG_PCT
			,[cedng_comm_flat_pct]
			,[cedng_comm_ovrrd_orig_pls]
		  FROM [SRC_TIRS_DB].ssis.vw_TIRS_UW_ContractSection_SubjBus
		WHERE section_no = 1
		
		UPDATE dc
		SET [Broker_Fee_Basis] 		= bf.[Broker_Fee_Basis],
			[BrokerFee_Percentage] 	= bf.[BrokerFee_Percentage],
			[cedng_comm_flat_pct] 	= bf.[cedng_comm_flat_pct],
			[cedng_comm_ovrrd_orig_pls] = bf.[cedng_comm_ovrrd_orig_pls]
		FROM #DimContract 	dc
		JOIN #BrokerFee 	bf	ON dc.CONTRACT_NBR = bf.CONTRACT_NBR COLLATE DATABASE_DEFAULT

		DROP TABLE IF EXISTS #Frequency

		SELECT x.PaymentFrequencyCode
			,x.PaymentFrequency
			,MinDays = x.PeriodDays - x.DaysAllowance
			,MaxDays = x.PeriodDays + x.DaysAllowance
		INTO #Frequency
		FROM (
			VALUES ('M', 'Monthly', 30, 4)
				,('Q', 'Quarterly', 92, 8)
				,('S', 'Semi-Annual', 183, 12)
				,('A', 'Annual', 365, 16)
				,('F', 'Full', 0, 0)
			) x (PaymentFrequencyCode, PaymentFrequency, PeriodDays, DaysAllowance)

		DROP TABLE IF EXISTS #PremiumFrequency
		CREATE TABLE #PremiumFrequency (
			[CONTRACT_NBR]          VARCHAR(255)NULL,
			[premium_frequency_cd]  CHAR(1)		NULL,
			[premium_frequency]     VARCHAR(30)	NULL,
			[remittance_days]  		INT			NULL
		)

		INSERT INTO #PremiumFrequency (
			 [CONTRACT_NBR]
			,[premium_frequency_cd]
			,[premium_frequency]
			,[remittance_days])
		SELECT
			 [CONTRACT_NBR]			= RTRIM(LTRIM(CAST (trty_no as char(5)) + cast (und_yr as char(4))))COLLATE DATABASE_DEFAULT
			,[premium_frequency_cd]	= tm.deposit_freq_cd COLLATE DATABASE_DEFAULT
			,[premium_frequency]	= cf.desc_txt COLLATE DATABASE_DEFAULT
			,[remittance_days]		= tm.remit_days 
		FROM SRC_TIRS_DB.dbo.trty_master		tm
		LEFT JOIN SRC_TIRS_DB.dbo.xrf_cal_freq	cf	ON cf.cal_freq_cd = tm.deposit_freq_cd
		UNION ALL
		-- Openbox
		SELECT z.CONTRACT_NBR COLLATE DATABASE_DEFAULT
			,premium_frequency_cd = COALESCE(f.PaymentFrequencyCode, 'C')
			,premium_frequency = COALESCE(f.PaymentFrequency, 'Custom')
			,remittance_days = NULL
		FROM (
			SELECT y.CONTRACT_NBR
				,MinDaysBetweenDueDates = MIN(y.MinDaysBetweenDueDates)
				,MaxDaysBetweenDueDates = MAX(y.MinDaysBetweenDueDates)
			FROM (
				SELECT x.CONTRACT_NBR
					,x.PolicyLiabilityID
					,MinDaysBetweenDueDates = COALESCE(MIN(x.DaysUntilNextDueDate), 0)
					,MaxDaysBetweenDueDates = COALESCE(MAX(x.DaysUntilNextDueDate), 0)
				FROM (
					SELECT CONTRACT_NBR = mce.CONTRACT_NBR
						,PolicyLiabilityID = plci.lPolicyLiabilityKey
						,DaysUntilNextDueDate = DATEDIFF(day, plci.DTDUE, LEAD(plci.DTDUE) OVER (PARTITION BY plci.lPolicyLiabilityKey ORDER BY plci.DTDUE))
					FROM SRC_LLOYDS_DB.dbo.PolicyLiabilityCustomInstalment plci
					INNER JOIN SRC_LLOYDS_DB.dbo.PolicySection ps
						ON ps.lPolicySectionKey = plci.lPolicySectionKey
						AND ps.lPolicyActivityKey = plci.lPolicyActivityKey
					INNER JOIN SRC_LLOYDS_DB.dbo.PolicyActivity pa
						ON pa.lPolicyActivityKey = ps.lPolicyActivityKey
					INNER JOIN SRC_LLOYDS_DB.dbo.Policy p
						ON p.lPolicyKey = ps.lPolicyKey
						AND p.lActivePolicyActivityKey = ps.lPolicyActivityKey
					INNER JOIN SRC_LLOYDS_DB.dbo.Typeofreportinglayer torl
						ON torl.lTypeOfReportingLayerKey = pa.lTypeOfReportingLayerKey
					INNER JOIN SRC_LLOYDS_DB.dbo.TypeOfProductgroup topg
						ON topg.lTypeOfProductGroupKey = torl.lTypeOfProductGroupKey
						AND topg.sCode = 'RI'
					INNER JOIN (
						SELECT DISTINCT mce.CONTRACT_NBR
							,mce.CONTRACT_REFERENCE
						FROM EDW_PREPROD.dbo.MAP_CONTRACT_EDW mce
						WHERE PLCY_SRC = 'OPENBOX'
						) mce
						ON mce.CONTRACT_REFERENCE = p.sPolicyReference COLLATE DATABASE_DEFAULT
					) x
				GROUP BY x.CONTRACT_NBR
					,x.PolicyLiabilityID
				) y
			GROUP BY y.CONTRACT_NBR
			) z
		LEFT JOIN #Frequency f
			ON f.MinDays <= z.MinDaysBetweenDueDates
			AND f.MaxDays >= z.MaxDaysBetweenDueDates

		UPDATE dc
		SET [premium_frequency_cd] 	= pf.premium_frequency_cd,
			[remittance_days] 		= pf.remittance_days,
			[premium_frequency] 	= pf.premium_frequency
		FROM #DimContract 		dc
		JOIN #PremiumFrequency 	pf	ON dc.CONTRACT_NBR = pf.CONTRACT_NBR COLLATE DATABASE_DEFAULT

		DROP TABLE IF EXISTS #PremiumTax
		CREATE TABLE #PremiumTax (
			[CONTRACT_NBR]	VARCHAR(255)  NULL,
			[prem_tax_pct]	NUMERIC(10,6) NULL
		)
        INSERT INTO #PremiumTax
			([CONTRACT_NBR]
			,[prem_tax_pct])
		SELECT
			 x.contract_nbr
        	,x.prem_tax_pct
        FROM (
        	SELECT
				 contract_nbr 	= RTRIM(LTRIM(CAST (trty_no AS CHAR(5)) + CAST (und_yr AS CHAR(4))))COLLATE Latin1_General_CI_AI
        		,prem_tax_pct	= tax.prem_tax_pct
        		,MostRecent		= ROW_NUMBER() OVER (PARTITION BY tm.trty_no, tm.und_yr ORDER BY tm.trty_key DESC)
        	FROM SRC_TIRS_DB.dbo.trty_master 			tm
        	INNER JOIN SRC_TIRS_DB.dbo.trty_section 	ts	ON  ts.trty_key = tm.trty_key
															AND ts.section_no = 1
        	INNER JOIN SRC_TIRS_DB.dbo.trty_acq_xpns 	tax	ON  tax.section_key = ts.section_key
        	) x
        WHERE x.MostRecent = 1

		UPDATE dc
		 SET prem_tax_pct = pt.prem_tax_pct
		FROM #DimContract	dc
		JOIN #PremiumTax	pt	ON dc.CONTRACT_NBR = pt.CONTRACT_NBR COLLATE DATABASE_DEFAULT

		UPDATE dc
		 SET treaty_type = m.TREATY_TYPE
		FROM #DimContract dc
		JOIN assumed.MappingTreatyType	 m	ON  m.TRTY_FAC_NAME		 COLLATE DATABASE_DEFAULT = dc.policy_type
											AND m.PRO_RATA_XOL_NAME  COLLATE DATABASE_DEFAULT = dc.PRO_RATA_XOL_NAME
											AND m.RPT_OFF_NAME		 COLLATE DATABASE_DEFAULT = dc.ReportingOffice

		UPDATE dc
		 SET Ultimate_Loss_Ratio = CAST(ROUND(v.Ultimate_Loss_Ratio, 4) AS NUMERIC(10,4))
		FROM #DimContract	dc
		INNER JOIN EDW_PREPROD.assumed.GetUltimateLossRatioPerContract()	v
			    ON dc.CONTRACT_NBR = v.contract_nbr COLLATE DATABASE_DEFAULT
	
		DROP TABLE IF EXISTS #PolicyCoverageType
		SELECT
			 policy_coverage_type_cd= xcc.coverage_cd
			,policy_coverage_type	= xcc.desc_txt
			,PLCY_SRC				= dc.PLCY_SRC
			,CONTRACT_NBR			= dc.CONTRACT_NBR
		INTO #PolicyCoverageType
		FROM EDW_PREPROD.assumed.DimContract 		dc
		INNER JOIN SRC_TIRS_DB.dbo.trty_master 		tm	ON CONCAT(LEFT(tm.trty_no, 5), tm.und_yr) = dc.CONTRACT_NBR COLLATE DATABASE_DEFAULT
		INNER JOIN SRC_TIRS_DB.dbo.trty_section 	ts	ON ts.trty_key = tm.trty_key AND ts.section_no = 1
		INNER JOIN SRC_TIRS_DB.dbo.xrf_coverage_cds xcc	ON xcc.coverage_cd = ts.coverage_cd
		WHERE dc.PLCY_SRC = 'TIRS'
		UNION ALL
		SELECT
			 policy_coverage_type_cd= xcc.coverage_cd
			,policy_coverage_type	= xcc.desc_txt
			,PLCY_SRC				= dc.PLCY_SRC
			,CONTRACT_NBR			= dc.CONTRACT_NBR
		FROM EDW_PREPROD.assumed.DimContract 		dc
		LEFT JOIN SRC_TIRS_DB.dbo.xrf_coverage_cds 	xcc		ON xcc.coverage_cd = 1
		WHERE dc.PLCY_SRC = 'OPENBOX'
		
		UPDATE dc
		 SET policy_coverage_type_cd = v.policy_coverage_type_cd,
			 policy_coverage_type	 = v.policy_coverage_type
		FROM #DimContract 				dc
		INNER JOIN #PolicyCoverageType	v	ON  dc.CONTRACT_NBR = v.CONTRACT_NBR COLLATE DATABASE_DEFAULT
											AND dc.PLCY_SRC		= v.PLCY_SRC COLLATE DATABASE_DEFAULT

		-- ensure that there are no duplicates on CONTRACT_REFERENCE for Openbox
		DELETE x
		FROM (
			SELECT Instance = ROW_NUMBER() OVER (PARTITION BY CONTRACT_REFERENCE ORDER BY LEN(CONTRACT_NBR) DESC)
			FROM #DimContract dc
			WHERE PLCY_SRC = 'OPENBOX'
				AND CONTRACT_REFERENCE IS NOT NULL
			) x
		WHERE x.Instance > 1


		------------------------------------------------------------
		-- Loading logic
		------------------------------------------------------------
		ALTER TABLE #DimContract ADD DataHash BINARY(20) NULL
		ALTER TABLE #DimContract ADD DataHashType1 BINARY(20) NULL

		UPDATE s
		SET DataHash = HASHBYTES('SHA1', CONCAT(s.BE_ID
			, '|', s.UNDERWRITING_YEAR
			, '|', s.ASSUMED_CEDED_FLG))
		FROM #DimContract s

		UPDATE s
		SET DataHashType1 = HASHBYTES('SHA1', CONCAT(s.inception_date
			, '|', s.[expiry_date]
			, '|', s.[new_renewal]
			, '|', s.[policy_coverage_type]
			, '|', s.[underwriter_code]
			, '|', s.[policy_source]
			, '|', s.[source_key]
			, '|', s.[policy_status]
			, '|', s.[cedant_code]
			, '|', s.[broker_code]
			, '|', s.[broker_ref]
			, '|', s.[branch_code]
			, '|', s.[sif_oif]
			, '|', s.[division_code]
			, '|', s.[department_code]
			, '|', s.[sub_department_code]
			, '|', s.[division_name]
			, '|', s.[department_name]
			, '|', s.[sub_department_name]
			, '|', s.[attachment_basis_name]
			, '|', s.[pro_rata_xol_name]
			, '|', s.[ceding_company_reference]
			, '|', s.[group_name]
			, '|', s.[is_processed_by_claims_department]
			, '|', s.[billing_company_code]
			, '|', s.[billing_company_reference]
			, '|', s.[policy_name]
			, '|', s.[policy_type]
			, '|', s.[effective_date]
			, '|', s.[awac_lead]
			, '|', s.[expos_cd]
			, '|', s.[expos_name]
			, '|', s.[DimBillingID]
			, '|', s.[DimAssuredID]
			, '|', s.[DimBrokerID]
			, '|', s.[DimMGAID]
	        , '|', s.[DimSchdlCompanyNameID]
	        , '|', s.[DimTPAID]
			, '|', s.[ReportingOfficeCode]
			, '|', s.[ReportingOffice] 
			, '|', s.[L01]
	        , '|', s.[AWAC_Estimated_Premium]
			, '|', s.[ROL]
			, '|', s.[Free]                     
			, '|', s.[NumberAllowed]            
			, '|', s.[ProRataAsToTime]          
			, '|', s.[ProRataAsToAmt]           
			, '|', s.[ReinstatementBrokeragePct]
			, '|', s.[ReinstatementPremiumPct]
			, '|', s.[management_base]
			, '|', s.[Management_Expense_%]
			, '|', s.[First_adjustment_date]
			, '|', s.[Last_adjustment_date]
			, '|', s.[Deficit_carry_forward]
			, '|', s.[Profit_comission]
			, '|', s.[Broker_Fee_Basis]
			, '|', s.[BrokerFee_Percentage]
			, '|', s.[cedng_comm_flat_pct]
			, '|', s.[cedng_comm_ovrrd_orig_pls]
			, '|', s.[block_basis_start]
			, '|', s.[block_basis_end]
			, '|', s.[puk_code]
			, '|', s.[puk_name]
			, '|', s.[premium_frequency_cd]
			, '|', s.[remittance_days]
			, '|', s.[premium_frequency]
			, '|', s.[prem_tax_pct]
			, '|', s.[Ultimate_Loss_Ratio]
			, '|', s.[treaty_type]
			, '|', s.[treaty_accounting_mode]
			, '|', s.[policy_coverage_type_cd]
			, '|', s.[original_underwriter_name]
			, '|', s.[SourceCreatedDate]
			, '|', s.[AWAC_limit_USD]
			, '|', s.[limit_attachment_USD]
			, '|', s.[pml_amount_USD]	
			, '|', s.[CONTRACT_REFERENCE]
			))
		FROM #DimContract s

		DROP TABLE IF EXISTS #LoadOperation
		CREATE TABLE #LoadOperation (
			 [CONTRACT_NBR] VARCHAR(255) COLLATE DATABASE_DEFAULT NULL
			,[PLCY_SRC]		VARCHAR(255) COLLATE DATABASE_DEFAULT NULL
			,[Operation]	CHAR(1) NOT NULL
		,UNIQUE (CONTRACT_NBR, PLCY_SRC)
		)

		INSERT INTO #LoadOperation (
			 [CONTRACT_NBR]
			,[PLCY_SRC]
			,[Operation]
			)
		SELECT
			 CONTRACT_NBR	= COALESCE(t.CONTRACT_NBR COLLATE DATABASE_DEFAULT, s.CONTRACT_NBR COLLATE DATABASE_DEFAULT)
			,PLCY_SRC		= COALESCE(t.PLCY_SRC COLLATE DATABASE_DEFAULT, s.PLCY_SRC COLLATE DATABASE_DEFAULT)
			,Operation		= CASE	WHEN t.DimContractID IS NULL 
									THEN 'I' 
									WHEN s.DataHash IS NULL
									THEN 'D' 
									WHEN t.DataHash != s.DataHash AND t.DataHashType1 != s.DataHashType1 
									THEN 'U' 
									WHEN t.DataHash != s.DataHash 
									THEN '2' 
									ELSE '1' END
		FROM (SELECT *
				FROM assumed.DimContract
			   WHERE EndDate = '31 Dec 9999' ) t
		FULL JOIN #DimContract	s
			   ON COALESCE(s.CONTRACT_NBR, '^&*')	= COALESCE(t.CONTRACT_NBR, '^&*') COLLATE DATABASE_DEFAULT
			  AND COALESCE(s.PLCY_SRC, '^&*')		= COALESCE(t.PLCY_SRC, '^&*') COLLATE DATABASE_DEFAULT
		WHERE t.DataHash IS NULL
		   OR s.DataHash IS NULL
		   OR t.DataHash != s.DataHash
		   OR t.DataHashType1 != s.DataHashType1

		------------------------------------------------------------
		------------------------------------------------------------
		BEGIN TRAN

		UPDATE t
		SET  [UpdateDate] 				= p.NewStartDate
			,[inception_date] 			= s.inception_date
			,[expiry_date] 				= s.expiry_date
			,[new_renewal] 				= s.new_renewal
			,[policy_coverage_type] 	= s.policy_coverage_type
			,[underwriter_code] 		= s.underwriter_code
			,[policy_source] 			= s.policy_source
			,[source_key] 				= s.source_key
			,[policy_status] 			= s.policy_status
			,[cedant_code] 				= s.cedant_code
			,[broker_code] 				= s.broker_code
			,[broker_ref] 				= s.broker_ref
			,[branch_code] 				= s.branch_code
			,[sif_oif] 					= s.sif_oif
			,[division_code] 			= s.division_code
			,[department_code] 			= s.department_code
			,[sub_department_code] 		= s.sub_department_code
			,[division_name] 			= s.division_name
			,[department_name] 			= s.department_name
			,[sub_department_name] 		= s.sub_department_name
			,[attachment_basis_name] 	= s.attachment_basis_name
			,[pro_rata_xol_name] 		= s.pro_rata_xol_name
			,[ceding_company_reference] = s.ceding_company_reference
			,[group_name]				= s.group_name
			,[is_processed_by_claims_department] = s.is_processed_by_claims_department
			,[billing_company_code]		= s.billing_company_code
			,[billing_company_reference]= s.billing_company_reference
			,[policy_name] 				= s.policy_name
			,[policy_type] 				= s.policy_type
			,[effective_date] 			= s.effective_date
			,[awac_lead] 				= s.awac_lead
			,[puk_code] 				= s.puk_code
			,[puk_name] 				= s.puk_name
			,[DimBillingID]				= s.DimBillingID
			,[DimAssuredID]				= s.DimAssuredID
			,[DimBrokerID] 				= s.DimBrokerID 
			,[DimMGAID] 				= s.DimMGAID
			,[DimSchdlCompanyNameID]	= s.DimSchdlCompanyNameID
			,[DimTPAID]					= s.DimTPAID
			,[ReportingOfficeCode] 		= s.ReportingOfficeCode
			,[ReportingOffice] 			= s.ReportingOffice
			,[L01] 						= s.L01
			,[AWAC_Estimated_Premium]	= s.AWAC_Estimated_Premium
			,[ROL] 						= s.ROL
            ,[Free] 					= s.Free
            ,[NumberAllowed] 			= s.NumberAllowed
		    ,[ProRataAsToTime] 			= s.ProRataAsToTime
		    ,[ProRataAsToAmt] 			= s.ProRataAsToAmt
		    ,[ReinstatementBrokeragePct]= s.ReinstatementBrokeragePct
		    ,[ReinstatementPremiumPct]	= s.ReinstatementPremiumPct
			,[management_base] 			= s.management_base
			,[Management_Expense_%]		= s.[Management_Expense_%]
			,[First_adjustment_date]	= s.First_adjustment_date
			,[Last_adjustment_date]		= s.Last_adjustment_date
			,[Deficit_carry_forward]	= s.Deficit_carry_forward
			,[Profit_comission]			= s.Profit_comission
			,[Broker_Fee_Basis]			= s.Broker_Fee_Basis
			,[BrokerFee_Percentage]		= s.BrokerFee_Percentage
			,[cedng_comm_flat_pct] 		= s.cedng_comm_flat_pct
			,[cedng_comm_ovrrd_orig_pls]= s.cedng_comm_ovrrd_orig_pls
			,[block_basis_start] 		= s.block_basis_start
			,[block_basis_end] 			= s.block_basis_end
			,[expos_cd] 				= s.expos_cd
			,[expos_name] 				= s.expos_name
			,[premium_frequency_cd] 	= s.premium_frequency_cd
			,[remittance_days]			= s.remittance_days
			,[premium_frequency]		= s.premium_frequency
			,[prem_tax_pct] 			= s.prem_tax_pct
			,[Ultimate_Loss_Ratio]		= s.Ultimate_Loss_Ratio
			,[treaty_type]				= s.treaty_type
			,[treaty_accounting_mode] 	= s.treaty_accounting_mode
			,[policy_coverage_type_cd]	= s.policy_coverage_type_cd
			,[original_underwriter_name]= s.original_underwriter_name
			,[SourceCreatedDate]      	= s.SourceCreatedDate
			,[AWAC_limit_USD]  			= s.AWAC_limit_USD
			,[limit_attachment_USD]  	= s.limit_attachment_USD
			,[pml_amount_USD]	  		= s.pml_amount_USD
			,[CONTRACT_REFERENCE]		= s.CONTRACT_REFERENCE
			,[DataHashType1]			= s.DataHashType1
		 FROM assumed.DimContract	t
		INNER JOIN #LoadOperation	lo	ON  COALESCE(lo.CONTRACT_NBR, '^&*')= COALESCE(t.CONTRACT_NBR, '^&*')
										AND COALESCE(lo.PLCY_SRC, '^&*')	= COALESCE(t.PLCY_SRC, '^&*')
										AND lo.Operation IN ('U', '1')
		INNER JOIN #DimContract		s	ON  COALESCE(s.CONTRACT_NBR, '^&*') = COALESCE(t.CONTRACT_NBR, '^&*') COLLATE DATABASE_DEFAULT
										AND COALESCE(s.PLCY_SRC, '^&*')		= COALESCE(t.PLCY_SRC, '^&*') COLLATE DATABASE_DEFAULT
		CROSS JOIN #Parameters		p
		WHERE p.NewStartDate BETWEEN t.StartDate AND t.EndDate

		UPDATE t
		 SET EndDate = p.ClosingEndDate
		FROM assumed.DimContract	t
		INNER JOIN #LoadOperation	lo	ON  COALESCE(lo.CONTRACT_NBR, '^&*')= COALESCE(t.CONTRACT_NBR, '^&*')
										AND COALESCE(lo.PLCY_SRC, '^&*') 	= COALESCE(t.PLCY_SRC, '^&*')
										AND lo.Operation IN ('U', '2')
		CROSS JOIN #Parameters		p
		WHERE t.EndDate = '31 Dec 9999'

		INSERT INTO assumed.DimContract
			([StartDate]
			,[UpdateDate]
			,[BE_ID]
			,[CONTRACT_NBR]
			,[PLCY_SRC]
			,[UNDERWRITING_YEAR]
			,[ASSUMED_CEDED_FLG]
			,[inception_date]
			,[expiry_date]
			,[new_renewal]
			,[policy_coverage_type]
			,[underwriter_code]
			,[policy_source]
			,[source_key]
			,[policy_status]
			,[cedant_code]
			,[broker_code]
			,[broker_ref]
			,[branch_code]
			,[sif_oif]
			,[division_code]
			,[department_code]
			,[sub_department_code]
			,[division_name]
			,[department_name]
			,[sub_department_name]
			,[attachment_basis_name]
			,[pro_rata_xol_name]
			,[ceding_company_reference]
			,[group_name]
			,[is_processed_by_claims_department]
			,[billing_company_code]
			,[billing_company_reference]
			,[policy_name]
			,[policy_type]
			,[effective_date]
			,[awac_lead]
			,[puk_code]
			,[puk_name]
			,[DimBillingID]
			,[DimAssuredID]
			,[DimBrokerID] 
			,[DimMGAID]
			,[DimSchdlCompanyNameID]
			,[DimTPAID]
			,[ReportingOfficeCode]
			,[ReportingOffice] 
			,[L01]
			,[AWAC_Estimated_Premium]
			,[ROL]
			,[Free]                     
			,[NumberAllowed]            
			,[ProRataAsToTime]          
			,[ProRataAsToAmt]           
			,[ReinstatementBrokeragePct]
			,[ReinstatementPremiumPct]
			,[management_base]
			,[Management_Expense_%]
			,[First_adjustment_date]
			,[Last_adjustment_date]
			,[Deficit_carry_forward]
			,[Profit_comission]
			,[Broker_Fee_Basis]
			,[BrokerFee_Percentage]
			,[cedng_comm_flat_pct]
			,[cedng_comm_ovrrd_orig_pls]
			,[block_basis_start]
			,[block_basis_end]
			,[expos_cd]
			,[expos_name]
			,[premium_frequency_cd] 
			,[premium_frequency]    
			,[remittance_days]  
			,[prem_tax_pct]
			,[Ultimate_Loss_Ratio]
			,[treaty_type]
			,[treaty_accounting_mode]
			,[policy_coverage_type_cd]
			,[original_underwriter_name]
			,[SourceCreatedDate]
			,[AWAC_limit_USD]
			,[limit_attachment_USD] 
			,[pml_amount_USD]
			,[CONTRACT_REFERENCE]
			,[DataHash]
			,[DataHashType1]
			)
		SELECT
			 StartDate  = p.NewStartDate
			,UpdateDate = p.NewStartDate
			,s.BE_ID
			,s.CONTRACT_NBR
			,s.PLCY_SRC
			,s.UNDERWRITING_YEAR
			,s.ASSUMED_CEDED_FLG
			,s.inception_date
			,s.expiry_date
			,s.new_renewal
			,s.policy_coverage_type
			,s.underwriter_code
			,s.policy_source
			,s.source_key
			,s.policy_status
			,s.cedant_code
			,s.broker_code
			,s.broker_ref
			,s.branch_code
			,s.sif_oif
			,s.division_code
			,s.department_code
			,s.sub_department_code
			,s.division_name
			,s.department_name
			,s.sub_department_name
			,s.attachment_basis_name
			,s.pro_rata_xol_name
			,s.ceding_company_reference
			,s.group_name
			,s.is_processed_by_claims_department
			,s.billing_company_code
			,s.billing_company_reference
			,s.policy_name
			,s.policy_type
			,s.effective_date
			,s.awac_lead
			,s.puk_code
			,s.puk_name
			,s.DimBillingID
			,s.DimAssuredID
			,s.DimBrokerID 
			,s.DimMGAID
			,s.DimSchdlCompanyNameID
			,s.DimTPAID
			,s.ReportingOfficeCode
			,s.ReportingOffice 
			,s.L01
			,s.AWAC_Estimated_Premium
			,s.ROL
			,s.Free                   
			,s.NumberAllowed         
			,s.ProRataAsToTime   
			,s.ProRataAsToAmt        
			,s.ReinstatementBrokeragePct
			,s.ReinstatementPremiumPct
			,s.management_base
			,s.[Management_Expense_%]
			,s.First_adjustment_date
			,s.Last_adjustment_date
			,s.Deficit_carry_forward
			,s.Profit_comission
			,s.Broker_Fee_Basis
			,s.BrokerFee_Percentage
			,s.cedng_comm_flat_pct
			,s.cedng_comm_ovrrd_orig_pls
			,s.block_basis_start
			,s.block_basis_end
			,s.expos_cd
			,s.expos_name
			,s.premium_frequency_cd 
			,s.premium_frequency    
			,s.remittance_days  
			,s.prem_tax_pct
			,s.Ultimate_Loss_Ratio
			,s.treaty_type
			,s.treaty_accounting_mode
			,s.policy_coverage_type_cd
			,s.original_underwriter_name
			,s.SourceCreatedDate
			,s.AWAC_limit_USD
			,s.limit_attachment_USD
			,s.pml_amount_USD	
			,s.CONTRACT_REFERENCE
			,s.DataHash
			,s.DataHashType1
		 FROM #DimContract			s
		INNER JOIN #LoadOperation	lo	ON  COALESCE(lo.CONTRACT_NBR, '^&*')= COALESCE(s.CONTRACT_NBR, '^&*') COLLATE DATABASE_DEFAULT
										AND COALESCE(lo.PLCY_SRC, '^&*') 	= COALESCE(s.PLCY_SRC, '^&*') COLLATE DATABASE_DEFAULT
										AND lo.Operation IN ('I', 'U', '2')
		CROSS JOIN #Parameters 		p

		COMMIT
		------------------------------------------------------------
		------------------------------------------------------------		
		DECLARE @ProcessName 		VARCHAR(100)= OBJECT_SCHEMA_NAME(@@PROCID) + '.' + OBJECT_NAME(@@PROCID)
		DECLARE @RowsProcessed 		BIGINT 		= COALESCE((SELECT COUNT(0) FROM #LoadOperation WHERE Operation IN ('I', 'U')), 0)
		DECLARE @LastIdentity 		BIGINT		= SCOPE_IDENTITY()
		DECLARE @ProcessingStarted 	DATETIME 	= (SELECT p.NewStartDate FROM #Parameters p)
		DECLARE @ProcessingEnded 	DATETIME 	= GETDATE()
		DECLARE @SourceDataDate 	DATETIME 	= (SELECT [sql_date] FROM ETL.dbo.[day] WHERE today = 1)

		EXEC ETL.dbo.update_etl_controller
			 @ps_process_name			= @ProcessName
			,@pn_rows_processed 		= @RowsProcessed
			,@pdt_data_datetime 		= @SourceDataDate
			,@pdt_process_start_datetime= @ProcessingStarted
			,@pdt_process_end_datetime 	= @ProcessingEnded
			,@pn_error_number 			= 0
			,@ps_comment 				= NULL
			,@pn_max_processed_event_id = @LastIdentity
	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > 0
		BEGIN
			ROLLBACK
		END

		DECLARE @ErrorDescription	VARCHAR(8000) = CONCAT('Error: ', ERROR_NUMBER(), ' - ', ERROR_MESSAGE(), '; ', 'Occurred in procedure: ' + ERROR_PROCEDURE() + ', ', 'Line ', ERROR_LINE())
		DECLARE @ErrorNumber		INT			  = ERROR_NUMBER()
		DECLARE @ErrorMessage		VARCHAR(8000) = ERROR_MESSAGE()
		DECLARE @ErrorSeverity		INT			  = ERROR_SEVERITY()
		DECLARE @ErrorState			INT			  = ERROR_STATE()
		DECLARE @ProcessNameC		VARCHAR(100)  = OBJECT_SCHEMA_NAME(@@PROCID) + '.' + OBJECT_NAME(@@PROCID)
		DECLARE @ProcessingStartedC DATETIME	  = (SELECT p.NewStartDate FROM #Parameters p)
		DECLARE @ProcessingEndedC	DATETIME	  = GETDATE()
		DECLARE @SourceDataDateC	DATETIME	  = (SELECT [sql_date] FROM ETL.dbo.[day] WHERE today = 1)

		EXEC ETL.dbo.update_etl_controller
			 @ps_process_name			= @ProcessNameC
			,@pn_rows_processed			= 0
			,@pdt_data_datetime			= @SourceDataDateC
			,@pdt_process_start_datetime= @ProcessingStartedC
			,@pdt_process_end_datetime	= @ProcessingEndedC
			,@pn_error_number			= @ErrorNumber
			,@ps_comment				= @ErrorDescription
			,@pn_max_processed_event_id = 0

		EXEC ETL.dbo.insert_error_log
			 @process_name	= @ProcessNameC
			,@object_name	= 0
			,@user_message	= @ErrorDescription
			,@status		= 0
			,@remedy		= 'Contact EDW team'

		RAISERROR(@ErrorDescription, @ErrorSeverity, @ErrorState)
	END CATCH
END

