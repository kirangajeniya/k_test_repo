-- Database: EDW_Staging
-- Schema: assumed
-- Procedure: LoadTIRS_UW_Staging_UEPR_DAC

CREATE   PROCEDURE [assumed].[LoadTIRS_UW_Staging_UEPR_DAC]
	@fullLoad BIT = 0
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
		-------------------------------------------------------

		DROP TABLE IF EXISTS #Parameters

		SELECT ClosingEndDate = DATEADD(NANOSECOND, -100, SYSDATETIME())
			,NewStartDate = SYSDATETIME()
			,IncrementalLoad = ~@fullLoad & CAST(COALESCE((SELECT TOP 1 1 FROM assumed.TIRS_UW_Staging WHERE SubSet = 2), 0) AS BIT) -- ensure a full load if the target table is empty
			,ChangedSince = DATEADD(DAY, -1, (SELECT MAX(StartDate) FROM assumed.TIRS_UW_Staging WHERE SubSet = 2))
		INTO #Parameters

		-- Staging logic
		
		DROP TABLE IF EXISTS #Filter
			
		SELECT DISTINCT CONTRACT_NBR = LEFT(ad.trty_no, 5) + LEFT(ad.und_yr, 4)
		INTO #Filter
		FROM #Parameters prm
		INNER JOIN SRC_TIRS_DB.dbo.acct_byline ab
			ON prm.IncrementalLoad = 0
		INNER JOIN SRC_TIRS_DB.dbo.acct_doc ad
			ON ab.doc_key = ad.doc_key
		UNION
		SELECT DISTINCT s.CONTRACT_NBR
		FROM assumed.TIRS_UW_Staging s
		INNER JOIN #Parameters prm
			ON prm.IncrementalLoad = 0
		WHERE s.EndDate = '31 Dec 9999'
		UNION
		SELECT DISTINCT CONTRACT_NBR = LEFT(ad.trty_no, 5) + LEFT(ad.und_yr, 4)
		FROM #Parameters prm
		INNER JOIN SRC_TIRS_DB.dbo.acct_byline ab
			ON prm.IncrementalLoad = 1
		INNER JOIN SRC_TIRS_DB.dbo.acct_doc ad
			ON ab.doc_key = ad.doc_key
		LEFT JOIN SRC_TIRS_DB.dbo.trty_master ceded_tm
			ON ceded_tm.trty_key = ad.Ceded_trty_key
		LEFT JOIN SRC_TIRS_DB.dbo.xrf_doc_type dc
			ON AD.doc_type_cd = DC.doc_type_cd
		LEFT JOIN SRC_TIRS_DB.dbo.xrf_lob_cds lob
			ON lob.lob_cd = ab.pr_cls_cd
		LEFT JOIN SRC_TIRS_DB.dbo.xrf_curr_cds xt
			ON xt.curr_cd = ad.curr_cd
			AND xt.xch_rt_dt = CAST(COALESCE(ad.reg_dt, DATEADD(MONTH, DATEDIFF(MONTH, 0, ad.create_dt), 0)) AS DATETIME)
		LEFT JOIN SRC_TIRS_DB.dbo.xrf_annl_stmt_line aslob
			ON lob.annl_stmt_key = aslob.annl_stmt_key
		LEFT JOIN SRC_TIRS_DB.dbo.trty_master tm
			ON tm.trty_key = ad.trty_key
		WHERE ab.touch_dt > prm.ChangedSince
			OR ad.create_dt > prm.ChangedSince
			OR ad.touch_dt > prm.ChangedSince
			OR ceded_tm.create_dt > prm.ChangedSince
			OR ceded_tm.touch_dt > prm.ChangedSince
			OR dc.touch_dt > prm.ChangedSince
			OR lob.touch_dt > prm.ChangedSince
			OR xt.touch_dt > prm.ChangedSince
			OR aslob.touch_dt > prm.ChangedSince
			OR tm.touch_dt > prm.ChangedSince
		UNION
		SELECT DISTINCT ubr.CONTRACT_NBR
		FROM assumed.TIRSUWBlendedRate ubr
		INNER JOIN #Parameters prm
			ON prm.IncrementalLoad = 1
		WHERE ubr.StartDate > prm.ChangedSince
			OR ubr.EndDate > prm.ChangedSince
		UNION
		SELECT DISTINCT urcud.CONTRACT_NBR
		FROM assumed.TIRSUWRptCurrUEPRDAC urcud
		INNER JOIN #Parameters prm
			ON prm.IncrementalLoad = 1
		WHERE urcud.StartDate > prm.ChangedSince
			OR urcud.EndDate > prm.ChangedSince
			
		DROP TABLE IF EXISTS #Preparation
			
		SELECT CONTRACT_NBR = y.CONTRACT_NBR
			,TREATY_NBR = y.TREATY_NBR
			,UNDERWRITING_YEAR = y.UNDERWRITING_YEAR
			,byline_key = y.byline_key
			,doc_type_cd = y.doc_type_cd
			,due_dt = y.due_dt
			,trty_key = y.trty_key
			,pr_cls_cd = y.pr_cls_cd
			,CEDED_CONTRACT_NBR = y.CEDED_CONTRACT_NBR
			,TIRS_ORIG_CURR_CD = y.TIRS_ORIG_CURR_CD
			,LOB_NAME = y.LOB_NAME
			,ASLOB = y.ASLOB
			,reg_date = y.reg_date
			,uepr = y.uepr
			,dac = y.dac
			,assumed_ceded_flg = y.assumed_ceded_flg
			,EntityGroup = y.EntityGroup
			,doc_key            = y.doc_key
			,Balance = MAX(y.Balance) OVER (PARTITION BY y.EntityGroup, y.reg_date)
			,NonZeroEntriesPerRegDate = SUM(CASE WHEN y.uepr != 0 OR y.dac != 0 THEN 1 ELSE 0 END) OVER (PARTITION BY y.EntityGroup, y.reg_date)
		INTO #Preparation
		FROM (
			SELECT CONTRACT_NBR = x.CONTRACT_NBR
				,TREATY_NBR = x.TREATY_NBR
				,UNDERWRITING_YEAR = x.UNDERWRITING_YEAR
				,byline_key = x.byline_key
				,doc_type_cd = x.doc_type_cd
				,due_dt = x.due_dt
				,trty_key = x.trty_key
				,pr_cls_cd = x.pr_cls_cd
				,CEDED_CONTRACT_NBR = x.CEDED_CONTRACT_NBR
				,TIRS_ORIG_CURR_CD = x.TIRS_ORIG_CURR_CD
				,LOB_NAME = x.LOB_NAME
				,ASLOB = x.ASLOB
				,reg_date = x.reg_date
				,uepr = x.uepr
				,dac = x.dac
				,acct_to_dt = x.acct_to_dt
				,assumed_ceded_flg = x.assumed_ceded_flg
				,doc_key            = x.doc_key
				,LatestAcctToDt 	= MAX(x.acct_to_dt) OVER (PARTITION BY x.CONTRACT_NBR, x.CEDED_CONTRACT_NBR, x.TIRS_ORIG_CURR_CD, x.LOB_NAME, x.assumed_ceded_flg ORDER BY x.reg_date)
				,EntityGroup 		= DENSE_RANK() OVER (ORDER BY x.CONTRACT_NBR, x.CEDED_CONTRACT_NBR, x.TIRS_ORIG_CURR_CD, x.LOB_NAME, x.assumed_ceded_flg)
				,Balance = CAST(CASE WHEN ROW_NUMBER() OVER (PARTITION BY x.CONTRACT_NBR, x.CEDED_CONTRACT_NBR, x.TIRS_ORIG_CURR_CD, x.LOB_NAME, x.assumed_ceded_flg, x.acct_to_dt ORDER BY x.reg_date, x.byline_key) = 1 THEN 1 ELSE 0 END AS TINYINT)
			FROM (
				SELECT
					 CONTRACT_NBR 		= TRIM(CAST(ad.trty_no AS CHAR(5))) + TRIM(CAST(ad.und_yr AS CHAR(4))) COLLATE DATABASE_DEFAULT
					,TREATY_NBR 		= TRIM(CAST(ad.trty_no AS VARCHAR(5))) COLLATE DATABASE_DEFAULT
					,UNDERWRITING_YEAR 	= TRIM(CAST(ad.und_yr AS VARCHAR(4))) COLLATE DATABASE_DEFAULT
					,byline_key 		= ab.byline_key
					,doc_type_cd 		= ad.doc_type_cd
					,due_dt 			= COALESCE(ad.due_dt, ad.receive_dt)
					,trty_key 			= ad.trty_key
					,pr_cls_cd 			= ab.pr_cls_cd
					,CEDED_CONTRACT_NBR = TRIM(CAST(ceded_tm.trty_no AS CHAR(5))) + TRIM(CAST(ceded_tm.und_yr AS CHAR(4))) COLLATE DATABASE_DEFAULT
					,TIRS_ORIG_CURR_CD 	= TRIM(ad.curr_cd) COLLATE DATABASE_DEFAULT
					,LOB_NAME 			= TRIM(lob.desc_txt) COLLATE DATABASE_DEFAULT
					,ASLOB 				= TRIM(am.ASLOB) COLLATE DATABASE_DEFAULT
					,reg_date 			= CAST(ISNULL(reg_dt, DATEADD(MONTH, DATEDIFF(MONTH, 0, ad.create_dt), 0)) AS DATETIME)
					,uepr 				= ISNULL(unearned_prem, 0)
					,dac 				= ISNULL(dac_assets, 0)
					,acct_to_dt 		= CAST(ad.acct_to_dt AS DATETIME)
					,assumed_ceded_flg 	= ad.assumed_ceded_flg COLLATE DATABASE_DEFAULT
					,doc_key			= ad.doc_key
				FROM SRC_TIRS_DB.dbo.acct_byline ab
				INNER JOIN SRC_TIRS_DB.dbo.acct_doc ad
					ON ab.doc_key = ad.doc_key
				INNER JOIN #Filter f
					ON f.CONTRACT_NBR = LEFT(ad.trty_no, 5) + LEFT(ad.und_yr, 4) COLLATE DATABASE_DEFAULT
				LEFT JOIN SRC_TIRS_DB.dbo.trty_master ceded_tm
					ON ceded_tm.trty_key = ad.Ceded_trty_key
				LEFT JOIN SRC_TIRS_DB.dbo.xrf_doc_type DC
					ON AD.doc_type_cd = DC.doc_type_cd
				LEFT JOIN SRC_TIRS_DB.dbo.xrf_lob_cds lob
					ON lob.lob_cd = ab.pr_cls_cd
				LEFT JOIN SRC_TIRS_DB.dbo.trty_master tm
					ON tm.trty_key = ad.trty_key
				LEFT JOIN SRC_TIRS_DB.dbo.xrf_annl_stmt_line aslob
					ON lob.annl_stmt_key = aslob.annl_stmt_key
				LEFT JOIN EDW_STAGING.dbo.TIRS_ASLOBCodeMapping am
					ON am.pro_xol_flg = tm.pro_xol_flg COLLATE DATABASE_DEFAULT
					AND am.annl_stmt_ln = aslob.annl_stmt_ln COLLATE DATABASE_DEFAULT
				WHERE RTRIM(LTRIM(DC.desc_txt)) IN ('Unearned Prem Auto Calc', 'Adjustment', 'Reported', 'Deposit', 'Cancellation', 'Correction')
					AND ad.status_flg = 'P'
				) x
			) y
		WHERE y.acct_to_dt = y.LatestAcctToDt
			AND NOT (y.Balance = 0 AND y.uepr = 0 AND y.dac = 0)
			
		DROP TABLE IF EXISTS #TIRS_UW_Staging
			
		SELECT CONTRACT_NBR = w.CONTRACT_NBR
			,TREATY_NBR = w.TREATY_NBR
			,UNDERWRITING_YEAR = w.UNDERWRITING_YEAR
			,byline_key = w.byline_key
			,doc_type_cd = w.doc_type_cd
			,due_date = w.due_dt
			,trty_key = w.trty_key
			,pr_cls_cd = w.pr_cls_cd
			,SubSet = 2
			,CEDED_CONTRACT_NBR = COALESCE(w.CEDED_CONTRACT_NBR, '')
			,assumed_ceded_flg = w.assumed_ceded_flg
			,TIRS_ORIG_CURR_CD = w.TIRS_ORIG_CURR_CD
			,OriginalCurrency = cn.curr_iso_cd COLLATE DATABASE_DEFAULT
			,LOB_NAME = w.LOB_NAME
			,ASLOB = w.ASLOB
			,reg_date = w.reg_date
			,doc_key  = w.doc_key
			,SUMMABLE_UEPR = w.uepr
			,SUMMABLE_UEPR_USD = CAST(NULL AS DECIMAL(19,2))
			,SUMMABLE_DAC = w.dac
			,SUMMABLE_DAC_USD = CAST(NULL AS DECIMAL(19,2))
			,BlendedRate = COALESCE(br.BlendedRate, 1)
			,RunningTotalUEPR = ROUND(SUM(w.uepr) OVER (PARTITION BY w.EntityGroup ORDER BY w.reg_date, w.byline_key), 2)
			,RunningTotalDAC = ROUND(SUM(w.dac) OVER (PARTITION BY w.EntityGroup ORDER BY w.reg_date, w.byline_key), 2)
			,RunningTotalUEPRUSD = ROUND(SUM(w.uepr) OVER (PARTITION BY w.EntityGroup ORDER BY w.reg_date, w.byline_key) * COALESCE(br.BlendedRate, 1), 2)
			,RunningTotalDACUSD = ROUND(SUM(w.dac) OVER (PARTITION BY w.EntityGroup ORDER BY w.reg_date, w.byline_key) * COALESCE(br.BlendedRate, 1), 2)
			,RPTCURR1_CD = CAST(NULL AS VARCHAR(3))
			,RPTCURR2_CD = CAST(NULL AS VARCHAR(3))
			,RPTCURR1 = CAST(NULL AS DECIMAL(38,15))
			,RPTCURR2 = CAST(NULL AS DECIMAL(38,15))
			,SUMMABLE_UEPR_RPT_CURR1 = CAST(NULL AS DECIMAL(19,2))
			,SUMMABLE_UEPR_RPT_CURR2 = CAST(NULL AS DECIMAL(19,2))
			,SUMMABLE_DAC_RPT_CURR1 = CAST(NULL AS DECIMAL(19,2))
			,SUMMABLE_DAC_RPT_CURR2 = CAST(NULL AS DECIMAL(19,2))
		INTO #TIRS_UW_Staging
		FROM (
			SELECT CONTRACT_NBR = z.CONTRACT_NBR
				,TREATY_NBR = z.TREATY_NBR
				,UNDERWRITING_YEAR = z.UNDERWRITING_YEAR
				,byline_key = z.byline_key
				,doc_type_cd = z.doc_type_cd
				,due_dt = z.due_dt
				,trty_key = z.trty_key
				,pr_cls_cd = z.pr_cls_cd
				,CEDED_CONTRACT_NBR = z.CEDED_CONTRACT_NBR
				,TIRS_ORIG_CURR_CD = z.TIRS_ORIG_CURR_CD
				,LOB_NAME = z.LOB_NAME
				,ASLOB = z.ASLOB
				,reg_date = z.reg_date
				,assumed_ceded_flg = z.assumed_ceded_flg
				,EntityGroup = z.EntityGroup
			    ,doc_key            = z.doc_key
				,uepr = CASE WHEN z.Balance = 0 THEN z.uepr ELSE z.uepr - COALESCE(LAG(z.ueprGroupBalance) OVER (PARTITION BY z.EntityGroup ORDER BY z.reg_date, z.byline_key), 0) END
				,dac = CASE WHEN z.Balance = 0 THEN z.dac ELSE z.dac - COALESCE(LAG(z.dacGroupBalance) OVER (PARTITION BY z.EntityGroup ORDER BY z.reg_date, z.byline_key), 0) END
			FROM (
				SELECT
					 CONTRACT_NBR = y.CONTRACT_NBR
					,TREATY_NBR = y.TREATY_NBR
					,UNDERWRITING_YEAR = y.UNDERWRITING_YEAR
					,byline_key = y.byline_key
					,doc_type_cd = y.doc_type_cd
					,due_dt = y.due_dt
					,trty_key = y.trty_key
					,pr_cls_cd = y.pr_cls_cd
					,CEDED_CONTRACT_NBR = y.CEDED_CONTRACT_NBR
					,TIRS_ORIG_CURR_CD = y.TIRS_ORIG_CURR_CD
					,LOB_NAME = y.LOB_NAME
					,ASLOB = y.ASLOB
					,reg_date = y.reg_date
					,assumed_ceded_flg = y.assumed_ceded_flg
					,EntityGroup = y.EntityGroup
			        ,doc_key            = y.doc_key
					,uepr 				= y.uepr
					,dac 				= y.dac
					,Balance 			= y.Balance
					,ueprGroupBalance 	= SUM(y.uepr) OVER (PARTITION BY y.EntityGroup, y.BalanceGroup)
					,dacGroupBalance 	= SUM(y.dac)  OVER (PARTITION BY y.EntityGroup, y.BalanceGroup)
				FROM (
					SELECT CONTRACT_NBR = x.CONTRACT_NBR
						,TREATY_NBR = x.TREATY_NBR
						,UNDERWRITING_YEAR = x.UNDERWRITING_YEAR
						,byline_key = CASE WHEN x.Balance = 0 OR (x.Balance = 1 AND x.EntryCountPerRegDate = 1) THEN 10000000000 + x.byline_key ELSE 20000000000 + x.byline_key END
						,doc_type_cd = CASE WHEN x.Balance = 0 OR (x.Balance = 1 AND x.DocTypeCountPerRegDate = x.EntryCountPerRegDate) THEN x.doc_type_cd ELSE 'MIX' END
						,due_dt = CASE WHEN x.Balance = 0 OR (x.Balance = 1 AND x.DueDateCountPerRegDate = x.EntryCountPerRegDate) THEN x.due_dt ELSE NULL END
						,trty_key = CASE WHEN x.Balance = 0 OR (x.Balance = 1 AND x.TreatyKeyCountPerRegDate = x.EntryCountPerRegDate) THEN x.trty_key ELSE NULL END
						,pr_cls_cd = CASE WHEN x.Balance = 0 OR (x.Balance = 1 AND x.PrClsCdCountPerRegDate = x.EntryCountPerRegDate) THEN x.pr_cls_cd ELSE NULL END
						,CEDED_CONTRACT_NBR = x.CEDED_CONTRACT_NBR
						,TIRS_ORIG_CURR_CD = x.TIRS_ORIG_CURR_CD
						,LOB_NAME = x.LOB_NAME
						,ASLOB = x.ASLOB
			            ,doc_key            = x.doc_key
						,reg_date 			= x.reg_date
						,assumed_ceded_flg 	= x.assumed_ceded_flg
						,EntityGroup 		= x.EntityGroup
						,uepr 				= x.uepr
						,dac 				= x.dac
						,Balance 			= x.Balance
						,BalanceGroup 		= SUM(x.Balance) OVER (PARTITION BY x.EntityGroup ORDER BY x.reg_date, x.byline_key)
					FROM (
						SELECT CONTRACT_NBR = p.CONTRACT_NBR
							,TREATY_NBR = p.TREATY_NBR
							,UNDERWRITING_YEAR = p.UNDERWRITING_YEAR
							,byline_key = p.byline_key
							,doc_type_cd = p.doc_type_cd
							,due_dt = p.due_dt
							,trty_key = p.trty_key
							,pr_cls_cd = p.pr_cls_cd
							,CEDED_CONTRACT_NBR = p.CEDED_CONTRACT_NBR
							,TIRS_ORIG_CURR_CD = p.TIRS_ORIG_CURR_CD
							,LOB_NAME = p.LOB_NAME
							,ASLOB = p.ASLOB
			                ,doc_key            = p.doc_key
							,reg_date 			= p.reg_date
							,assumed_ceded_flg 	= p.assumed_ceded_flg
							,EntityGroup 		= p.EntityGroup
							,uepr 				= CASE WHEN p.Balance = 0 THEN p.uepr ELSE SUM(p.uepr) OVER (PARTITION BY p.EntityGroup, p.reg_date) END
							,dac 				= CASE WHEN p.Balance = 0 THEN p.dac ELSE SUM(p.dac) OVER (PARTITION BY p.EntityGroup, p.reg_date) END
							,Balance 			= p.Balance
							,DocTypeCountPerRegDate = COUNT(0) OVER (PARTITION BY p.EntityGroup, p.reg_date, p.doc_type_cd)
							,DueDateCountPerRegDate = COUNT(0) OVER (PARTITION BY p.EntityGroup, p.reg_date, p.due_dt)
							,TreatyKeyCountPerRegDate = COUNT(0) OVER (PARTITION BY p.EntityGroup, p.reg_date, p.trty_key)
							,PrClsCdCountPerRegDate = COUNT(0) OVER (PARTITION BY p.EntityGroup, p.reg_date, p.pr_cls_cd)
							,EntryCountPerRegDate = COUNT(0) OVER (PARTITION BY p.EntityGroup, p.reg_date)
							,MostRecent = ROW_NUMBER() OVER (PARTITION BY p.EntityGroup, p.reg_date ORDER BY p.byline_key DESC)
						FROM #Preparation p
						WHERE NOT (p.Balance = 1 AND p.uepr = 0 AND p.dac = 0 AND p.NonZeroEntriesPerRegDate >= 1)
						) x
					WHERE x.MostRecent = 1
						OR x.Balance = 0
					) y
				) z
			) w
		LEFT JOIN assumed.TIRSUWBlendedRate br
			ON br.CONTRACT_NBR = w.CONTRACT_NBR
			AND br.ASSUMED_CEDED_FLG = w.assumed_ceded_flg
			AND br.TIRS_ORIG_CURR_CD = w.TIRS_ORIG_CURR_CD
			AND w.reg_date BETWEEN br.FromRegDate AND br.ToRegDate
			AND br.EndDate = '31 Dec 9999'
		LEFT JOIN SRC_TIRS_DB.dbo.xrf_curr_names cn
			ON cn.curr_cd = w.TIRS_ORIG_CURR_CD COLLATE DATABASE_DEFAULT
		WHERE NOT (w.uepr = 0 AND w.dac = 0)
			
		UPDATE x
		SET RPTCURR1_CD = Revised_RPTCURR1_CD
			,RPTCURR2_CD = Revised_RPTCURR2_CD
			,SUMMABLE_UEPR_RPT_CURR1 = Revised_SUMMABLE_UEPR_RPT_CURR1
			,SUMMABLE_UEPR_RPT_CURR2 = Revised_SUMMABLE_UEPR_RPT_CURR2
			,SUMMABLE_DAC_RPT_CURR1 = Revised_SUMMABLE_DAC_RPT_CURR1
			,SUMMABLE_DAC_RPT_CURR2 = Revised_SUMMABLE_DAC_RPT_CURR2
		FROM (
			SELECT s.RPTCURR1_CD
				,s.RPTCURR2_CD
				,s.SUMMABLE_UEPR_RPT_CURR1
				,s.SUMMABLE_UEPR_RPT_CURR2
				,s.SUMMABLE_DAC_RPT_CURR1
				,s.SUMMABLE_DAC_RPT_CURR2
				,Revised_RPTCURR1_CD = rc.RPTCURR1_CD
				,Revised_RPTCURR2_CD = rc.RPTCURR2_CD
				,Revised_SUMMABLE_UEPR_RPT_CURR1 = ROUND(CAST(s.RunningTotalUEPR * rc.WP_RPT1_Rate AS DECIMAL(19,3)), 2) - COALESCE(ROUND(CAST(LAG(s.RunningTotalUEPR * rc.WP_RPT1_Rate) OVER (PARTITION BY s.CONTRACT_NBR, s.LOB_NAME, s.assumed_ceded_flg, s.TIRS_ORIG_CURR_CD ORDER BY s.reg_date, s.byline_key) AS DECIMAL(19,3)), 2), 0)
				,Revised_SUMMABLE_UEPR_RPT_CURR2 = ROUND(CAST(s.RunningTotalUEPR * rc.WP_RPT2_Rate AS DECIMAL(19,3)), 2) - COALESCE(ROUND(CAST(LAG(s.RunningTotalUEPR * rc.WP_RPT2_Rate) OVER (PARTITION BY s.CONTRACT_NBR, s.LOB_NAME, s.assumed_ceded_flg, s.TIRS_ORIG_CURR_CD ORDER BY s.reg_date, s.byline_key) AS DECIMAL(19,3)), 2), 0)
				,Revised_SUMMABLE_DAC_RPT_CURR1 = ROUND(CAST(s.RunningTotalDAC * rc.COMM_RPT1_Rate AS DECIMAL(19,3)), 2) - COALESCE(ROUND(CAST(LAG(s.RunningTotalDAC * rc.COMM_RPT1_Rate) OVER (PARTITION BY s.CONTRACT_NBR, s.LOB_NAME, s.assumed_ceded_flg, s.TIRS_ORIG_CURR_CD ORDER BY s.reg_date, s.byline_key) AS DECIMAL(19,3)), 2), 0)
				,Revised_SUMMABLE_DAC_RPT_CURR2 = ROUND(CAST(s.RunningTotalDAC * rc.COMM_RPT2_Rate AS DECIMAL(19,3)), 2) - COALESCE(ROUND(CAST(LAG(s.RunningTotalDAC * rc.COMM_RPT2_Rate) OVER (PARTITION BY s.CONTRACT_NBR, s.LOB_NAME, s.assumed_ceded_flg, s.TIRS_ORIG_CURR_CD ORDER BY s.reg_date, s.byline_key) AS DECIMAL(19,3)), 2), 0)
			FROM #TIRS_UW_Staging s
			LEFT JOIN assumed.TIRSUWRptCurrUEPRDAC rc
				ON rc.CONTRACT_NBR = s.CONTRACT_NBR
				AND rc.CEDED_CONTRACT_NBR = s.CEDED_CONTRACT_NBR
				AND rc.TIRS_ORIG_CURR_CD = s.TIRS_ORIG_CURR_CD
				AND rc.ASSUMED_CEDED_FLG = s.assumed_ceded_flg
				AND rc.LOB_NAME = s.LOB_NAME
				AND s.reg_date BETWEEN rc.FromRegDate AND rc.ToRegDate
				AND rc.EndDate = '31 Dec 9999'
			) x
			
		UPDATE s
		SET SUMMABLE_UEPR_USD = s.Revised_SUMMABLE_UEPR_USD
			,SUMMABLE_DAC_USD = s.Revised_SUMMABLE_DAC_USD
		FROM (
			SELECT SUMMABLE_UEPR_USD
				,SUMMABLE_DAC_USD
				,Revised_SUMMABLE_UEPR_USD = s.RunningTotalUEPRUSD - COALESCE(LAG(s.RunningTotalUEPRUSD) OVER (PARTITION BY s.CONTRACT_NBR, s.LOB_NAME, s.assumed_ceded_flg, s.TIRS_ORIG_CURR_CD ORDER BY s.reg_date, s.byline_key), 0)
				,Revised_SUMMABLE_DAC_USD = s.RunningTotalDACUSD - COALESCE(LAG(s.RunningTotalDACUSD) OVER (PARTITION BY s.CONTRACT_NBR, s.LOB_NAME, s.assumed_ceded_flg, s.TIRS_ORIG_CURR_CD ORDER BY s.reg_date, s.byline_key), 0)
			FROM #TIRS_UW_Staging s
			) s
			
		DROP TABLE IF EXISTS #FXUSD
				
		SELECT AccountingPeriodDate = CAST(LEFT(lgc.JoinMonth, 4) + RIGHT(lgc.JoinMonth, 2) + '01' AS DATE)
			,FromCurrency = lgc.ISOCode COLLATE DATABASE_DEFAULT
			,ToCurrency = 'USD'
			,ExchangeRate = MIN(lgc.ExchangeRate)
		INTO #FXUSD
		FROM EDW_PREPROD.dbo.LOOKUP_GENIUS_CURRENCYRATES lgc
		WHERE JoinMonth IS NOT NULL
		GROUP BY CAST(LEFT(lgc.JoinMonth, 4) + RIGHT(lgc.JoinMonth, 2) + '01' AS DATE)
			,lgc.ISOCode
				
		DROP TABLE IF EXISTS #FX
			
		SELECT f.AccountingPeriodDate
			,FromCurrency = y.FromCurrency COLLATE DATABASE_DEFAULT
			,ToCurrency = y.ToCurrency COLLATE DATABASE_DEFAULT
			,ExchangeRate = CASE WHEN y.FromCurrency = y.ToCurrency THEN 1 ELSE f.ExchangeRate / t.ExchangeRate END
		INTO #FX
		FROM (
			SELECT DISTINCT FromCurrency = s.OriginalCurrency
				,ToCurrency = x.ToCurrency COLLATE DATABASE_DEFAULT
				,s.reg_date
			FROM #TIRS_UW_Staging s
			CROSS APPLY (
				VALUES(s.RPTCURR1_CD)
					,(s.RPTCURR2_CD)
				) x (ToCurrency)
			WHERE NULLIF(x.ToCurrency, '') IS NOT NULL
			GROUP BY s.OriginalCurrency
				,x.ToCurrency
				,s.reg_date
			) y
		INNER JOIN #FXUSD f
			ON f.AccountingPeriodDate = y.reg_date
			AND f.FromCurrency = y.FromCurrency COLLATE DATABASE_DEFAULT
		INNER JOIN #FXUSD t
			ON t.AccountingPeriodDate = f.AccountingPeriodDate
			AND t.FromCurrency = y.ToCurrency COLLATE DATABASE_DEFAULT
			
		UPDATE x
		SET RPTCURR1 = x.Revised_RPTCURR1
			,RPTCURR2 = x.Revised_RPTCURR2
		FROM (
			SELECT RPTCURR1
				,RPTCURR2
				,Revised_RPTCURR1 = fx1.ExchangeRate
				,Revised_RPTCURR2 = fx2.ExchangeRate
			FROM #TIRS_UW_Staging s
			LEFT JOIN #FX fx1
				ON fx1.AccountingPeriodDate = s.reg_date
				AND fx1.FromCurrency = s.OriginalCurrency
				AND fx1.ToCurrency = s.RPTCURR1_CD
			LEFT JOIN #FX fx2
				ON fx2.AccountingPeriodDate = s.reg_date
				AND fx2.FromCurrency = s.OriginalCurrency
				AND fx2.ToCurrency = s.RPTCURR2_CD
			WHERE NOT (s.RPTCURR1_CD = '' AND s.RPTCURR2_CD = '')
			) x
		

		-- Loading logic
		ALTER TABLE #TIRS_UW_Staging ADD DataHash BINARY(20) NULL

		UPDATE s
		SET DataHash = HASHBYTES('SHA1', 
						CONCAT_WS('|',s.TREATY_NBR
									 ,s.UNDERWRITING_YEAR
									 ,s.CEDED_CONTRACT_NBR
									 ,s.ASSUMED_CEDED_FLG
									 ,s.TIRS_ORIG_CURR_CD
									 ,s.ASLOB
									 ,s.LOB_NAME
									 ,s.reg_date
									 ,s.due_date
									 ,s.doc_type_cd
									 ,s.trty_key
									 ,s.pr_cls_cd   
									 ,s.SUMMABLE_UEPR
									 ,s.SUMMABLE_UEPR_USD
									 ,s.SUMMABLE_DAC
									 ,s.SUMMABLE_DAC_USD
									 ,s.BlendedRate
									 ,s.RPTCURR1_CD
									 ,s.RPTCURR2_CD
									 ,s.RPTCURR1
									 ,s.RPTCURR2
									 ,s.SUMMABLE_UEPR_RPT_CURR1
									 ,s.SUMMABLE_UEPR_RPT_CURR2
									 ,s.SUMMABLE_DAC_RPT_CURR1
									 ,s.SUMMABLE_DAC_RPT_CURR2
									 ,s.doc_key					 
									 ))
		FROM #TIRS_UW_Staging s

		DROP TABLE IF EXISTS #LoadOperation

		CREATE TABLE #LoadOperation
		(CONTRACT_NBR VARCHAR(9) COLLATE DATABASE_DEFAULT NOT NULL
		,byline_key BIGINT NULL
		,Operation CHAR(1) NOT NULL
		,UNIQUE (CONTRACT_NBR, byline_key)
		)

		INSERT INTO #LoadOperation
			(CONTRACT_NBR
			,byline_key
			,Operation
			)
		SELECT CONTRACT_NBR = COALESCE(t.CONTRACT_NBR COLLATE DATABASE_DEFAULT, s.CONTRACT_NBR COLLATE DATABASE_DEFAULT)
			,byline_key = COALESCE(t.byline_key, s.byline_key)
			,Operation = CASE WHEN t.TIRS_UW_StagingID IS NULL THEN 'I' WHEN s.DataHash IS NULL THEN 'D' ELSE 'U' END
		FROM (
			SELECT t.*
			FROM assumed.TIRS_UW_Staging t
			INNER JOIN (
				SELECT DISTINCT f.CONTRACT_NBR
				FROM #Filter f
				) f
				ON f.CONTRACT_NBR = t.CONTRACT_NBR COLLATE DATABASE_DEFAULT
			WHERE t.EndDate = '31 Dec 9999'
				AND t.SubSet = 2
			) t
		FULL JOIN (
			SELECT s.*
			FROM #TIRS_UW_Staging s
			INNER JOIN (
				SELECT DISTINCT f.CONTRACT_NBR
				FROM #Filter f
				) f
				ON f.CONTRACT_NBR = s.CONTRACT_NBR COLLATE DATABASE_DEFAULT
			) s
			ON s.CONTRACT_NBR = t.CONTRACT_NBR COLLATE DATABASE_DEFAULT
			AND COALESCE(s.byline_key, -1) = COALESCE(t.byline_key, -1)
		WHERE t.DataHash IS NULL
			OR s.DataHash IS NULL
			OR t.DataHash != s.DataHash

		BEGIN TRAN

		UPDATE t
		SET EndDate = p.ClosingEndDate
		FROM assumed.TIRS_UW_Staging t
		INNER JOIN #LoadOperation lo
			ON lo.CONTRACT_NBR = t.CONTRACT_NBR
			AND COALESCE(lo.byline_key, -1) = COALESCE(t.byline_key, -1)
			AND lo.Operation IN ('U', 'D')
		CROSS JOIN #Parameters p
		WHERE t.EndDate = '31 Dec 9999'
			AND t.SubSet = 2

		INSERT INTO assumed.TIRS_UW_Staging
			(StartDate
			,SubSet
			,byline_key
			,TREATY_NBR
			,UNDERWRITING_YEAR
			,CONTRACT_NBR
			,CEDED_CONTRACT_NBR
			,ASSUMED_CEDED_FLG
			,TIRS_ORIG_CURR_CD
			,ASLOB
			,LOB_NAME	
			,reg_date
			,due_date
			,doc_type_cd
			,trty_key
			,pr_cls_cd
			,SUMMABLE_UEPR
			,SUMMABLE_UEPR_USD
			,SUMMABLE_DAC
			,SUMMABLE_DAC_USD
			,BlendedRate
			,RPTCURR1_CD
			,RPTCURR2_CD
			,RPTCURR1
			,RPTCURR2
			,SUMMABLE_UEPR_RPT_CURR1
			,SUMMABLE_UEPR_RPT_CURR2
			,SUMMABLE_DAC_RPT_CURR1
			,SUMMABLE_DAC_RPT_CURR2
			,doc_key
			,DataHash
			)
		SELECT StartDate = p.NewStartDate
			,SubSet = 2
			,s.byline_key
			,s.TREATY_NBR
			,s.UNDERWRITING_YEAR
			,s.CONTRACT_NBR
			,s.CEDED_CONTRACT_NBR
			,s.ASSUMED_CEDED_FLG
			,s.TIRS_ORIG_CURR_CD
			,s.ASLOB
			,s.LOB_NAME
			,s.reg_date
			,s.due_date
			,s.doc_type_cd
			,s.trty_key
			,s.pr_cls_cd
			,s.SUMMABLE_UEPR
			,s.SUMMABLE_UEPR_USD
			,s.SUMMABLE_DAC
			,s.SUMMABLE_DAC_USD
			,s.BlendedRate
			,s.RPTCURR1_CD
			,s.RPTCURR2_CD
			,s.RPTCURR1
			,s.RPTCURR2
			,s.SUMMABLE_UEPR_RPT_CURR1
			,s.SUMMABLE_UEPR_RPT_CURR2
			,s.SUMMABLE_DAC_RPT_CURR1
			,s.SUMMABLE_DAC_RPT_CURR2
			,s.doc_key
			,s.DataHash
		FROM #TIRS_UW_Staging s
		INNER JOIN #LoadOperation lo
			ON lo.CONTRACT_NBR = s.CONTRACT_NBR COLLATE DATABASE_DEFAULT
			AND COALESCE(lo.byline_key, -1) = COALESCE(s.byline_key, -1)
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
