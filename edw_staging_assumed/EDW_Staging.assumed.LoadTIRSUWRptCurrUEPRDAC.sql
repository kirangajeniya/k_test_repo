-- Database: EDW_Staging
-- Schema: assumed
-- Procedure: LoadTIRSUWRptCurrUEPRDAC

CREATE   PROCEDURE assumed.LoadTIRSUWRptCurrUEPRDAC
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
			,IncrementalLoad = ~@fullLoad & CAST(COALESCE((SELECT TOP 1 1 FROM assumed.TIRSUWRptCurrUEPRDAC), 0) AS BIT) -- ensure a full load if the target table is empty
			,ChangedSince = DATEADD(DAY, -1, (SELECT MAX(StartDate) FROM assumed.TIRSUWRptCurrUEPRDAC))
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
		FROM assumed.TIRSUWRptCurrUEPRDAC s
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
		
		DROP TABLE IF EXISTS #CurrentAccountingPeriod
		
		SELECT x.AccountingPeriodDate
			,x.AccountingStartDate
			,x.AccountingEndDate
			,OffsetDays = 1
			,OffsetAccountingStartDate = DATEADD(DAY, 1, x.AccountingStartDate)
			,OffsetAccountingEndDate = DATEADD(DAY, 1, x.AccountingEndDate)
		INTO #CurrentAccountingPeriod
		FROM (
			SELECT AccountingPeriodDate = ap.accounting_period_date
				,AccountingStartDate = CAST(DATEADD(DAY, 1, LAG(ap.accounting_period_close_date) OVER (ORDER BY ap.accounting_period_key)) AS DATE)
				,AccountingEndDate = CAST(ap.accounting_period_close_date AS DATE)
			FROM Insight.dbo.accounting_periods ap
			) x
		WHERE CAST(DATEADD(DAY, -1, GETDATE()) AS DATE) BETWEEN x.AccountingStartDate AND x.AccountingEndDate
		
		DROP TABLE IF EXISTS #RPT
		
		SELECT Contract_NBR = tch.Contract_NBR COLLATE DATABASE_DEFAULT
			,lob_name = tch.lob_name COLLATE DATABASE_DEFAULT
			,RPTCURR1_CD = tch.RPTCURR1_CD COLLATE DATABASE_DEFAULT
			,RPTCURR2_CD = tch.RPTCURR2_CD COLLATE DATABASE_DEFAULT
		INTO #RPT
		FROM #CurrentAccountingPeriod cap
		INNER JOIN EDW_PREPROD.dbo.T_Code_History tch
			ON cap.OffsetAccountingEndDate > tch.START_DATE
			AND cap.OffsetAccountingEndDate < tch.END_DATE
		INNER JOIN #Filter f
			ON f.CONTRACT_NBR = tch.Contract_NBR COLLATE DATABASE_DEFAULT
		
		DROP TABLE IF EXISTS #MaxRegDate
		
		SELECT CONTRACT_NBR = CONCAT(TRIM(CAST(ad.trty_no AS VARCHAR(5))), TRIM(CAST(ad.und_yr AS VARCHAR(4)))) COLLATE DATABASE_DEFAULT
			,CEDED_CONTRACT_NBR = CONCAT(TRIM(CAST(ceded_tm.trty_no AS VARCHAR(5))), TRIM(CAST(ceded_tm.und_yr AS VARCHAR(4)))) COLLATE DATABASE_DEFAULT
			,ASSUMED_CEDED_FLG = ad.assumed_ceded_flg COLLATE DATABASE_DEFAULT
			,TIRS_ORIG_CURR_CD = TRIM(ad.curr_cd) COLLATE DATABASE_DEFAULT
			,LOB_NAME = TRIM(lob.desc_txt) COLLATE DATABASE_DEFAULT
			,MaxRegDate = MAX(CAST(COALESCE(ad.reg_dt, DATEADD(MONTH, DATEDIFF(MONTH, 0, ad.create_dt), 0)) AS DATE))
		INTO #MaxRegDate
		FROM SRC_TIRS_DB.dbo.acct_byline ab
		INNER JOIN SRC_TIRS_DB.dbo.acct_doc ad
			ON ab.doc_key = ad.doc_key
		INNER JOIN #Filter f
			ON f.CONTRACT_NBR = TRIM(CAST(ad.trty_no AS CHAR(5))) + TRIM(CAST(ad.und_yr AS CHAR(4))) COLLATE DATABASE_DEFAULT
		LEFT JOIN SRC_TIRS_DB.dbo.trty_master ceded_tm
			ON ceded_tm.trty_key = ad.Ceded_trty_key
		LEFT JOIN SRC_TIRS_DB.dbo.xrf_lob_cds lob
			ON lob.lob_cd = ab.pr_cls_cd
		WHERE ad.status_flg = 'P'
		GROUP BY CONCAT(TRIM(CAST(ad.trty_no AS VARCHAR(5))), TRIM(CAST(ad.und_yr AS VARCHAR(4)))) COLLATE DATABASE_DEFAULT
			,CONCAT(TRIM(CAST(ceded_tm.trty_no AS VARCHAR(5))), TRIM(CAST(ceded_tm.und_yr AS VARCHAR(4)))) COLLATE DATABASE_DEFAULT
			,ad.assumed_ceded_flg COLLATE DATABASE_DEFAULT
			,TRIM(ad.curr_cd) COLLATE DATABASE_DEFAULT
			,TRIM(lob.desc_txt) COLLATE DATABASE_DEFAULT
		
		DROP TABLE IF EXISTS #WPCOMM
		
		SELECT x.CONTRACT_NBR
			,x.CEDED_CONTRACT_NBR
			,x.ASSUMED_CEDED_FLG
			,x.TIRS_ORIG_CURR_CD
			,x.ISOCurrencyCode
			,x.LOB_NAME
			,FromRegDate = x.reg_date
			,ToRegDate = COALESCE(DATEADD(MONTH, -1, LEAD(x.reg_date) OVER (PARTITION BY x.CONTRACT_NBR, x.CEDED_CONTRACT_NBR, x.ASSUMED_CEDED_FLG, x.TIRS_ORIG_CURR_CD, x.LOB_NAME ORDER BY x.reg_date)), mrd.MaxRegDate)
			,x.WP
			,x.COMM
		INTO #WPCOMM
		FROM (
			SELECT CONTRACT_NBR = CONCAT(TRIM(CAST(ad.trty_no AS VARCHAR(5))), TRIM(CAST(ad.und_yr AS VARCHAR(4)))) COLLATE DATABASE_DEFAULT
				,CEDED_CONTRACT_NBR = CONCAT(TRIM(CAST(ceded_tm.trty_no AS VARCHAR(5))), TRIM(CAST(ceded_tm.und_yr AS VARCHAR(4)))) COLLATE DATABASE_DEFAULT
				,ASSUMED_CEDED_FLG = ad.assumed_ceded_flg COLLATE DATABASE_DEFAULT
				,TIRS_ORIG_CURR_CD = TRIM(ad.curr_cd) COLLATE DATABASE_DEFAULT
				,ISOCurrencyCode = cn.curr_iso_cd COLLATE DATABASE_DEFAULT
				,LOB_NAME = TRIM(lob.desc_txt) COLLATE DATABASE_DEFAULT
				,reg_date = CAST(COALESCE(ad.reg_dt, DATEADD(MONTH, DATEDIFF(MONTH, 0, ad.create_dt), 0)) AS DATE)
				,WP = SUM(COALESCE(ab.prem_wr, 0))
				,COMM = SUM(COALESCE(ab.Brokerage, 0) + COALESCE(ab.tax_nonrefund, 0) + COALESCE(ab.tax_on_prem, 0) + COALESCE(ab.fire_prevent_fund, 0) + COALESCE(ab.xch_diff, 0) + COALESCE(ab.Comm, 0) + COALESCE(ab.sldg_comm_amt, 0) + COALESCE(2 * ab.overrider_comm_amt, 0) + COALESCE(ab.prov_comm_amt, 0) + COALESCE(ab.deferred_comm_amt, 0))
			FROM SRC_TIRS_DB.dbo.acct_byline ab
			INNER JOIN SRC_TIRS_DB.dbo.acct_doc ad
				ON ab.doc_key = ad.doc_key
			INNER JOIN #Filter f
				ON f.CONTRACT_NBR = TRIM(CAST(ad.trty_no AS CHAR(5))) + TRIM(CAST(ad.und_yr AS CHAR(4))) COLLATE DATABASE_DEFAULT
			LEFT JOIN SRC_TIRS_DB.dbo.trty_master ceded_tm
				ON ceded_tm.trty_key = ad.Ceded_trty_key
			LEFT JOIN SRC_TIRS_DB.dbo.xrf_lob_cds lob
				ON lob.lob_cd = ab.pr_cls_cd
			LEFT JOIN SRC_TIRS_DB.dbo.xrf_curr_names cn
				ON cn.curr_cd = ad.curr_cd
			WHERE ad.status_flg = 'P'
			GROUP BY CONCAT(TRIM(CAST(ad.trty_no AS VARCHAR(5))), TRIM(CAST(ad.und_yr AS VARCHAR(4)))) COLLATE DATABASE_DEFAULT
				,CONCAT(TRIM(CAST(ceded_tm.trty_no AS VARCHAR(5))), TRIM(CAST(ceded_tm.und_yr AS VARCHAR(4)))) COLLATE DATABASE_DEFAULT
				,ad.assumed_ceded_flg COLLATE DATABASE_DEFAULT
				,TRIM(ad.curr_cd) COLLATE DATABASE_DEFAULT
				,cn.curr_iso_cd COLLATE DATABASE_DEFAULT
				,TRIM(lob.desc_txt) COLLATE DATABASE_DEFAULT
				,CAST(COALESCE(ad.reg_dt, DATEADD(MONTH, DATEDIFF(MONTH, 0, ad.create_dt), 0)) AS DATE)
			HAVING NOT (SUM(COALESCE(ab.prem_wr, 0)) = 0
					AND SUM(COALESCE(ab.Brokerage, 0) + COALESCE(ab.tax_nonrefund, 0) + COALESCE(ab.tax_on_prem, 0) + COALESCE(ab.fire_prevent_fund, 0) + COALESCE(ab.xch_diff, 0) + COALESCE(ab.Comm, 0) + COALESCE(ab.sldg_comm_amt, 0) + COALESCE(2 * ab.overrider_comm_amt, 0) + COALESCE(ab.prov_comm_amt, 0) + COALESCE(ab.deferred_comm_amt, 0)) = 0
					)
			) x
		INNER JOIN #MaxRegDate mrd
			ON mrd.CONTRACT_NBR = x.CONTRACT_NBR
			AND mrd.CEDED_CONTRACT_NBR = x.CEDED_CONTRACT_NBR
			AND mrd.ASSUMED_CEDED_FLG = x.ASSUMED_CEDED_FLG
			AND mrd.TIRS_ORIG_CURR_CD = x.TIRS_ORIG_CURR_CD
			AND mrd.LOB_NAME = x.LOB_NAME
		OPTION (FORCE ORDER)
		
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
			SELECT DISTINCT FromCurrency = wpc.ISOCurrencyCode COLLATE DATABASE_DEFAULT
				,ToCurrency = x.ToCurrency COLLATE DATABASE_DEFAULT
				,FromRegDate = MIN(wpc.FromRegDate)
				,ToRegDate = MAX(wpc.ToRegDate)
			FROM #WPCOMM wpc
			INNER JOIN #RPT r
				ON r.Contract_NBR = wpc.CONTRACT_NBR
				AND r.lob_name = wpc.LOB_NAME
			CROSS APPLY (
				VALUES(r.RPTCURR1_CD)
					,(r.RPTCURR2_CD)
				) x (ToCurrency)
			WHERE NULLIF(x.ToCurrency, '') IS NOT NULL
			GROUP BY wpc.ISOCurrencyCode
				,x.ToCurrency
			) y
		INNER JOIN #FXUSD f
			ON f.AccountingPeriodDate BETWEEN y.FromRegDate AND y.ToRegDate
			AND f.FromCurrency = y.FromCurrency COLLATE DATABASE_DEFAULT
		INNER JOIN #FXUSD t
			ON t.AccountingPeriodDate = f.AccountingPeriodDate
			AND t.FromCurrency = y.ToCurrency COLLATE DATABASE_DEFAULT
		
		DROP TABLE IF EXISTS #TIRSUWRptCurrUEPRDAC
		
		SELECT wpc.CONTRACT_NBR
			,wpc.CEDED_CONTRACT_NBR
			,wpc.ASSUMED_CEDED_FLG
			,wpc.TIRS_ORIG_CURR_CD
			,wpc.LOB_NAME
			,wpc.FromRegDate
			,wpc.ToRegDate
			,r.RPTCURR1_CD
			,r.RPTCURR2_CD
			,WP_RPT1_Rate = COALESCE(SUM(CAST(wpc.WP AS FLOAT) * fx1.ExchangeRate) OVER (PARTITION BY wpc.CONTRACT_NBR, wpc.CEDED_CONTRACT_NBR, wpc.ASSUMED_CEDED_FLG, wpc.TIRS_ORIG_CURR_CD, wpc.LOB_NAME ORDER BY wpc.FromRegDate) / NULLIF(SUM(CAST(wpc.WP AS FLOAT)) OVER (PARTITION BY wpc.CONTRACT_NBR, wpc.CEDED_CONTRACT_NBR, wpc.ASSUMED_CEDED_FLG, wpc.TIRS_ORIG_CURR_CD, wpc.LOB_NAME ORDER BY wpc.FromRegDate), 0), CASE WHEN NULLIF(r.RPTCURR1_CD, '') IS NOT NULL THEN 0 END)
			,WP_RPT2_Rate = COALESCE(SUM(CAST(wpc.WP AS FLOAT) * fx2.ExchangeRate) OVER (PARTITION BY wpc.CONTRACT_NBR, wpc.CEDED_CONTRACT_NBR, wpc.ASSUMED_CEDED_FLG, wpc.TIRS_ORIG_CURR_CD, wpc.LOB_NAME ORDER BY wpc.FromRegDate) / NULLIF(SUM(CAST(wpc.WP AS FLOAT)) OVER (PARTITION BY wpc.CONTRACT_NBR, wpc.CEDED_CONTRACT_NBR, wpc.ASSUMED_CEDED_FLG, wpc.TIRS_ORIG_CURR_CD, wpc.LOB_NAME ORDER BY wpc.FromRegDate), 0), CASE WHEN NULLIF(r.RPTCURR2_CD, '') IS NOT NULL THEN 0 END)
			,COMM_RPT1_Rate = COALESCE(SUM(CAST(wpc.COMM AS FLOAT) * fx1.ExchangeRate) OVER (PARTITION BY wpc.CONTRACT_NBR, wpc.CEDED_CONTRACT_NBR, wpc.ASSUMED_CEDED_FLG, wpc.TIRS_ORIG_CURR_CD, wpc.LOB_NAME ORDER BY wpc.FromRegDate) / NULLIF(SUM(CAST(wpc.COMM AS FLOAT)) OVER (PARTITION BY wpc.CONTRACT_NBR, wpc.CEDED_CONTRACT_NBR, wpc.ASSUMED_CEDED_FLG, wpc.TIRS_ORIG_CURR_CD, wpc.LOB_NAME ORDER BY wpc.FromRegDate), 0), CASE WHEN NULLIF(r.RPTCURR1_CD, '') IS NOT NULL THEN 0 END)
			,COMM_RPT2_Rate = COALESCE(SUM(CAST(wpc.COMM AS FLOAT) * fx2.ExchangeRate) OVER (PARTITION BY wpc.CONTRACT_NBR, wpc.CEDED_CONTRACT_NBR, wpc.ASSUMED_CEDED_FLG, wpc.TIRS_ORIG_CURR_CD, wpc.LOB_NAME ORDER BY wpc.FromRegDate) / NULLIF(SUM(CAST(wpc.COMM AS FLOAT)) OVER (PARTITION BY wpc.CONTRACT_NBR, wpc.CEDED_CONTRACT_NBR, wpc.ASSUMED_CEDED_FLG, wpc.TIRS_ORIG_CURR_CD, wpc.LOB_NAME ORDER BY wpc.FromRegDate), 0), CASE WHEN NULLIF(r.RPTCURR2_CD, '') IS NOT NULL THEN 0 END)
		INTO #TIRSUWRptCurrUEPRDAC
		FROM #WPCOMM wpc
		INNER JOIN #RPT r
			ON r.Contract_NBR = wpc.CONTRACT_NBR
			AND r.lob_name = wpc.LOB_NAME
		LEFT JOIN #FX fx1
			ON fx1.AccountingPeriodDate = wpc.FromRegDate
			AND fx1.FromCurrency = wpc.ISOCurrencyCode
			AND fx1.ToCurrency = r.RPTCURR1_CD
		LEFT JOIN #FX fx2
			ON fx2.AccountingPeriodDate = wpc.FromRegDate
			AND fx2.FromCurrency = wpc.ISOCurrencyCode
			AND fx2.ToCurrency = r.RPTCURR2_CD
		

		-- Loading logic
		ALTER TABLE #TIRSUWRptCurrUEPRDAC ADD DataHash BINARY(20) NULL

		UPDATE s
		SET DataHash = HASHBYTES('SHA1', CONCAT(s.ToRegDate
			, '|', s.RPTCURR1_CD
			, '|', s.RPTCURR2_CD
			, '|', s.WP_RPT1_Rate
			, '|', s.WP_RPT2_Rate
			, '|', s.COMM_RPT1_Rate
			, '|', s.COMM_RPT2_Rate))
		FROM #TIRSUWRptCurrUEPRDAC s

		DROP TABLE IF EXISTS #LoadOperation

		CREATE TABLE #LoadOperation
		(CONTRACT_NBR VARCHAR(9) COLLATE DATABASE_DEFAULT NOT NULL
		,CEDED_CONTRACT_NBR VARCHAR(9) COLLATE DATABASE_DEFAULT NOT NULL
		,ASSUMED_CEDED_FLG CHAR(1) COLLATE DATABASE_DEFAULT NOT NULL
		,TIRS_ORIG_CURR_CD VARCHAR(3) COLLATE DATABASE_DEFAULT NOT NULL
		,LOB_NAME VARCHAR(255) COLLATE DATABASE_DEFAULT NOT NULL
		,FromRegDate DATE NOT NULL
		,Operation CHAR(1) NOT NULL
		,UNIQUE (CONTRACT_NBR, CEDED_CONTRACT_NBR, ASSUMED_CEDED_FLG, TIRS_ORIG_CURR_CD, LOB_NAME, FromRegDate)
		)

		INSERT INTO #LoadOperation
			(CONTRACT_NBR
			,CEDED_CONTRACT_NBR
			,ASSUMED_CEDED_FLG
			,TIRS_ORIG_CURR_CD
			,LOB_NAME
			,FromRegDate
			,Operation
			)
		SELECT CONTRACT_NBR = COALESCE(t.CONTRACT_NBR COLLATE DATABASE_DEFAULT, s.CONTRACT_NBR COLLATE DATABASE_DEFAULT)
			,CEDED_CONTRACT_NBR = COALESCE(t.CEDED_CONTRACT_NBR COLLATE DATABASE_DEFAULT, s.CEDED_CONTRACT_NBR COLLATE DATABASE_DEFAULT)
			,ASSUMED_CEDED_FLG = COALESCE(t.ASSUMED_CEDED_FLG COLLATE DATABASE_DEFAULT, s.ASSUMED_CEDED_FLG COLLATE DATABASE_DEFAULT)
			,TIRS_ORIG_CURR_CD = COALESCE(t.TIRS_ORIG_CURR_CD COLLATE DATABASE_DEFAULT, s.TIRS_ORIG_CURR_CD COLLATE DATABASE_DEFAULT)
			,LOB_NAME = COALESCE(t.LOB_NAME COLLATE DATABASE_DEFAULT, s.LOB_NAME COLLATE DATABASE_DEFAULT)
			,FromRegDate = COALESCE(t.FromRegDate, s.FromRegDate)
			,Operation = CASE WHEN t.TIRSUWRptCurrUEPRDACID IS NULL THEN 'I' WHEN s.DataHash IS NULL THEN 'D' ELSE 'U' END
		FROM (
			SELECT t.*
			FROM assumed.TIRSUWRptCurrUEPRDAC t
			INNER JOIN (
				SELECT DISTINCT f.CONTRACT_NBR
				FROM #Filter f
				) f
				ON f.CONTRACT_NBR = t.CONTRACT_NBR COLLATE DATABASE_DEFAULT
			WHERE t.EndDate = '31 Dec 9999'
			) t
		FULL JOIN (
			SELECT s.*
			FROM #TIRSUWRptCurrUEPRDAC s
			INNER JOIN (
				SELECT DISTINCT f.CONTRACT_NBR
				FROM #Filter f
				) f
				ON f.CONTRACT_NBR = s.CONTRACT_NBR COLLATE DATABASE_DEFAULT
			) s
			ON s.CONTRACT_NBR = t.CONTRACT_NBR COLLATE DATABASE_DEFAULT
			AND s.CEDED_CONTRACT_NBR = t.CEDED_CONTRACT_NBR COLLATE DATABASE_DEFAULT
			AND s.ASSUMED_CEDED_FLG = t.ASSUMED_CEDED_FLG COLLATE DATABASE_DEFAULT
			AND s.TIRS_ORIG_CURR_CD = t.TIRS_ORIG_CURR_CD COLLATE DATABASE_DEFAULT
			AND s.LOB_NAME = t.LOB_NAME COLLATE DATABASE_DEFAULT
			AND s.FromRegDate = t.FromRegDate
		WHERE t.DataHash IS NULL
			OR s.DataHash IS NULL
			OR t.DataHash != s.DataHash

		BEGIN TRAN

		UPDATE t
		SET EndDate = p.ClosingEndDate
		FROM assumed.TIRSUWRptCurrUEPRDAC t
		INNER JOIN #LoadOperation lo
			ON lo.CONTRACT_NBR = t.CONTRACT_NBR
			AND lo.CEDED_CONTRACT_NBR = t.CEDED_CONTRACT_NBR
			AND lo.ASSUMED_CEDED_FLG = t.ASSUMED_CEDED_FLG
			AND lo.TIRS_ORIG_CURR_CD = t.TIRS_ORIG_CURR_CD
			AND lo.LOB_NAME = t.LOB_NAME
			AND lo.FromRegDate = t.FromRegDate
			AND lo.Operation IN ('U', 'D')
		CROSS JOIN #Parameters p
		WHERE t.EndDate = '31 Dec 9999'

		INSERT INTO assumed.TIRSUWRptCurrUEPRDAC
			(StartDate
			,CONTRACT_NBR
			,CEDED_CONTRACT_NBR
			,ASSUMED_CEDED_FLG
			,TIRS_ORIG_CURR_CD
			,LOB_NAME
			,FromRegDate
			,ToRegDate
			,RPTCURR1_CD
			,RPTCURR2_CD
			,WP_RPT1_Rate
			,WP_RPT2_Rate
			,COMM_RPT1_Rate
			,COMM_RPT2_Rate
			,DataHash
			)
		SELECT StartDate = p.NewStartDate
			,s.CONTRACT_NBR
			,s.CEDED_CONTRACT_NBR
			,s.ASSUMED_CEDED_FLG
			,s.TIRS_ORIG_CURR_CD
			,s.LOB_NAME
			,s.FromRegDate
			,s.ToRegDate
			,s.RPTCURR1_CD
			,s.RPTCURR2_CD
			,s.WP_RPT1_Rate
			,s.WP_RPT2_Rate
			,s.COMM_RPT1_Rate
			,s.COMM_RPT2_Rate
			,s.DataHash
		FROM #TIRSUWRptCurrUEPRDAC s
		INNER JOIN #LoadOperation lo
			ON lo.CONTRACT_NBR = s.CONTRACT_NBR COLLATE DATABASE_DEFAULT
			AND lo.CEDED_CONTRACT_NBR = s.CEDED_CONTRACT_NBR COLLATE DATABASE_DEFAULT
			AND lo.ASSUMED_CEDED_FLG = s.ASSUMED_CEDED_FLG COLLATE DATABASE_DEFAULT
			AND lo.TIRS_ORIG_CURR_CD = s.TIRS_ORIG_CURR_CD COLLATE DATABASE_DEFAULT
			AND lo.LOB_NAME = s.LOB_NAME COLLATE DATABASE_DEFAULT
			AND lo.FromRegDate = s.FromRegDate
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
