-- Database: EDW_PREPROD
-- Schema: assumed
-- Procedure: LoadDimExchangeRate

CREATE   PROCEDURE assumed.LoadDimExchangeRate
AS
BEGIN
	BEGIN TRY
		DROP TABLE IF EXISTS #Parameters

		SELECT ClosingEndDate = DATEADD(NANOSECOND, -100, SYSDATETIME())
			,NewStartDate = SYSDATETIME()
		INTO #Parameters

		-- Staging logic
		
		DROP TABLE IF EXISTS #AccountingPeriod

		SELECT x.AccountingPeriodDate
			,x.AccountingStartDate
			,x.AccountingEndDate
		INTO #AccountingPeriod
		FROM (
			SELECT AccountingPeriodDate = CAST(ap.accounting_period_date AS DATE)
				,AccountingStartDate = CAST(DATEADD(DAY, 1, LAG(ap.accounting_period_close_date) OVER (ORDER BY ap.accounting_period_key)) AS DATE)
				,AccountingEndDate = CAST(ap.accounting_period_close_date AS DATE)
			FROM Insight.dbo.accounting_periods ap
			) x
		WHERE x.AccountingStartDate IS NOT NULL

		DROP TABLE IF EXISTS #ContractOrigCurrency
			
		SELECT DISTINCT ad.reg_date
			,lob_name = TRIM(lob.desc_txt) COLLATE DATABASE_DEFAULT
			,ad.Contract_NBR
			,FromCurrency = TRIM(cn.curr_iso_cd) COLLATE DATABASE_DEFAULT
			,TIRSFromCurrency = cn.curr_cd COLLATE DATABASE_DEFAULT
		INTO #ContractOrigCurrency
		FROM src_tirs_db.dbo.acct_byline ab
		INNER JOIN (
			SELECT Contract_NBR = CAST(ad.trty_no AS VARCHAR(5)) + CAST(TRIM(ad.und_yr) AS VARCHAR(4)) COLLATE DATABASE_DEFAULT
				,reg_date = CAST(COALESCE(ad.reg_dt, DATEADD(MONTH, DATEDIFF(MONTH, 0, ad.create_dt), 0)) AS DATE)
				,ad.doc_key
				,ad.curr_cd
			FROM SRC_TIRS_DB.dbo.acct_doc ad
			WHERE ad.status_flg = 'P'
			) ad
			ON ab.doc_key = ad.doc_key
		INNER JOIN SRC_TIRS_DB.dbo.xrf_lob_cds lob
			ON lob.lob_cd = ab.pr_cls_cd
		INNER JOIN SRC_TIRS_DB.dbo.xrf_curr_names cn
			ON ad.curr_cd = cn.curr_cd
		UNION
		SELECT DISTINCT c.reg_date
			,lob_name = TRIM(lob.desc_txt) COLLATE DATABASE_DEFAULT
			,tm.Contract_NBR
			,FromCurrency = TRIM(cn.curr_iso_cd) COLLATE DATABASE_DEFAULT
			,TIRSFromCurrency = cn.curr_cd COLLATE DATABASE_DEFAULT
		FROM (
			SELECT reg_date = CAST(COALESCE(ct.reg_dt, DATEADD(MONTH, DATEDIFF(MONTH, 0, c.create_dt), 0)) AS DATE)
				,c.trty_key
				,c.lob_key
				,ct.curr_cd
			FROM SRC_TIRS_DB.dbo.claim c
			INNER JOIN SRC_TIRS_DB.dbo.claim_trans ct
				ON ct.clm_key = c.clm_key
			) c
		INNER JOIN (
			SELECT Contract_NBR = CAST(tm.trty_no AS CHAR(5)) + CAST(TRIM(tm.und_yr) AS CHAR(4)) COLLATE DATABASE_DEFAULT
				,tm.trty_key
			FROM src_tirs_db.dbo.trty_master tm
			) tm
			ON tm.trty_key = c.trty_key
		LEFT JOIN SRC_TIRS_DB.dbo.xrf_lob_cds lob
			ON lob.lob_cd = c.lob_key
		LEFT JOIN SRC_TIRS_DB.dbo.xrf_curr_names cn
			ON c.curr_cd = cn.curr_cd
			
		DROP TABLE IF EXISTS #MissingCombinations
			
		SELECT DISTINCT tcer.Reg_Date
			,lob_name = h.lob_name COLLATE DATABASE_DEFAULT
			,Contract_NBR = tcer.Contract_NBR COLLATE DATABASE_DEFAULT
		INTO #MissingCombinations
		FROM (
			SELECT tcer.Contract_NBR
				,tcer.Reg_Date
				,offset_reg_date = DATEADD(DAY, 1, tcer.Reg_Date)
			FROM EDW_PREPROD.dbo.TIRS_Contract_Earning_Rates tcer
			) tcer
		INNER JOIN EDW_PREPROD.dbo.T_Code_history h
			ON h.START_DATE < tcer.offset_reg_date
				AND h.END_DATE > tcer.offset_reg_date
				AND h.Contract_NBR = tcer.CONTRACT_NBR
		EXCEPT
		SELECT DISTINCT reg_date
			,lob_name = lob_name COLLATE DATABASE_DEFAULT
			,Contract_NBR = Contract_NBR COLLATE DATABASE_DEFAULT
		FROM #ContractOrigCurrency
			
		DROP TABLE IF EXISTS #ContractCurrencyLookup
			
		SELECT DISTINCT coc.lob_name	
			,coc.Contract_NBR
			,coc.FromCurrency
			,coc.TIRSFromCurrency
		INTO #ContractCurrencyLookup
		FROM #ContractOrigCurrency coc
			
		INSERT INTO #ContractOrigCurrency
			(reg_date
			,lob_name
			,Contract_NBR
			,FromCurrency
			,TIRSFromCurrency
			)
		SELECT mc.Reg_Date
			,mc.lob_name	
			,mc.Contract_NBR
			,ccl.FromCurrency
			,ccl.TIRSFromCurrency
		FROM #MissingCombinations mc
		INNER JOIN #ContractCurrencyLookup ccl
			ON ccl.lob_name	= mc.lob_name
			AND ccl.Contract_NBR = mc.Contract_NBR
			
		DROP TABLE IF EXISTS #DimExchangeRate
			
		SELECT DISTINCT FromCurrency = coc.FromCurrency
			,TIRSFromCurrency = coc.TIRSFromCurrency
			,ToCurrency = rc.RPTCURR
			,AccountingPeriodDate = coc.reg_date
			,Source = CAST('Genius' AS VARCHAR(15))
			,RateDescription = CONCAT(coc.FromCurrency COLLATE DATABASE_DEFAULT, '-', rc.RPTCURR, ' ', CONVERT(VARCHAR(7), coc.reg_date, 120))
			,ExchangeRate = CAST(NULL AS DECIMAL(28,15))
		INTO #DimExchangeRate
		FROM (
			SELECT coc.*
				,offset_reg_date = DATEADD(DAY, 1, coc.reg_date)
			FROM #ContractOrigCurrency coc
			) coc
		LEFT JOIN edw_preprod.dbo.T_Code_history h
			ON h.START_DATE < coc.offset_reg_date
				AND h.END_DATE > coc.offset_reg_date
				AND h.lob_name = coc.lob_name COLLATE DATABASE_DEFAULT
				AND h.Contract_NBR = coc.Contract_NBR COLLATE DATABASE_DEFAULT
		CROSS APPLY (
			VALUES(NULLIF(h.RPTCURR1_CD, ''))
				,(NULLIF(h.RPTCURR2_CD, ''))
			) rc (RPTCURR)
		WHERE rc.RPTCURR IS NOT NULL
		UNION
		-- manually entered data based on historically produced data that is no longer generated by the code
		SELECT x.FromCurrency
			,x.TIRSFromCurrency
			,x.ToCurrency
			,x.AccountingPeriodDate
			,Source = CAST('Genius' AS VARCHAR(15))
			,RateDescription = CONCAT(x.FromCurrency, '-', x.ToCurrency, ' ', CONVERT(VARCHAR(7), CAST(x.AccountingPeriodDate AS DATE), 120))
			,ExchangeRate = CAST(NULL AS DECIMAL(28,15))
		FROM (
			VALUES('CAD', '011', 'GBP', '1 May 2014')
				 ,('INR', '026', 'SGD', '1 May 2010')
			) x (FromCurrency, TIRSFromCurrency, ToCurrency, AccountingPeriodDate)
		UNION
		SELECT DISTINCT FromCurrency = cn.curr_iso_cd COLLATE DATABASE_DEFAULT
			,TIRSFromCurrency = cn.curr_cd COLLATE DATABASE_DEFAULT
			,ToCurrency = rc.RPTCURR
			,AccountingPeriodDate = rtct.reg_date
			,Source = CAST('Genius' AS VARCHAR(15))
			,RateDescription = CONCAT(cn.curr_iso_cd COLLATE DATABASE_DEFAULT, '-', rc.RPTCURR, ' ', CONVERT(VARCHAR(7), rtct.reg_date, 120))
			,ExchangeRate = CAST(NULL AS DECIMAL(28,15))
		FROM EDW_PREPROD.dbo.RS_TIRS_CLAIMS_TOPSIDE rtct
		INNER JOIN SRC_TIRS_DB.dbo.xrf_curr_names cn
			ON cn.curr_cd = rtct.TIRS_ORIG_CURR_CD COLLATE DATABASE_DEFAULT
		CROSS APPLY (
			VALUES(NULLIF(rtct.RPTCURR1_CD, ''))
				,(NULLIF(rtct.RPTCURR2_CD, ''))
			) rc (RPTCURR)
		WHERE rc.RPTCURR IS NOT NULL
		UNION
		SELECT DISTINCT y.FromCurrency
			,TIRSFromCurrency = cn.curr_cd COLLATE DATABASE_DEFAULT
			,y.ToCurrency
			,AccountingPeriodDate = tcl.accounting_period_date
			,Source = CAST('Genius' AS VARCHAR(15))
			,RateDescription = CONCAT(y.FromCurrency, '-', y.ToCurrency, ' ', CONVERT(VARCHAR(7), tcl.accounting_period_date, 120))
			,ExchangeRate = CAST(NULL AS DECIMAL(28,15))
		FROM EDW_PREPROD.lloyds.TBL_CLAIM_LLYDS tcl
		CROSS APPLY (
			SELECT *
			FROM (
				VALUES(tcl.OrigCurrCode, 'GBP')
				,(NULLIF(tcl.SettCurrCode, ''), 'GBP')
				) x (FromCurrency, ToCurrency)
			) y
		LEFT JOIN SRC_TIRS_DB.dbo.xrf_curr_names cn
			ON cn.curr_iso_cd = y.FromCurrency COLLATE DATABASE_DEFAULT
			AND cn.status_flg = 'A'
		WHERE tcl.businesstype = 'Assumed'
			AND tcl.PolicySource = 'Openbox'
			AND y.FromCurrency IS NOT NULL
		UNION
		SELECT FromCurrency = E.OriginalCurrencyCode
			,TIRSFromCurrency = R.TIRS_CURRENCY_CODE
			,ToCurrency = 'GBP'
			,AccountingPeriodDate = E.AccountingDate
			,Source = CAST('Genius' AS VARCHAR(15))
			,RateDescription = CONCAT(E.OriginalCurrencyCode, '-', 'GBP', ' ', CONVERT(VARCHAR(7), E.AccountingDate, 120))
			,ExchangeRate = CAST(NULL AS DECIMAL(28,15))
		  FROM EDW_PREPROD.lloyds.tbl_ep_gp_llyds E 
				OUTER APPLY (SELECT TOP 1 R.TIRS_CURRENCY_CODE, R.CURRENCY_NAME
							   FROM EDW_PREPROD.dbo.EDW_TIRS_ROE   R
							  WHERE E.OriginalCurrencyCode = R.K1CURRENCY_CODE ORDER BY R.K1PERIOD_OF_TIME desc)	 R	
		 WHERE businesstype='Assumed'
		   AND PolicySource='Openbox'
		 GROUP BY E.OriginalCurrencyCode, R.TIRS_CURRENCY_CODE, E.AccountingDate
		UNION
		SELECT FromCurrency = cn.curr_iso_cd COLLATE DATABASE_DEFAULT
			,TIRSFromCurrency = cn.curr_cd COLLATE DATABASE_DEFAULT
			,ToCurrency = rc.RPTCURR
			,AccountingPeriodDate = rtct.reg_date
			,Source = CAST('Genius' AS VARCHAR(15))
			,RateDescription = CONCAT(cn.curr_iso_cd COLLATE DATABASE_DEFAULT, '-', rc.RPTCURR, ' ', CONVERT(VARCHAR(7), rtct.reg_date, 120))
			,ExchangeRate = CAST(NULL AS DECIMAL(28,15))
		FROM EDW_PREPROD.dbo.RS_TIRS_UNDERWRITING_TOPSIDE rtct
		INNER JOIN SRC_TIRS_DB.dbo.xrf_curr_names cn
			ON cn.curr_cd = rtct.TIRS_ORIG_CURR_CD COLLATE DATABASE_DEFAULT
		CROSS APPLY (
			VALUES(NULLIF(rtct.RPTCURR1_CD, ''))
				,(NULLIF(rtct.RPTCURR2_CD, ''))
			) rc (RPTCURR)
		WHERE rc.RPTCURR IS NOT NULL
		UNION
		SELECT FromCurrency = cur.SCCY
			,TIRSFromCurrency = cn.curr_cd COLLATE DATABASE_DEFAULT
			,ToCurrency = 'GBP'
			,AccountingPeriodDate = ap.AccountingPeriodDate
			,Source = CAST('Genius' AS VARCHAR(15))
			,RateDescription = CONCAT(cur.SCCY, '-GBP ', CONVERT(VARCHAR(7), ap.AccountingPeriodDate, 120))
			,ExchangeRate = CAST(NULL AS DECIMAL(28,15))
		FROM SRC_LLOYDS_DB.dbo.PolicyLiability pl
		INNER JOIN SRC_LLOYDS_DB.dbo.PolicySection ps
			ON ps.lPolicySectionKey = pl.lPolicySectionKey
		INNER JOIN SRC_LLOYDS_DB.dbo.Policy p
			ON p.lPolicyKey = pl.lPolicyKey
			AND p.lActivePolicyActivityKey = pl.lPolicyActivityKey
		INNER JOIN SRC_LLOYDS_DB.dbo.PolicyActivity pa
			ON pa.lPolicyActivityKey = pl.lPolicyActivityKey
		INNER JOIN SRC_LLOYDS_DB.dbo.Typeofreportinglayer torl
			ON torl.lTypeOfReportingLayerKey = pa.lTypeOfReportingLayerKey
		INNER JOIN SRC_LLOYDS_DB.dbo.TypeOfProductgroup topg
			ON topg.lTypeOfProductGroupKey = torl.lTypeOfProductGroupKey
			AND topg.sCode = 'RI'
		INNER JOIN SRC_LLOYDS_DB.dbo.EntityInstanceStates pseis
			ON pseis.lInstanceKey = pl.lPolicySectionKey
			AND pseis.lEntityKey = 614
		INNER JOIN SRC_LLOYDS_DB.dbo.EntitystateMembers psesm
			ON psesm.lEntityStateMemberKey = pseis.lEntityStateMemberKey
			AND psesm.sEntityStateMember IN ('Cancelled', 'Current', 'Endorsement Data Entry', 'Written')
		INNER JOIN SRC_LLOYDS_DB.dbo.EntityInstanceStates peis
			ON peis.lInstanceKey = p.lPolicyKey
			AND peis.lEntityKey = 608
		INNER JOIN SRC_LLOYDS_DB.dbo.EntitystateMembers pesm
			ON pesm.lEntityStateMemberKey = peis.lEntityStateMemberKey
			AND pesm.sEntityStateMember IN ('Booked', 'Cancelled', 'Endorsement Data Entry', 'Expired', 'Renewed', 'Written')
		INNER JOIN SRC_LLOYDS_DB.dbo.Currency cur
			ON cur.lCurrencyKey = pl.lLiabilityPremiumCcyKey
		INNER JOIN #AccountingPeriod ap
			ON pa.dtPeriodFrom BETWEEN ap.AccountingStartDate AND ap.AccountingEndDate
		LEFT JOIN SRC_TIRS_DB.dbo.xrf_curr_names cn
			ON cn.curr_iso_cd = cur.SCCY COLLATE DATABASE_DEFAULT
			AND cn.status_flg = 'A'
		UNION
		SELECT FromCurrency = ma.OriginalCurrencyCode
			,TIRSFromCurrency = cn.curr_cd COLLATE DATABASE_DEFAULT
			,ToCurrency = 'GBP'
			,AccountingPeriodDate = ma.AccountingDate
			,Source = CAST('Genius' AS VARCHAR(15))
			,RateDescription = CONCAT(ma.OriginalCurrencyCode, '-GBP ', CONVERT(VARCHAR(7), ma.AccountingDate, 120))
			,ExchangeRate = CAST(NULL AS DECIMAL(28,15))
		FROM SRC_LLOYDS_DB.SSIS.tbl_ep_gp_llyds_manual_adjustments ma
		LEFT JOIN SRC_TIRS_DB.dbo.xrf_curr_names cn
			ON cn.curr_iso_cd = ma.OriginalCurrencyCode COLLATE DATABASE_DEFAULT
			AND cn.status_flg = 'A'
		WHERE ma.BusinessType = 'Assumed'
			AND ma.PolicySource = 'OPENBOX'

		DROP TABLE IF EXISTS #FX
			
		SELECT AccountingPeriodDate = CAST(LEFT(lgc.JoinMonth, 4) + RIGHT(lgc.JoinMonth, 2) + '01' AS DATE)
			,FromCurrency = lgc.ISOCode
			,ToCurrency = 'USD'
			,ExchangeRate = MIN(lgc.ExchangeRate)
		INTO #FX
		FROM EDW_PREPROD.dbo.LOOKUP_GENIUS_CURRENCYRATES lgc
		WHERE JoinMonth IS NOT NULL
		GROUP BY CAST(LEFT(lgc.JoinMonth, 4) + RIGHT(lgc.JoinMonth, 2) + '01' AS DATE)
			,lgc.ISOCode
			
		UPDATE daer
		SET ExchangeRate = CASE WHEN daer.FromCurrency = daer.ToCurrency COLLATE DATABASE_DEFAULT THEN 1 ELSE f.ExchangeRate / t.ExchangeRate END
		FROM #DimExchangeRate daer
		LEFT JOIN #FX f
			ON f.FromCurrency = daer.FromCurrency COLLATE DATABASE_DEFAULT
			AND f.AccountingPeriodDate = daer.AccountingPeriodDate
		LEFT JOIN #FX t
			ON t.FromCurrency = daer.ToCurrency COLLATE DATABASE_DEFAULT
			AND t.AccountingPeriodDate = daer.AccountingPeriodDate
			
		DROP TABLE IF EXISTS #ToUSD
			
		SELECT DISTINCT AccountingPeriodDate = coc.reg_date
			,coc.FromCurrency
			,coc.TIRSFromCurrency
		INTO #ToUSD
		FROM #ContractOrigCurrency coc
		LEFT JOIN #DimExchangeRate daer2
			ON daer2.AccountingPeriodDate = coc.reg_date
			AND daer2.FromCurrency = coc.FromCurrency
			AND daer2.TIRSFromCurrency = coc.TIRSFromCurrency
			AND daer2.ToCurrency = 'USD'
		WHERE daer2.AccountingPeriodDate IS NULL
			
		INSERT INTO #DimExchangeRate
			(FromCurrency
			,TIRSFromCurrency
			,ToCurrency
			,AccountingPeriodDate
			,Source
			,RateDescription
			,ExchangeRate
			)
		SELECT DISTINCT FromCurrency = '-?-'
			,TIRSFromCurrency = '-?-'
			,ToCurrency = '-?-'
			,AccountingPeriodDate = '1 Jan 1900'
			,Source = 'Uncoded'
			,RateDescription = 'Uncoded'
			,ExchangeRate = CAST(NULL AS DECIMAL(28,15))
		UNION ALL
		SELECT DISTINCT FromCurrency = '---'
			,TIRSFromCurrency = '---'
			,ToCurrency = '---'
			,AccountingPeriodDate = '1 Jan 1900'
			,Source = 'N/A'
			,RateDescription = 'N/A'
			,ExchangeRate = CAST(NULL AS DECIMAL(28,15))
		UNION ALL
		SELECT tu.FromCurrency
			,tu.TIRSFromCurrency
			,ToCurrency = 'USD'
			,tu.AccountingPeriodDate
			,Source = 'TIRS'
			,RateDescription = CONCAT(tu.FromCurrency, '-USD ', CONVERT(VARCHAR(7), tu.AccountingPeriodDate, 120))
			,ExchangeRate = xcc.xch_rt
		FROM #ToUSD tu
		LEFT JOIN (
			SRC_TIRS_DB.dbo.xrf_curr_names cn
			INNER JOIN SRC_TIRS_DB.dbo.xrf_curr_cds xcc
				ON xcc.curr_cd = cn.curr_cd
			)
			ON cn.curr_cd = tu.TIRSFromCurrency COLLATE DATABASE_DEFAULT
			AND xcc.xch_rt_dt = tu.AccountingPeriodDate
		

		-- Loading logic
		ALTER TABLE #DimExchangeRate ADD DataHash BINARY(20) NULL

		UPDATE s
		SET DataHash = HASHBYTES('SHA1', CONCAT(s.TIRSFromCurrency
			, '|', s.Source
			, '|', s.RateDescription
			, '|', s.ExchangeRate))
		FROM #DimExchangeRate s

		DROP TABLE IF EXISTS #LoadOperation

		CREATE TABLE #LoadOperation
		(FromCurrency CHAR(3) COLLATE DATABASE_DEFAULT NOT NULL
		,ToCurrency CHAR(3) COLLATE DATABASE_DEFAULT NOT NULL
		,AccountingPeriodDate DATE NOT NULL
		,Operation CHAR(1) NOT NULL
		,UNIQUE (FromCurrency, ToCurrency, AccountingPeriodDate)
		)

		INSERT INTO #LoadOperation
			(FromCurrency
			,ToCurrency
			,AccountingPeriodDate
			,Operation
			)
		SELECT FromCurrency = COALESCE(t.FromCurrency COLLATE DATABASE_DEFAULT, s.FromCurrency COLLATE DATABASE_DEFAULT)
			,ToCurrency = COALESCE(t.ToCurrency COLLATE DATABASE_DEFAULT, s.ToCurrency COLLATE DATABASE_DEFAULT)
			,AccountingPeriodDate = COALESCE(t.AccountingPeriodDate, s.AccountingPeriodDate)
			,Operation = CASE WHEN t.DimExchangeRateID IS NULL THEN 'I' WHEN s.DataHash IS NULL THEN 'D' ELSE 'U' END
		FROM (
			SELECT t.*
			FROM assumed.DimExchangeRate t
			WHERE t.EndDate = '31 Dec 9999'
			) t
		FULL JOIN #DimExchangeRate s
			ON s.FromCurrency = t.FromCurrency COLLATE DATABASE_DEFAULT
			AND s.ToCurrency = t.ToCurrency COLLATE DATABASE_DEFAULT
			AND s.AccountingPeriodDate = t.AccountingPeriodDate
		WHERE t.DataHash IS NULL
			OR s.DataHash IS NULL
			OR t.DataHash != s.DataHash

		BEGIN TRAN

		UPDATE t
		SET EndDate = p.ClosingEndDate
		FROM assumed.DimExchangeRate t
		INNER JOIN #LoadOperation lo
			ON lo.FromCurrency = t.FromCurrency
			AND lo.ToCurrency = t.ToCurrency
			AND lo.AccountingPeriodDate = t.AccountingPeriodDate
			AND lo.Operation = 'U'
		CROSS JOIN #Parameters p
		WHERE t.EndDate = '31 Dec 9999'

		INSERT INTO assumed.DimExchangeRate
			(StartDate
			,FromCurrency
			,TIRSFromCurrency
			,ToCurrency
			,AccountingPeriodDate
			,Source
			,RateDescription
			,ExchangeRate
			,DataHash
			)
		SELECT StartDate = p.NewStartDate
			,s.FromCurrency
			,s.TIRSFromCurrency
			,s.ToCurrency
			,s.AccountingPeriodDate
			,s.Source
			,s.RateDescription
			,s.ExchangeRate
			,s.DataHash
		FROM #DimExchangeRate s
		INNER JOIN #LoadOperation lo
			ON lo.FromCurrency = s.FromCurrency COLLATE DATABASE_DEFAULT
			AND lo.ToCurrency = s.ToCurrency COLLATE DATABASE_DEFAULT
			AND lo.AccountingPeriodDate = s.AccountingPeriodDate
			AND lo.Operation IN ('I', 'U')
		CROSS JOIN #Parameters p

		COMMIT

		DECLARE @ProcessName VARCHAR(100) = OBJECT_SCHEMA_NAME(@@PROCID) + '.' + OBJECT_NAME(@@PROCID)
		DECLARE @RowsProcessed BIGINT = COALESCE((SELECT COUNT(0) FROM #LoadOperation WHERE Operation IN ('I', 'U')), 0)
		DECLARE @LastIdentity BIGINT = SCOPE_IDENTITY()
		DECLARE @ProcessingStarted DATETIME = (SELECT p.NewStartDate FROM #Parameters p)
		DECLARE @ProcessingEnded DATETIME = GETDATE()
		DECLARE @SourceDataDate DATETIME = (SELECT [sql_date] FROM ETL.dbo.[day] WHERE today = 1)

		EXEC ETL.dbo.update_etl_controller @ps_process_name = @ProcessName
			,@pn_rows_processed = @RowsProcessed
			,@pdt_data_datetime = @SourceDataDate
			,@pdt_process_start_datetime = @ProcessingStarted
			,@pdt_process_end_datetime = @ProcessingEnded
			,@pn_error_number = 0
			,@ps_comment = NULL
			,@pn_max_processed_event_id = @LastIdentity
	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > 0
		BEGIN
			ROLLBACK
		END

		DECLARE @ErrorDescription VARCHAR(8000) = CONCAT('Error: ', ERROR_NUMBER(), ' - ', ERROR_MESSAGE(), '; ', 'Occurred in procedure: ' + ERROR_PROCEDURE() + ', ', 'Line ', ERROR_LINE())
		DECLARE @ErrorNumber INT = ERROR_NUMBER()
		DECLARE @ErrorMessage VARCHAR(8000) = ERROR_MESSAGE()
		DECLARE @ErrorSeverity INT = ERROR_SEVERITY()
		DECLARE @ErrorState INT = ERROR_STATE()
		DECLARE @ProcessNameC VARCHAR(100) = OBJECT_SCHEMA_NAME(@@PROCID) + '.' + OBJECT_NAME(@@PROCID)
		DECLARE @ProcessingStartedC DATETIME = (SELECT p.NewStartDate FROM #Parameters p)
		DECLARE @ProcessingEndedC DATETIME = GETDATE()
		DECLARE @SourceDataDateC DATETIME = (SELECT [sql_date] FROM ETL.dbo.[day] WHERE today = 1)

		EXEC ETL.dbo.update_etl_controller @ps_process_name = @ProcessNameC
			,@pn_rows_processed = 0
			,@pdt_data_datetime = @SourceDataDateC
			,@pdt_process_start_datetime = @ProcessingStartedC
			,@pdt_process_end_datetime = @ProcessingEndedC
			,@pn_error_number = @ErrorNumber
			,@ps_comment = @ErrorDescription
			,@pn_max_processed_event_id = 0

		EXEC ETL.dbo.insert_error_log @process_name = @ProcessNameC
			,@object_name = 0
			,@user_message = @ErrorDescription
			,@status = 0
			,@remedy = 'Contact EDW team'

		RAISERROR(@ErrorMessage, @ErrorSeverity, @ErrorState)
	END CATCH
END
