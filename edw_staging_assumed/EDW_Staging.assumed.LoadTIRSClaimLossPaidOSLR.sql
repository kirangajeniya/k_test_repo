-- Database: EDW_Staging
-- Schema: assumed
-- Procedure: LoadTIRSClaimLossPaidOSLR

CREATE   PROCEDURE assumed.LoadTIRSClaimLossPaidOSLR
AS
BEGIN TRY
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
		-------------------------------------------------------

		DROP TABLE IF EXISTS #Parameters

		SELECT ClosingEndDate = DATEADD(NANOSECOND, -100, SYSDATETIME())
			,NewStartDate = SYSDATETIME()
		INTO #Parameters

		-- Staging logic
		
		DROP TABLE IF EXISTS #TIRSClaimLossPaidOSLR
		
		SELECT x.TREATY_NBR
			,x.UNDERWRITING_YEAR
			,x.CONTRACT_NBR
			,x.CEDED_CONTRACT_NBR
			,y.DataSet
			,x.trans_key
			,x.trans_cd
			,x.entry_dt
			,x.section_key
			,y.FromDate
			,y.ToDate
			,x.ORIGCURR_CD
			,x.TIRS_ORIG_CURR_CD
			,x.TIRS_ORIG_CURR_NAME
			,x.TIRS_LOB_NAME
			,x.AccidentYear
			,x.ClaimLossDate
			,x.REG_DATE
			,x.ASLOB
			,x.assumed_ceded_flg
			,x.CAT_KEY
			,x.CatCode
			,x.TIRS_CLM_CD
			,x.Claim_NBR
			,x.bill_co_br_key
			,y.Summable_LOSS_PAID
			,y.SUMMABLE_LAE
			,y.SUMMABLE_LOSS_PAID_USD
			,y.SUMMABLE_LAE_USD
			,y.Summable_OS_LOSS
			,y.Summable_os_loss_exp
			,y.Summable_OS_LOSS_USD
			,y.Summable_os_loss_exp_USD
			,y.SUMMABLE_reinstatement_premium
			,y.SUMMABLE_reinstatement_premium_USD
			,x.solvency_II_regulatory_key
			,x.claim_description
		INTO #TIRSClaimLossPaidOSLR
		FROM (
			SELECT TREATY_NBR = TRIM(CAST(tm.trty_no AS VARCHAR(5))) COLLATE DATABASE_DEFAULT
				,UNDERWRITING_YEAR = TRIM(CAST(tm.und_yr AS VARCHAR(4))) COLLATE DATABASE_DEFAULT
				,CONTRACT_NBR = TRIM(CAST(tm.trty_no AS CHAR(5)) + CAST(tm.und_yr AS CHAR(4))) COLLATE DATABASE_DEFAULT
				,CEDED_CONTRACT_NBR = TRIM(CAST(ceded_tm.trty_no AS CHAR(5)) + CAST(ceded_tm.und_yr AS CHAR(4))) COLLATE DATABASE_DEFAULT
				,ct.trans_key
				,trans_cd = CAST(ct.trans_cd AS VARCHAR(3))
				,entry_dt = CAST(ct.entry_dt AS DATE)
				,c.section_key
				,ORIGCURR_CD = TRIM(cn.curr_iso_cd) COLLATE DATABASE_DEFAULT
				,TIRS_ORIG_CURR_CD = COALESCE(TRIM(ct.curr_cd), TRIM(c.curr_cd)) COLLATE DATABASE_DEFAULT
				,TIRS_ORIG_CURR_NAME = TRIM(cn.curr_nm) COLLATE DATABASE_DEFAULT
				,TIRS_LOB_NAME = TRIM(lob.desc_txt) COLLATE DATABASE_DEFAULT
				,AccidentYear = IIF(tm.und_YR > YEAR(c.loss_Dt), TRIM(CAST(tm.und_yr AS VARCHAR(4))) COLLATE DATABASE_DEFAULT, CAST(YEAR(CAST(c.loss_dt AS DATETIME)) AS VARCHAR(4)) COLLATE DATABASE_DEFAULT)
				,ClaimLossDate = CAST(c.loss_dt AS DATETIME)
				,REG_DATE = CAST(COALESCE(ct.reg_dt, DATEADD(MONTH, DATEDIFF(MONTH, 0, c.create_dt), 0)) AS DATETIME)
				,ASLOB = TRIM(AM.ASLOB) COLLATE DATABASE_DEFAULT
				,assumed_ceded_flg = CT.assumed_ceded_flg COLLATE DATABASE_DEFAULT
				,CAT_KEY = COALESCE(CAST(CAT.cat_key AS VARCHAR(20)), '') COLLATE DATABASE_DEFAULT
				,CatCode = CAST(COALESCE(CatCode.SunCatCode, '') AS VARCHAR(10)) COLLATE DATABASE_DEFAULT
				,TIRS_CLM_CD = CAST(COALESCE(ct.trans_key, '') AS VARCHAR(10)) COLLATE DATABASE_DEFAULT
				,Claim_NBR = CAST(COALESCE(c.clm_key, '') AS VARCHAR(10)) COLLATE DATABASE_DEFAULT
				,bill_co_br_key = c.payee_br_key
				,Summable_LOSS_PAID = CAST(COALESCE(ROUND(ct.trc_xpns, COALESCE(cdp.DecPlaces, 2)), 0) + COALESCE(ROUND(ct.indmnty_amt, COALESCE(cdp.DecPlaces, 2)), 0) AS DECIMAL(19,2))
				,SUMMABLE_LAE = CAST(COALESCE(ROUND(ct.xpns_amt, COALESCE(cdp.DecPlaces, 2)), 0) AS DECIMAL(19,2))
				,SUMMABLE_LOSS_PAID_USD = CAST(ROUND((COALESCE(ROUND(ct.trc_xpns, COALESCE(cdp.DecPlaces, 2)), 0) + COALESCE(ROUND(ct.indmnty_amt, COALESCE(cdp.DecPlaces, 2)), 0)) * COALESCE(xt.xch_rt, 0), 2) AS DECIMAL(19,2))
				,SUMMABLE_LAE_USD = CAST(ROUND(COALESCE(ROUND(ct.xpns_amt, COALESCE(cdp.DecPlaces, 2)) * xt.xch_rt, 0), 2) AS DECIMAL(19,2))
				,Summable_OS_LOSS = CAST(COALESCE(ROUND(ct.delta_ac_rsrvs, COALESCE(cdp.DecPlaces, 2)), 0) + COALESCE(ROUND(ct.delta_rsrvs, COALESCE(cdp.DecPlaces, 2)), 0) AS DECIMAL(19,2))
				,Summable_os_loss_exp = CAST(COALESCE(ROUND(ct.delta_lae_rsrvs, COALESCE(cdp.DecPlaces, 2)), 0) AS DECIMAL(19,2))
				,Summable_OS_LOSS_USD = CAST(ROUND(COALESCE(ROUND(ct.delta_ac_rsrvs, COALESCE(cdp.DecPlaces, 2)) * xt.xch_rt, 0), 2) + ROUND(COALESCE(ROUND(ct.delta_rsrvs, COALESCE(cdp.DecPlaces, 2)) * xt.xch_rt, 0), 2) AS DECIMAL(19,2))
				,Summable_os_loss_exp_USD = CAST(ROUND(COALESCE(ROUND(ct.delta_lae_rsrvs, COALESCE(cdp.DecPlaces, 2)) * xt.xch_rt, 0), 2) AS DECIMAL(19,2))
				,SUMMABLE_reinstatement_premium = CAST(COALESCE(ROUND(ct.reinstmt_amt, COALESCE(cdp.DecPlaces, 2)), 0) AS DECIMAL(19,2))
				,SUMMABLE_reinstatement_premium_USD = CAST(ROUND(COALESCE(ROUND(ct.reinstmt_amt, COALESCE(cdp.DecPlaces, 2)) * xt.xch_rt, 0), 2) AS DECIMAL(19,2))
				,solvency_II_regulatory_key = solII.solvency_II_regulatory_key
				,claim_description = TRIM(cc.desc_txt)
			FROM src_tirs_db.dbo.claim c
			INNER JOIN SRC_TIRS_DB.dbo.claim_trans ct
				ON ct.clm_key = c.clm_key
			INNER JOIN src_tirs_db.dbo.trty_master tm
				ON tm.trty_key = c.trty_key
			LEFT JOIN SRC_TIRS_DB.dbo.trty_master ceded_tm
				ON ceded_tm.trty_key = CT.Ceded_trty_key
			LEFT JOIN src_tirs_db.dbo.xrf_claim_type_cds cc
				ON c.claim_type_cd = cc.claim_type_cd
			LEFT JOIN SRC_TIRS_DB.dbo.xrf_lob_cds lob
				ON lob.lob_cd = c.lob_key
			LEFT JOIN SRC_TIRS_DB.dbo.xrf_annl_stmt_line aslob
				ON lob.annl_stmt_key = aslob.annl_stmt_key
			LEFT JOIN SRC_TIRS_DB.dbo.xrf_curr_names cn
				ON ct.curr_cd = cn.curr_cd
			LEFT JOIN EDW_Staging.assumed.CurrencyDecimalPlaces cdp
				ON cdp.CurrencyCode = cn.curr_iso_cd COLLATE DATABASE_DEFAULT
				AND cdp.EndDate = '31 Dec 9999'
			LEFT JOIN SRC_TIRS_DB.dbo.claim_cat CAT
				ON CAT.clm_key = c.clm_key
			LEFT JOIN IBNR.dbo.CatCode_Mapping CatCode
				ON COALESCE(CAST(CAT.cat_key AS VARCHAR(20)), '') = CatCode.EDWCatCode COLLATE DATABASE_DEFAULT
					AND CatCode.PolicySource = 'TIRS'
			LEFT JOIN SRC_TIRS_DB.dbo.xrf_curr_cds xt
				ON ct.curr_cd = xt.curr_cd
					AND CAST(COALESCE(ct.reg_dt, DATEADD(MONTH, DATEDIFF(MONTH, 0, c.create_dt), 0)) AS DATETIME) = xt.xch_rt_dt
			LEFT JOIN EDW_STAGING.dbo.TIRS_ASLOBCodeMapping AM
				ON AM.pro_xol_flg = TM.pro_xol_flg COLLATE DATABASE_DEFAULT
					AND AM.annl_stmt_ln = aslob.annl_stmt_ln COLLATE DATABASE_DEFAULT
			LEFT JOIN SRC_TIRS_DB.dbo.xrf_rpt_ofc xr
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
					AND COALESCE(solII.property_or_casualty, '') COLLATE DATABASE_DEFAULT = COALESCE(CASE WHEN sd.division_nm LIKE '%property%' THEN 'PROPERTY' WHEN sd.division_nm LIKE '%marine%' THEN 'PROPERTY' ELSE 'CASUALTY' END, '')
					AND COALESCE(solII.is_lloyds, '') COLLATE DATABASE_DEFAULT = COALESCE(CASE WHEN XR.rpt_ofc_nm LIKE '%lloyd%' THEN 'Lloyds' ELSE 'Non-Lloyds' END, '')
					AND COALESCE(solII.transaction_ASLOB_code, '') COLLATE DATABASE_DEFAULT = COALESCE(aslob.annl_stmt_ln, '')
					AND COALESCE(solII.InceptionFrom, tm.inception_dt, '1 Jan 1900') <= COALESCE(tm.inception_dt, '1 Jan 1900')
					AND COALESCE(solII.InceptionTo, tm.inception_dt, '1 Jan 1900') >= COALESCE(tm.inception_dt, '1 Jan 1900')
			WHERE NOT (CC.desc_txt IN ('Informational Only', 'Sub Claim')
				AND CAST(YEAR(CAST(c.loss_dt AS DATETIME)) AS VARCHAR(4)) < TRIM(CAST(tm.und_yr AS VARCHAR(4))))
			) x
		-- split measures in order to set to/from dates with defaults for reinstatement premium only, for the benefit of SAP
		CROSS APPLY (
			VALUES (x.Summable_LOSS_PAID, x.SUMMABLE_LAE, x.SUMMABLE_LOSS_PAID_USD, x.SUMMABLE_LAE_USD, x.Summable_OS_LOSS, x.Summable_os_loss_exp, x.Summable_OS_LOSS_USD, x.Summable_os_loss_exp_USD, 0, 0, NULL, NULL, CAST(1 AS TINYINT))
				,(0, 0, 0, 0, 0, 0, 0, 0, x.SUMMABLE_reinstatement_premium, x.SUMMABLE_reinstatement_premium_USD, CAST(x.REG_DATE AS DATE), CAST(x.REG_DATE AS DATE), CAST(2 AS TINYINT))
			) y (Summable_LOSS_PAID, SUMMABLE_LAE, SUMMABLE_LOSS_PAID_USD, SUMMABLE_LAE_USD, Summable_OS_LOSS, Summable_os_loss_exp, Summable_OS_LOSS_USD, Summable_os_loss_exp_USD, SUMMABLE_reinstatement_premium, SUMMABLE_reinstatement_premium_USD, FromDate, ToDate, DataSet)
		WHERE NOT (y.Summable_LOSS_PAID = 0
			AND y.SUMMABLE_LAE = 0
			AND y.Summable_OS_LOSS = 0
			AND y.Summable_os_loss_exp = 0
			AND y.SUMMABLE_reinstatement_premium = 0
			)
		        

		-- Loading logic
		ALTER TABLE #TIRSClaimLossPaidOSLR ADD DataHash BINARY(20) NULL

		UPDATE s
		SET DataHash = HASHBYTES('SHA1', CONCAT_WS('|'
			,s.TREATY_NBR
			,s.UNDERWRITING_YEAR
			,s.CONTRACT_NBR
			,s.CEDED_CONTRACT_NBR
			,s.trans_cd
			,s.entry_dt
			,s.section_key
			,s.FromDate
			,s.ToDate
			,s.ORIGCURR_CD
			,s.TIRS_ORIG_CURR_CD
			,s.TIRS_ORIG_CURR_NAME
			,s.TIRS_LOB_NAME
			,s.AccidentYear
			,s.ClaimLossDate
			,s.REG_DATE
			,s.ASLOB
			,s.assumed_ceded_flg
			,s.CAT_KEY
			,s.CatCode
			,s.TIRS_CLM_CD
			,s.Claim_NBR
			,s.bill_co_br_key
			,s.SUMMABLE_LOSS_PAID
			,s.SUMMABLE_LAE
			,s.SUMMABLE_LOSS_PAID_USD
			,s.SUMMABLE_LAE_USD
			,s.SUMMABLE_OS_LOSS
			,s.SUMMABLE_OS_LOSS_EXP
			,s.SUMMABLE_OS_LOSS_USD
			,s.SUMMABLE_OS_LOSS_EXP_USD
			,s.SUMMABLE_REINSTATEMENT_PREMIUM
			,s.SUMMABLE_REINSTATEMENT_PREMIUM_USD
			,s.solvency_II_regulatory_key
			,s.claim_description))
		FROM #TIRSClaimLossPaidOSLR s

		-- check/enforce uniqueness on the dimension source data
		CREATE UNIQUE INDEX assumed_TIRSClaimLossPaidOSLR_UK ON #TIRSClaimLossPaidOSLR (trans_key, DataSet)

		DROP TABLE IF EXISTS #LoadOperation

		CREATE TABLE #LoadOperation
		(trans_key INT NOT NULL
		,DataSet TINYINT NOT NULL
		,Operation CHAR(1) NOT NULL
		,UNIQUE (trans_key, DataSet)
		)

		INSERT INTO #LoadOperation
			(trans_key
			,DataSet
			,Operation
			)
		SELECT trans_key = COALESCE(t.trans_key, s.trans_key)
			,DataSet = COALESCE(t.DataSet, s.DataSet)
			,Operation = CASE WHEN t.TIRSClaimLossPaidOSLRID IS NULL THEN 'I' WHEN s.DataHash IS NULL THEN 'D' ELSE 'U' END
		FROM (
			SELECT t.*
			FROM assumed.TIRSClaimLossPaidOSLR t
			WHERE t.EndDate = '31 Dec 9999'
			) t
		FULL JOIN #TIRSClaimLossPaidOSLR s
			ON s.trans_key = t.trans_key
			AND s.DataSet = t.DataSet
		WHERE t.DataHash IS NULL
			OR s.DataHash IS NULL
			OR t.DataHash != s.DataHash

		BEGIN TRAN

		UPDATE t
		SET EndDate = p.ClosingEndDate
		FROM assumed.TIRSClaimLossPaidOSLR t
		INNER JOIN #LoadOperation lo
			ON lo.trans_key = t.trans_key
			AND lo.DataSet = t.DataSet
			AND lo.Operation IN ('U', 'D')
		CROSS JOIN #Parameters p
		WHERE t.EndDate = '31 Dec 9999'

		INSERT INTO assumed.TIRSClaimLossPaidOSLR
			(StartDate
			,TREATY_NBR
			,UNDERWRITING_YEAR
			,CONTRACT_NBR
			,CEDED_CONTRACT_NBR
			,DataSet
			,trans_key
			,trans_cd
			,entry_dt
			,section_key
			,FromDate
			,ToDate
			,ORIGCURR_CD
			,TIRS_ORIG_CURR_CD
			,TIRS_ORIG_CURR_NAME
			,TIRS_LOB_NAME
			,AccidentYear
			,ClaimLossDate
			,REG_DATE
			,ASLOB
			,assumed_ceded_flg
			,CAT_KEY
			,CatCode
			,TIRS_CLM_CD
			,Claim_NBR
			,bill_co_br_key
			,SUMMABLE_LOSS_PAID
			,SUMMABLE_LAE
			,SUMMABLE_LOSS_PAID_USD
			,SUMMABLE_LAE_USD
			,SUMMABLE_OS_LOSS
			,SUMMABLE_OS_LOSS_EXP
			,SUMMABLE_OS_LOSS_USD
			,SUMMABLE_OS_LOSS_EXP_USD
			,SUMMABLE_REINSTATEMENT_PREMIUM
			,SUMMABLE_REINSTATEMENT_PREMIUM_USD
			,solvency_II_regulatory_key
			,claim_description
			,DataHash
			)
		SELECT StartDate = p.NewStartDate
			,s.TREATY_NBR
			,s.UNDERWRITING_YEAR
			,s.CONTRACT_NBR
			,s.CEDED_CONTRACT_NBR
			,s.DataSet
			,s.trans_key
			,s.trans_cd
			,s.entry_dt
			,s.section_key
			,s.FromDate
			,s.ToDate
			,s.ORIGCURR_CD
			,s.TIRS_ORIG_CURR_CD
			,s.TIRS_ORIG_CURR_NAME
			,s.TIRS_LOB_NAME
			,s.AccidentYear
			,s.ClaimLossDate
			,s.REG_DATE
			,s.ASLOB
			,s.assumed_ceded_flg
			,s.CAT_KEY
			,s.CatCode
			,s.TIRS_CLM_CD
			,s.Claim_NBR
			,s.bill_co_br_key
			,s.SUMMABLE_LOSS_PAID
			,s.SUMMABLE_LAE
			,s.SUMMABLE_LOSS_PAID_USD
			,s.SUMMABLE_LAE_USD
			,s.SUMMABLE_OS_LOSS
			,s.SUMMABLE_OS_LOSS_EXP
			,s.SUMMABLE_OS_LOSS_USD
			,s.SUMMABLE_OS_LOSS_EXP_USD
			,s.SUMMABLE_REINSTATEMENT_PREMIUM
			,s.SUMMABLE_REINSTATEMENT_PREMIUM_USD
			,s.solvency_II_regulatory_key
			,s.claim_description
			,s.DataHash
		FROM #TIRSClaimLossPaidOSLR s
		INNER JOIN #LoadOperation lo
			ON lo.trans_key = s.trans_key
			AND lo.DataSet = s.DataSet
			AND lo.Operation IN ('I', 'U')
		CROSS JOIN #Parameters p

	COMMIT TRANSACTION

	-------------------------------------------------------
	-- Update etl_controller, flag SUCCESS
	-------------------------------------------------------
	SET @v_RowsProcessed	= COALESCE((SELECT COUNT(0) FROM #LoadOperation WHERE Operation IN ('I', 'U', 'D')), 0)
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
