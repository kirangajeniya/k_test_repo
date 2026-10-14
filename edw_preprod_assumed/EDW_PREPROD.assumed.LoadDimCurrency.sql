-- Database: EDW_PREPROD
-- Schema: assumed
-- Procedure: LoadDimCurrency

CREATE   PROCEDURE assumed.LoadDimCurrency
AS
BEGIN
	BEGIN TRY
		DROP TABLE IF EXISTS #Parameters

		SELECT ClosingEndDate = DATEADD(NANOSECOND, -100, SYSDATETIME())
			,NewStartDate = SYSDATETIME()
		INTO #Parameters

		-- Staging logic
		
		DROP TABLE IF EXISTS #DimCurrency
		
		SELECT DISTINCT ISOCurrencyCode = 'Unc'
			,TIRS_CURR_CD = 'Unc'
			,TIRS_CURR_NAME = 'Uncoded'
		INTO #DimCurrency
		UNION ALL
		SELECT DISTINCT ISOCurrencyCode = 'N/A'
			,TIRS_CURR_CD = 'N/A'
			,TIRS_CURR_NAME = 'N/A'
		
			--Underwriting piece of Code START
		UNION
		select * from
		(SELECT DISTINCT ISOCurrencyCode = TRIM(cn.curr_iso_cd) COLLATE DATABASE_DEFAULT
			,TIRS_CURR_CD = NULLIF(TRIM(ad.curr_cd), '') COLLATE DATABASE_DEFAULT
			,TIRS_CURR_NAME = NULLIF(TRIM(cn.curr_nm), '') COLLATE DATABASE_DEFAULT
		 FROM src_tirs_db.dbo.acct_byline ab with(nolock)
		INNER JOIN SRC_TIRS_DB.dbo.acct_doc ad with(nolock)
			ON ab.doc_key = ad.doc_key
			AND ad.status_flg = 'P'
		LEFT JOIN SRC_TIRS_DB.dbo.xrf_curr_names cn with(nolock)
			ON ad.curr_cd = cn.curr_cd 
		
			UNION
			
			select DISTINCT  isnull(cn.curr_iso_cd,cn2.curr_iso_cd) COLLATE DATABASE_DEFAULT 	as ISOCurrencyCode,
			isnull(cn.curr_cd,cn2.curr_cd)COLLATE DATABASE_DEFAULT  as TIRS_CURR_CD,
			Subqry.TIRS_CURR_NAME COLLATE DATABASE_DEFAULT as TIRS_CURR_NAME 
			from(
			SELECT E.OriginalCurrencyCode as TIRS_CURR_CD,R.CURRENCY_NAME as TIRS_CURR_NAME
			from edw_preprod.lloyds.tbl_ep_gp_llyds E with(nolock)
			OUTER APPLY (SELECT TOP 1 R.TIRS_CURRENCY_CODE,R.CURRENCY_NAME  
			FROM EDW_PREPROD.dbo.EDW_TIRS_ROE   R with(nolock) WHERE E.OriginalCurrencyCode=R.TIRS_CURRENCY_CODE ORDER BY R.K1PERIOD_OF_TIME desc)	 R	
			  WHERE businesstype='Assumed'
				and PolicySource='Openbox')Subqry
				 inner join SRC_TIRS_DB.dbo.xrf_curr_names cn with(nolock)
			ON ((Subqry.TIRS_CURR_NAME = cn.curr_nm COLLATE Latin1_General_CI_AI) 
			OR (Subqry.TIRS_CURR_CD  = cn.curr_cd COLLATE Latin1_General_CI_AI))
			 inner join SRC_TIRS_DB.dbo.xrf_curr_names cn2 with(nolock) on cn2.status_flg = 'A' and
			cn2.curr_iso_cd = Subqry.TIRS_CURR_CD COLLATE Latin1_General_CI_AI)UNDWCur
			
			--Underwriting piece of Code END
		
		UNION  (
		SELECT DISTINCT ISOCurrencyCode = TRIM(cn.curr_iso_cd) COLLATE DATABASE_DEFAULT
			,TIRS_CURR_CD = NULLIF(TRIM(ad.curr_cd), '') COLLATE DATABASE_DEFAULT
			,TIRS_CURR_NAME = NULLIF(TRIM(cn.curr_nm), '') COLLATE DATABASE_DEFAULT
		FROM src_tirs_db.dbo.acct_byline ab
		INNER JOIN SRC_TIRS_DB.dbo.acct_doc ad
			ON ab.doc_key = ad.doc_key
			AND ad.status_flg = 'P'
		INNER JOIN SRC_TIRS_DB.dbo.xrf_curr_names cn
			ON ad.curr_cd = cn.curr_cd
		UNION
		SELECT DISTINCT ISOCurrencyCode = TRIM(cn.curr_iso_cd) COLLATE DATABASE_DEFAULT
			,TIRS_CURR_CD = COALESCE(TRIM(ct.curr_cd), TRIM(c.curr_cd)) COLLATE DATABASE_DEFAULT
			,TIRS_CURR_NAME = NULLIF(TRIM(cn.curr_nm), '') COLLATE DATABASE_DEFAULT
		FROM SRC_TIRS_DB.dbo.claim c
		INNER JOIN SRC_TIRS_DB.dbo.claim_trans ct
			ON ct.clm_key = c.clm_key
		LEFT JOIN SRC_TIRS_DB.dbo.xrf_curr_names cn
			ON COALESCE(ct.curr_cd, c.curr_cd) = cn.curr_cd
		UNION
		SELECT ISOCurrencyCode = TRIM(cn.curr_iso_cd) COLLATE DATABASE_DEFAULT
			,TIRS_CURR_CD = TRIM(cn.curr_cd) COLLATE DATABASE_DEFAULT
			,TIRS_CURR_NAME = NULLIF(TRIM(cn.curr_nm), '') COLLATE DATABASE_DEFAULT
		FROM (
			SELECT DISTINCT TIRS_ORIG_CURR_CD
			FROM EDW_PREPROD.dbo.RS_TIRS_CLAIMS_TOPSIDE rtct
			) x
		INNER JOIN SRC_TIRS_DB.dbo.xrf_curr_names cn
			ON cn.curr_cd = x.TIRS_ORIG_CURR_CD COLLATE DATABASE_DEFAULT
		UNION
		SELECT ISOCurrencyCode = TRIM(cn.curr_iso_cd) COLLATE DATABASE_DEFAULT
			,TIRS_CURR_CD = TRIM(cn.curr_cd) COLLATE DATABASE_DEFAULT
			,TIRS_CURR_NAME = NULLIF(TRIM(cn.curr_nm), '') COLLATE DATABASE_DEFAULT
		FROM (
			SELECT DISTINCT y.CurrCode
			FROM EDW_PREPROD.lloyds.TBL_CLAIM_LLYDS tcl
			CROSS APPLY (
				SELECT x.CurrCode
				FROM (
					VALUES(tcl.OrigCurrCode)
					,(tcl.SettCurrCode)
					) x (CurrCode)
				) y
			WHERE y.CurrCode NOT IN ('', '-9999')
			) z
		INNER JOIN SRC_TIRS_DB.dbo.xrf_curr_names cn
			ON cn.curr_iso_cd = z.CurrCode COLLATE DATABASE_DEFAULT
		WHERE cn.status_flg = 'A'
		)
		

		-- Loading logic
		ALTER TABLE #DimCurrency ADD DataHash BINARY(20) NULL

		UPDATE s
		SET DataHash = HASHBYTES('SHA1', CONCAT(s.TIRS_CURR_CD
			, '|', s.TIRS_CURR_NAME))
		FROM #DimCurrency s

		DROP TABLE IF EXISTS #LoadOperation

		CREATE TABLE #LoadOperation
		(ISOCurrencyCode VARCHAR(3) COLLATE DATABASE_DEFAULT NOT NULL
		,Operation CHAR(1) NOT NULL
		,UNIQUE (ISOCurrencyCode)
		)

		INSERT INTO #LoadOperation
			(ISOCurrencyCode
			,Operation
			)
		SELECT ISOCurrencyCode = COALESCE(t.ISOCurrencyCode COLLATE DATABASE_DEFAULT, s.ISOCurrencyCode COLLATE DATABASE_DEFAULT)
			,Operation = CASE WHEN t.DimCurrencyID IS NULL THEN 'I' WHEN s.DataHash IS NULL THEN 'D' ELSE 'U' END
		FROM (
			SELECT t.*
			FROM assumed.DimCurrency t
			WHERE t.EndDate = '31 Dec 9999'
			) t
		FULL JOIN #DimCurrency s
			ON s.ISOCurrencyCode = t.ISOCurrencyCode COLLATE DATABASE_DEFAULT
		WHERE t.DataHash IS NULL
			OR s.DataHash IS NULL
			OR t.DataHash != s.DataHash

		BEGIN TRAN

		UPDATE t
		SET EndDate = p.ClosingEndDate
		FROM assumed.DimCurrency t
		INNER JOIN #LoadOperation lo
			ON lo.ISOCurrencyCode = t.ISOCurrencyCode
			AND lo.Operation = 'U'
		CROSS JOIN #Parameters p
		WHERE t.EndDate = '31 Dec 9999'

		INSERT INTO assumed.DimCurrency
			(StartDate
			,ISOCurrencyCode
			,TIRS_CURR_CD
			,TIRS_CURR_NAME
			,DataHash
			)
		SELECT StartDate = p.NewStartDate
			,s.ISOCurrencyCode
			,s.TIRS_CURR_CD
			,s.TIRS_CURR_NAME
			,s.DataHash
		FROM #DimCurrency s
		INNER JOIN #LoadOperation lo
			ON lo.ISOCurrencyCode = s.ISOCurrencyCode COLLATE DATABASE_DEFAULT
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
