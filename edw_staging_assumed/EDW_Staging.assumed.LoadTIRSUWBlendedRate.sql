-- Database: EDW_Staging
-- Schema: assumed
-- Procedure: LoadTIRSUWBlendedRate

CREATE   PROCEDURE assumed.LoadTIRSUWBlendedRate
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
			,IncrementalLoad = ~@fullLoad & CAST(COALESCE((SELECT TOP 1 1 FROM assumed.TIRSUWBlendedRate), 0) AS BIT) -- ensure a full load if the target table is empty
			,ChangedSince = DATEADD(DAY, -1, (SELECT MAX(StartDate) FROM assumed.TIRSUWBlendedRate))
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
		FROM assumed.TIRSUWBlendedRate s
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
		
		DROP TABLE IF EXISTS #TIRSUWBlendedRate
		
		SELECT x.CONTRACT_NBR
			,x.assumed_ceded_flg
			,x.TIRS_ORIG_CURR_CD
			,FromRegDate = x.reg_date
			,ToRegDate = COALESCE(DATEADD(MONTH, -1, LEAD(x.reg_date) OVER (PARTITION BY x.CONTRACT_NBR, x.assumed_ceded_flg, x.TIRS_ORIG_CURR_CD ORDER BY x.reg_date)), '1 Dec 9999')
			,BlendedRate = COALESCE(CAST(CAST(SUM(x.SUMMABLE_WRTN_PREM_USD) OVER (PARTITION BY x.CONTRACT_NBR, x.assumed_ceded_flg, x.TIRS_ORIG_CURR_CD ORDER BY x.reg_date) AS DECIMAL(19,7)) / CAST(NULLIF(SUM(x.SUMMABLE_WRTN_PREM) OVER (PARTITION BY x.CONTRACT_NBR, x.assumed_ceded_flg, x.TIRS_ORIG_CURR_CD ORDER BY x.reg_date), 0) AS DECIMAL(19,7)) AS DECIMAL(19,12)), 1)
		INTO #TIRSUWBlendedRate
		FROM (
			SELECT CONTRACT_NBR = TRIM(CAST(ad.trty_no AS CHAR(5))) + TRIM(CAST(ad.und_yr AS CHAR(4))) COLLATE DATABASE_DEFAULT
				,assumed_ceded_flg = ad.assumed_ceded_flg COLLATE DATABASE_DEFAULT
				,TIRS_ORIG_CURR_CD = TRIM(ad.curr_cd) COLLATE DATABASE_DEFAULT
				,reg_date = CAST(COALESCE(reg_dt, DATEADD(MONTH, DATEDIFF(MONTH, 0, ad.create_dt), 0)) AS DATE)
				,SUMMABLE_WRTN_PREM = SUM(COALESCE(ab.prem_wr, 0))
				,SUMMABLE_WRTN_PREM_USD = SUM(COALESCE(ab.prem_wr * xt.xch_rt, 0))
			FROM SRC_TIRS_DB.dbo.acct_byline ab
			INNER JOIN SRC_TIRS_DB.dbo.acct_doc ad
				ON ab.doc_key = ad.doc_key
			INNER JOIN #Filter f
				ON f.CONTRACT_NBR = TRIM(CAST(ad.trty_no AS CHAR(5))) + TRIM(CAST(ad.und_yr AS CHAR(4))) COLLATE DATABASE_DEFAULT
			LEFT JOIN SRC_TIRS_DB.dbo.xrf_lob_cds lob
				ON lob.lob_cd = ab.pr_cls_cd
			LEFT JOIN SRC_TIRS_DB.dbo.xrf_curr_cds xt
				ON ad.curr_cd = xt.curr_cd
					AND CAST(COALESCE(ad.reg_dt, DATEADD(MONTH, DATEDIFF(MONTH, 0, ad.create_dt), 0)) AS DATE) = xt.xch_rt_dt
			WHERE ad.status_flg = 'P'
				AND ad.curr_cd != '001'
			GROUP BY TRIM(CAST(ad.trty_no AS CHAR(5))) + TRIM(CAST(ad.und_yr AS CHAR(4))) COLLATE DATABASE_DEFAULT
				,ad.assumed_ceded_flg COLLATE DATABASE_DEFAULT
				,TRIM(ad.curr_cd) COLLATE DATABASE_DEFAULT
				,CAST(COALESCE(reg_dt, DATEADD(MONTH, DATEDIFF(MONTH, 0, ad.create_dt), 0)) AS DATE)
			HAVING SUM(COALESCE(ab.prem_wr, 0)) != 0
			) x
		

		-- Loading logic
		ALTER TABLE #TIRSUWBlendedRate ADD DataHash BINARY(20) NULL

		UPDATE s
		SET DataHash = HASHBYTES('SHA1', CONCAT(s.ToRegDate
			, '|', s.BlendedRate))
		FROM #TIRSUWBlendedRate s

		DROP TABLE IF EXISTS #LoadOperation

		CREATE TABLE #LoadOperation
		(CONTRACT_NBR VARCHAR(9) COLLATE DATABASE_DEFAULT NOT NULL
		,ASSUMED_CEDED_FLG CHAR(1) COLLATE DATABASE_DEFAULT NOT NULL
		,TIRS_ORIG_CURR_CD VARCHAR(3) COLLATE DATABASE_DEFAULT NOT NULL
		,FromRegDate DATE NOT NULL
		,Operation CHAR(1) NOT NULL
		,UNIQUE (CONTRACT_NBR, ASSUMED_CEDED_FLG, TIRS_ORIG_CURR_CD, FromRegDate)
		)

		INSERT INTO #LoadOperation
			(CONTRACT_NBR
			,ASSUMED_CEDED_FLG
			,TIRS_ORIG_CURR_CD
			,FromRegDate
			,Operation
			)
		SELECT CONTRACT_NBR = COALESCE(t.CONTRACT_NBR COLLATE DATABASE_DEFAULT, s.CONTRACT_NBR COLLATE DATABASE_DEFAULT)
			,ASSUMED_CEDED_FLG = COALESCE(t.ASSUMED_CEDED_FLG COLLATE DATABASE_DEFAULT, s.ASSUMED_CEDED_FLG COLLATE DATABASE_DEFAULT)
			,TIRS_ORIG_CURR_CD = COALESCE(t.TIRS_ORIG_CURR_CD COLLATE DATABASE_DEFAULT, s.TIRS_ORIG_CURR_CD COLLATE DATABASE_DEFAULT)
			,FromRegDate = COALESCE(t.FromRegDate, s.FromRegDate)
			,Operation = CASE WHEN t.TIRSUWBlendedRateID IS NULL THEN 'I' WHEN s.DataHash IS NULL THEN 'D' ELSE 'U' END
		FROM (
			SELECT t.*
			FROM assumed.TIRSUWBlendedRate t
			INNER JOIN (
				SELECT DISTINCT f.CONTRACT_NBR
				FROM #Filter f
				) f
				ON f.CONTRACT_NBR = t.CONTRACT_NBR COLLATE DATABASE_DEFAULT
			WHERE t.EndDate = '31 Dec 9999'
			) t
		FULL JOIN (
			SELECT s.*
			FROM #TIRSUWBlendedRate s
			INNER JOIN (
				SELECT DISTINCT f.CONTRACT_NBR
				FROM #Filter f
				) f
				ON f.CONTRACT_NBR = s.CONTRACT_NBR COLLATE DATABASE_DEFAULT
			) s
			ON s.CONTRACT_NBR = t.CONTRACT_NBR COLLATE DATABASE_DEFAULT
			AND s.ASSUMED_CEDED_FLG = t.ASSUMED_CEDED_FLG COLLATE DATABASE_DEFAULT
			AND s.TIRS_ORIG_CURR_CD = t.TIRS_ORIG_CURR_CD COLLATE DATABASE_DEFAULT
			AND s.FromRegDate = t.FromRegDate
		WHERE t.DataHash IS NULL
			OR s.DataHash IS NULL
			OR t.DataHash != s.DataHash

		BEGIN TRAN

		UPDATE t
		SET EndDate = p.ClosingEndDate
		FROM assumed.TIRSUWBlendedRate t
		INNER JOIN #LoadOperation lo
			ON lo.CONTRACT_NBR = t.CONTRACT_NBR
			AND lo.ASSUMED_CEDED_FLG = t.ASSUMED_CEDED_FLG
			AND lo.TIRS_ORIG_CURR_CD = t.TIRS_ORIG_CURR_CD
			AND lo.FromRegDate = t.FromRegDate
			AND lo.Operation IN ('U', 'D')
		CROSS JOIN #Parameters p
		WHERE t.EndDate = '31 Dec 9999'

		INSERT INTO assumed.TIRSUWBlendedRate
			(StartDate
			,CONTRACT_NBR
			,ASSUMED_CEDED_FLG
			,TIRS_ORIG_CURR_CD
			,FromRegDate
			,ToRegDate
			,BlendedRate
			,DataHash
			)
		SELECT StartDate = p.NewStartDate
			,s.CONTRACT_NBR
			,s.ASSUMED_CEDED_FLG
			,s.TIRS_ORIG_CURR_CD
			,s.FromRegDate
			,s.ToRegDate
			,s.BlendedRate
			,s.DataHash
		FROM #TIRSUWBlendedRate s
		INNER JOIN #LoadOperation lo
			ON lo.CONTRACT_NBR = s.CONTRACT_NBR COLLATE DATABASE_DEFAULT
			AND lo.ASSUMED_CEDED_FLG = s.ASSUMED_CEDED_FLG COLLATE DATABASE_DEFAULT
			AND lo.TIRS_ORIG_CURR_CD = s.TIRS_ORIG_CURR_CD COLLATE DATABASE_DEFAULT
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
