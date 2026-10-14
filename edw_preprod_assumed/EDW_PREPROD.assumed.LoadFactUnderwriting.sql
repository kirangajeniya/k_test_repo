-- Database: EDW_PREPROD
-- Schema: assumed
-- Procedure: LoadFactUnderwriting

CREATE   PROCEDURE [assumed].[LoadFactUnderwriting]
--DECLARE	
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
		DECLARE @v_RowCount				BIGINT		= 0
		DECLARE @v_RowCount_Fact		BIGINT		= 0

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

		/*
		DECLARE @FullLoad BIT = 0
		DECLARE @v_RowCount BIGINT = 0
		--*/

		--------------------------------------------------------------------------------
		--	##Timings_UW 
		--------------------------------------------------------------------------------
		DROP TABLE IF EXISTS ##Timings_UW

		SELECT EventTime = SYSDATETIME(),	EventMessage = CAST('Start' AS VARCHAR(100)), HandledRowCount=@v_RowCount
		  INTO ##Timings_UW

		--------------------------------------------------------------------------------		
		-- #AccountingPeriod 
		--------------------------------------------------------------------------------
		DROP TABLE IF EXISTS #AccountingPeriod
	
		SELECT
			 x.AccountingPeriodDate
			,OffsetDays = 1
			,OffsetAccountingStartDate	= DATEADD(DAY, 1, x.AccountingStartDate)
			,OffsetAccountingEndDate	= DATEADD(DAY, 1, x.AccountingEndDate)
			,x.AccountingStartDate
			,x.AccountingEndDate
			,CurrentPeriod = CONVERT(BIT, IIF(CAST(DATEADD(DAY, -1, GETDATE()) AS DATE) BETWEEN x.AccountingStartDate AND x.AccountingEndDate, 1, 0))
		INTO #AccountingPeriod
		FROM (SELECT AccountingPeriodDate = ap.accounting_period_date
					,AccountingStartDate= CONVERT(DATE, DATEADD(DAY, 1, LAG(ap.accounting_period_close_date) OVER (ORDER BY ap.accounting_period_key)) )
					,AccountingEndDate	= CONVERT(DATE, ap.accounting_period_close_date )
				FROM Insight.dbo.accounting_periods ap
			) x
		WHERE x.AccountingStartDate IS NOT NULL

		--------------------------------------------------------------------------------		
		--	#Parameters
		--------------------------------------------------------------------------------
		DROP TABLE IF EXISTS #Parameters

		SELECT
			 OffsetDays = 1
			,CurrentOffsetAccountingStartDate=(SELECT OffsetAccountingStartDate FROM #AccountingPeriod WHERE CurrentPeriod = 1)
			,CurrentOffsetAccountingEndDate = (SELECT OffsetAccountingEndDate FROM #AccountingPeriod WHERE CurrentPeriod = 1)
			,CurrentAccountingPeriod		= (SELECT AccountingPeriodDate FROM #AccountingPeriod WHERE CurrentPeriod = 1)
			,CurrentAccountingStartDate		= (SELECT AccountingStartDate  FROM #AccountingPeriod WHERE CurrentPeriod = 1)
			,FactLastChanged				= (SELECT LastCreatedDate = MAX(CreatedDate) FROM assumed.FactUnderwriting)
			,UnderwritingTouchedSince		= DATEADD(DAY, -7,  COALESCE((SELECT LastCreatedDate = MAX(CreatedDate) FROM assumed.FactUnderwriting), '1 Jan 1900'))
			,CatCodeHistoryChangedSince		= DATEADD(DAY, -45, COALESCE((SELECT LastCreatedDate = MAX(CreatedDate) FROM assumed.FactUnderwriting), '1 Jan 1900'))
			,ProcessingDate					= SYSDATETIME()
			,FullLoad						= CONVERT(BIT, IIF(NOT EXISTS (SELECT 1 FROM assumed.FactUnderwriting), 1, @FullLoad))
			----
			,DimContractUncoded				= (SELECT DimContractID			FROM EDW_PREPROD.assumed.DimContract			WHERE Contract_NBR			= 'Uncoded' AND SYSDATETIME() BETWEEN StartDate AND EndDate)
			,DimContractNA					= (SELECT DimContractID			FROM EDW_PREPROD.assumed.DimContract			WHERE Contract_NBR			= 'N/A'	    AND SYSDATETIME() BETWEEN StartDate AND EndDate)

			,DimTransactionTypeUncoded		= (SELECT DimTransactionTypeID	FROM EDW_PREPROD.assumed.DimTransactionType		WHERE TransactionType		= 'Uncoded' AND SYSDATETIME() BETWEEN StartDate AND EndDate)
			,DimTransactionTypeNA			= (SELECT DimTransactionTypeID	FROM EDW_PREPROD.assumed.DimTransactionType		WHERE TransactionType		= 'N/A'		AND SYSDATETIME() BETWEEN StartDate AND EndDate)

			,DimExchangeRateUncoded			= (SELECT DimExchangeRateID		FROM EDW_PREPROD.assumed.DimExchangeRate		WHERE RateDescription		= 'Uncoded' AND SYSDATETIME() BETWEEN StartDate AND EndDate)
			,DimExchangeRateNA				= (SELECT DimExchangeRateID		FROM EDW_PREPROD.assumed.DimExchangeRate		WHERE RateDescription		= 'N/A'		AND SYSDATETIME() BETWEEN StartDate AND EndDate)

			,DimCurrencyUncoded				= (SELECT DimCurrencyID			FROM EDW_PREPROD.assumed.DimCurrency			WHERE TIRS_CURR_NAME		= 'Uncoded' AND SYSDATETIME() BETWEEN StartDate AND EndDate)
			,DimCurrencyNA					= (SELECT DimCurrencyID			FROM EDW_PREPROD.assumed.DimCurrency			WHERE TIRS_CURR_NAME		= 'N/A'		AND SYSDATETIME() BETWEEN StartDate AND EndDate)

			,DimDateUncoded					= (SELECT DimDateID				FROM EDW_PREPROD.assumed.DimDate				WHERE DateText				= 'Uncoded' AND SYSDATETIME() BETWEEN StartDate AND EndDate)
			,DimDateNA						= (SELECT DimDateID				FROM EDW_PREPROD.assumed.DimDate				WHERE DateText				= 'N/A'     AND SYSDATETIME() BETWEEN StartDate AND EndDate)

			,DimParticipantUncoded			= (SELECT DimParticipantID		FROM EDW_PREPROD.assumed.DimParticipant			WHERE Participant			= 'Uncoded' AND SYSDATETIME() BETWEEN StartDate AND EndDate)
			,DimParticipantNA				= (SELECT DimParticipantID		FROM EDW_PREPROD.assumed.DimParticipant			WHERE Participant			= 'N/A'		AND SYSDATETIME() BETWEEN StartDate AND EndDate)

			,DimDocumentUncoded				= (SELECT DimDocumentID			FROM EDW_PREPROD.assumed.DimDocument			WHERE doc_key				= 'Uncoded' AND SYSDATETIME() BETWEEN StartDate AND EndDate)
			,DimDocumentNA					= (SELECT DimDocumentID			FROM EDW_PREPROD.assumed.DimDocument			WHERE doc_key				= 'N/A'		AND SYSDATETIME() BETWEEN StartDate AND EndDate)

			,DimBillingUncoded				= (SELECT DimBillingID			FROM EDW_PREPROD.assumed.DimBilling				WHERE BILL_COMPANY_CD		= 'Uncoded' AND SYSDATETIME() BETWEEN StartDate AND EndDate)
			,DimBillingNA					= (SELECT DimBillingID			FROM EDW_PREPROD.assumed.DimBilling				WHERE BILL_COMPANY_CD		= 'N/A'	    AND SYSDATETIME() BETWEEN StartDate AND EndDate)

			,DimAccountingUncoded			= (SELECT DimAccountingID		FROM EDW_PREPROD.assumed.DimAccounting			WHERE ActuarialLob			= 'Uncoded' AND RPT_OFF_NAME = 'Uncoded' AND SYSDATETIME() BETWEEN StartDate AND EndDate)
			,DimAccountingPeriodUncoded		= (SELECT DimAccountingPeriodID	FROM EDW_PREPROD.assumed.DimAccountingPeriod	WHERE AccountingYearMonth	= 'Uncoded' AND SYSDATETIME() BETWEEN StartDate AND EndDate)
			,DimAdjustmentTypeUncoded		= (SELECT DimAdjustmentTypeID	FROM EDW_PREPROD.assumed.DimAdjustmentType		WHERE AdjustmentType		= 'Uncoded' AND SYSDATETIME() BETWEEN StartDate AND EndDate)
			,DimLineOfBusinessUncoded		= (SELECT DimLineOfBusinessID	FROM EDW_PREPROD.assumed.DimLineOfBusiness		WHERE LineOfBusinessName	= 'Uncoded' AND SYSDATETIME() BETWEEN StartDate AND EndDate)
			,DimMeasureUncoded				= (SELECT DimMeasureID			FROM EDW_PREPROD.assumed.DimMeasure				WHERE MeasureCode			= 'Uncoded' AND SYSDATETIME() BETWEEN StartDate AND EndDate)

			,Current_DimAccountingPeriodID	= (SELECT dap.DimAccountingPeriodID
												 FROM EDW_PREPROD.assumed.DimAccountingPeriod dap
												WHERE EXISTS (SELECT * 
															    FROM #AccountingPeriod ap 
															   WHERE ap.AccountingPeriodDate = dap.AccountingPeriodDate
																 AND ap.CurrentPeriod = 1 )
												  AND SYSDATETIME() BETWEEN dap.StartDate AND dap.EndDate			)
			,ProcessName = COALESCE(OBJECT_SCHEMA_NAME(@@PROCID) + '.' + OBJECT_NAME(@@PROCID), 'assumed.LoadFactUnderwriting')
		INTO #Parameters;

		SET @v_RowCount = ROWCOUNT_BIG();
		INSERT INTO ##Timings_UW SELECT SYSDATETIME(), 'Created #Parameters', @v_RowCount;

		-- Handle situations where the processing isn't run on the first day of a new accounting period (covering the last day of source data for the previous accounting period), but then is run the next
		-- day.  This situation includes 2 days of source data, one of which should be processed into the previous month and one day that should be processed into the current month.  In this case only
		-- use the reg_date received from source to indicate the accounting period it should be placed in.  In those situations, one row will be created in the following table that can be used to override
		-- the Actual_DimAccountingPeriodID in the final inserts of this stored procedure.
		DROP TABLE IF EXISTS #ActualAccountingPeriodOverride

		SELECT
			 Intended_DimAccountingPeriodID = dap.DimAccountingPeriodID
			,Actual_DimAccountingPeriodID	= dap.DimAccountingPeriodID
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
		INNER JOIN assumed.DimAccountingPeriod dap
			ON dap.EndDate = '31 Dec 9999'
			AND dap.AccountingPeriodDate = y.AccountingPeriodDate
		WHERE y.MostRecent = 2

		INSERT INTO ##Timings_UW SELECT SYSDATETIME(), 'Created #ActualAccountingPeriodOverride', ROWCOUNT_BIG()

		--------------------------------------------------------------------------------		
		-- #LGC
		--------------------------------------------------------------------------------
		DROP TABLE IF EXISTS #LGC

		SELECT * 
		  INTO #LGC 
		  FROM EDW_PREPROD.dbo.LOOKUP_GENIUS_CURRENCYRATES

		CREATE CLUSTERED INDEX PIndex ON #LGC (JoinMonth);
		--------------------------------------------------------------------------------		
		-- #ContractFilter
		-- Create the contract filter, only those contracts that have changed for non-full loads and all contracts for full loads
		--------------------------------------------------------------------------------
		DROP TABLE IF EXISTS #CededParticipantChange

		SELECT DISTINCT bcb.DimContractID
		INTO #CededParticipantChange
		FROM assumed.BridgeContractBroker bcb
		CROSS JOIN #Parameters prm
		WHERE bcb.AssumedCeded = 'C'
			AND (bcb.EndDate BETWEEN prm.UnderwritingTouchedSince AND prm.ProcessingDate OR bcb.StartDate > prm.UnderwritingTouchedSince)
			AND prm.FullLoad = 0

		DROP TABLE IF EXISTS #AssumedCededLink

		SELECT DISTINCT ad.trty_key
			,ad.ceded_trty_key
		INTO #AssumedCededLink
		FROM SRC_TIRS_DB.dbo.acct_doc ad
		WHERE ceded_trty_key != -999
		OPTION (MAXDOP 1)

		DROP TABLE IF EXISTS #ContractFilter

		SELECT DISTINCT
			 trty_no		= CONVERT(INT, trty_no)
			,und_yr			= CONVERT(VARCHAR(4),und_yr)
			,Contract_NBR	= CONVERT(VARCHAR(20),Contract_NBR)
		INTO #ContractFilter
		FROM (
 			--------------------------------------------------------------------------------------------------------
 			-- Non-Full Load - Changed happened in the assumed.TIRS_UW_Staging table
 			--------------------------------------------------------------------------------------------------------
 			SELECT DISTINCT 
				 trty_no		= s.TREATY_NBR			COLLATE DATABASE_DEFAULT
 				,und_yr			= s.UNDERWRITING_YEAR	COLLATE DATABASE_DEFAULT
 				,CONTRACT_NBR	= s.CONTRACT_NBR		COLLATE DATABASE_DEFAULT
 			 FROM EDW_Staging.assumed.TIRS_UW_Staging	s
 			INNER JOIN #Parameters						prm ON prm.FullLoad = 0
 			WHERE s.StartDate > prm.FactLastChanged
 			   OR s.EndDate BETWEEN prm.FactLastChanged AND prm.ProcessingDate
 			UNION
			--------------------------------------------------------------------------------------------------------
			-- Non-Full Load - identify changed TIRS account byline or associated acct_doc records (with status 'P')
			--------------------------------------------------------------------------------------------------------
			SELECT DISTINCT
				 trty_no		= ad.trty_no
				,und_yr			= ad.und_yr
				,Contract_NBR	= CONCAT(CAST(ad.trty_no AS CHAR(5)), CAST(TRIM(ad.und_yr) AS CHAR(4)))
			FROM SRC_TIRS_DB.dbo.acct_byline	AS ab
			CROSS JOIN #Parameters				AS prm
			INNER JOIN SRC_TIRS_DB.dbo.acct_doc	AS ad	ON ad.doc_key = ab.doc_key
			WHERE prm.FullLoad = 0
			  AND ad.status_flg = 'P'
			  AND (ab.touch_dt > prm.UnderwritingTouchedSince
				OR ad.touch_dt > prm.UnderwritingTouchedSince
				OR ad.create_dt > prm.UnderwritingTouchedSince
				OR ad.reg_dt > prm.UnderwritingTouchedSince
				)
			UNION
			--------------------------------------------------------------------------------------------------------
			-- Non-Full Load - identify changed dbo.T_CODE_HISTORY entries within the threshold with a TIRS acct_doc record with status 'P'
			--------------------------------------------------------------------------------------------------------
			SELECT DISTINCT
				 trty_no		= ad.trty_no
				,und_yr			= ad.und_yr
				,Contract_NBR	= CONCAT(CAST(ad.trty_no AS CHAR(5)), CAST(TRIM(ad.und_yr) AS CHAR(4)))
			FROM SRC_TIRS_DB.dbo.acct_doc	AS ad
			CROSS JOIN #Parameters			AS prm
			INNER JOIN EDW_PREPROD.dbo.T_CODE_HISTORY	AS tch	ON tch.CONTRACT_NBR = CONCAT(CAST(ad.trty_no AS CHAR(5)), CAST(TRIM(ad.und_yr) AS CHAR(4))) COLLATE DATABASE_DEFAULT
			WHERE prm.FullLoad = 0
			  AND ad.status_flg = 'P'
			  AND tch.START_DATE > prm.CatCodeHistoryChangedSince
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
			--------------------------------------------------------------------------------------------------------
			-- always include contracts with topsides as there is no way to detect a change the in topside table
			--------------------------------------------------------------------------------------------------------
			SELECT DISTINCT
				 trty_no		= TRY_CAST(rtct.TREATY_NBR AS INT)
				,und_yr			= rtct.UNDERWRITING_YEAR COLLATE DATABASE_DEFAULT
				,Contract_NBR	= rtct.CONTRACT_NBR COLLATE DATABASE_DEFAULT
			FROM EDW_PREPROD.dbo.RS_TIRS_UNDERWRITING_TOPSIDE rtct
			UNION
			--------------------------------------------------------------------------------------------------------
			-- always include contracts from OPENBOX
			--------------------------------------------------------------------------------------------------------
			SELECT DISTINCT
				 trty_no		= CAST(NULL AS INT)
				,und_yr			= CAST(NULL AS VARCHAR(4))
				,Contract_NBR	= m.CONTRACT_NBR
			 FROM EDW_PREPROD.dbo.MAP_CONTRACT_EDW	AS m
			WHERE plcy_SRC = 'OPENBOX'
			UNION
			--------------------------------------------------------------------------------------------------------
			-- Full Load - TIRS contracts with an acct_doc record with a status 'P'
			--------------------------------------------------------------------------------------------------------
			SELECT DISTINCT
				 trty_no		= TRY_CAST(LEFT(dc.CONTRACT_NBR, 5) AS INT)
				,und_yr			= COALESCE(dc.UNDERWRITING_YEAR, CASE WHEN dc.PLCY_SRC = 'TIRS' THEN RIGHT(dc.CONTRACT_NBR, 4) END) COLLATE DATABASE_DEFAULT
				,CONTRACT_NBR	= dc.CONTRACT_NBR COLLATE DATABASE_DEFAULT
			FROM assumed.DimContract	dc
		   INNER JOIN #Parameters		prm	ON prm.FullLoad = 1
		   WHERE LEN(COALESCE(dc.UNDERWRITING_YEAR, '')) <= 4
			 AND dc.EndDate = '9999-12-31'
			 AND dc.CONTRACT_NBR NOT IN ('N/A','Uncoded')
		) AS u

		SET @v_RowCount = ROWCOUNT_BIG();

		-- remove any duplicate Contract_NBRs to ensure that Contract_NBR is unique
		DELETE x
		FROM (
			SELECT Instance = ROW_NUMBER() OVER (PARTITION BY Contract_NBR ORDER BY trty_no DESC, und_yr DESC)
			FROM #ContractFilter
			) x
		WHERE x.Instance > 1

		SET @v_RowCount -= ROWCOUNT_BIG();
		INSERT INTO ##Timings_UW SELECT SYSDATETIME(), 'Created #ContractFilter', @v_RowCount;
		--------------------------------------------------------------------------------		
		-- #TCodeUsed
		--------------------------------------------------------------------------------
		DROP TABLE IF EXISTS #TCodeUsed

		SELECT
			 START_DATE = x.START_DATE
			,END_DATE	= x.END_DATE
			,ContainsAccountingPeriod = CAST(CASE WHEN EXISTS (SELECT TOP 1 Column1 = 1
																 FROM #AccountingPeriod ap
																WHERE ap.OffsetAccountingEndDate > x.START_DATE
																  AND ap.OffsetAccountingEndDate < x.END_DATE )
												  THEN 1 ELSE 0 END AS BIT)
		INTO #TCodeUsed
		FROM (
			SELECT DISTINCT
				 START_DATE = START_DATE
				,END_DATE	= END_DATE
			FROM EDW_PREPROD.dbo.T_Code_History tch
			) x

		SET @v_RowCount = ROWCOUNT_BIG();
		INSERT INTO ##Timings_UW SELECT SYSDATETIME(), 'Created #TCodeUsed', @v_RowCount;
		--------------------------------------------------------------------------------		
		-- #TCodeRevisionExASLOB
		--------------------------------------------------------------------------------
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
					,PrevSame = CASE WHEN x.UniqueCombination = LAG(x.UniqueCombination)  OVER (PARTITION BY x.GroupingID ORDER BY x.GroupSequence) THEN 1 ELSE 0 END
					,NextSame = CASE WHEN x.UniqueCombination = LEAD(x.UniqueCombination) OVER (PARTITION BY x.GroupingID ORDER BY x.GroupSequence) THEN 1 ELSE 0 END
				FROM (
					-- set up fields to simplify comparisons
					SELECT ID = tch.ID
						,START_DATE			= tch.START_DATE
						,GroupingID			= DENSE_RANK() OVER (ORDER BY tch.Contract_NBR, tch.lob_name)
						,GroupSequence		= ROW_NUMBER() OVER (PARTITION BY tch.Contract_NBR, tch.lob_name ORDER BY tch.START_DATE)
						,UniqueCombination	= DENSE_RANK() OVER (PARTITION BY tch.Contract_NBR ,tch.lob_name
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
					 FROM EDW_PREPROD.dbo.T_Code_History	tch
					INNER JOIN #TCodeUsed					tcu	ON  tcu.START_DATE = tch.START_DATE
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

		SET @v_RowCount = ROWCOUNT_BIG();
		INSERT INTO ##Timings_UW SELECT SYSDATETIME(), 'Created #TCodeRevisionExASLOB', @v_RowCount;
		--------------------------------------------------------------------------------		
		-- #DimAccountingPairing
		--------------------------------------------------------------------------------
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
				 FROM assumed.DimAccounting da
				WHERE da.EndDate = '9999-12-31'
				) x
			GROUP BY x.UniqueCombination
			) y
		CROSS APPLY (  VALUES(y.Intended_DimAccountingID, y.DimAccountingID)
							,(y.DimAccountingID, y.DimAccountingID)
					) z (Intended_DimAccountingID, DimAccountingID)

		SET @v_RowCount = ROWCOUNT_BIG();
		INSERT INTO ##Timings_UW SELECT SYSDATETIME(), 'Created #DimAccountingPairing', @v_RowCount;
		--------------------------------------------------------------------------------	
		-- #UnderwritingLoadWide
		--------------------------------------------------------------------------------	
		DROP TABLE IF EXISTS #UnderwritingLoadWide

		CREATE TABLE #UnderwritingLoadWide
		(
			[UnderwritingLoadWideID]		INT IDENTITY NOT NULL,
			[TREATY_NBR]					VARCHAR(5)		COLLATE DATABASE_DEFAULT NULL,
			[UNDERWRITING_YEAR]				VARCHAR(4)		COLLATE DATABASE_DEFAULT NOT NULL,
			[CONTRACT_NBR]					VARCHAR(25)		COLLATE DATABASE_DEFAULT NOT NULL,
			[CEDED_CONTRACT_NBR]			VARCHAR(25)		COLLATE DATABASE_DEFAULT NULL,
			[SourceSystemKey]				BIGINT NULL,
			[Source]						VARCHAR(20)		COLLATE DATABASE_DEFAULT NULL,
			SourceID AS CASE WHEN [Source] = 'TIRS' THEN 4 WHEN [Source] = 'OPENBOX' THEN 1 ELSE NULL END PERSISTED,
			[TIRS_ORIG_CURR_CD]				VARCHAR(3)		COLLATE DATABASE_DEFAULT NULL,
			[TIRS_ORIG_CURR_NAME]			VARCHAR(50)		COLLATE DATABASE_DEFAULT NULL,
			[lob_name]						VARCHAR(255)	COLLATE DATABASE_DEFAULT NULL,
			[reg_date]						DATE NULL,
			[due_date]						DATE NULL,
			[acct_from_dt]					DATE NULL,
			[acct_to_dt]					DATE NULL,
			[doc_key]                       VARCHAR(50)		COLLATE DATABASE_DEFAULT NULL,
			[bill_company_cd]				VARCHAR(200)	COLLATE DATABASE_DEFAULT NULL,
			[aslob]							VARCHAR(20)		COLLATE DATABASE_DEFAULT NULL,
			[solvency_II_regulatory_key]	INT NULL,
			[AdjustmentType]				VARCHAR(200)	COLLATE DATABASE_DEFAULT NULL,
			[TIRS_UW_ASSM_CEDED_NAME]		VARCHAR(7)		COLLATE DATABASE_DEFAULT NULL,
			---------
			[SUMMABLE_WRTN_PREM_ALL_DOC_TYPES]						MONEY NULL,
			[SUMMABLE_WRTN_PREM_ALL_DOC_TYPES_USD]					MONEY NULL,
			[SUMMABLE_CEDED_WRTN_PREM_ALL_DOC_TYPES]				MONEY NULL,
			[SUMMABLE_CEDED_WRTN_PREM_ALL_DOC_TYPES_USD]			MONEY NULL,
			[SUMMABLE_WRTN_PREM_No_Claims_Rebate]					MONEY NULL,
			[SUMMABLE_WRTN_PREM_No_Claims_Rebate_USD]				MONEY NULL,
			[SUMMABLE_CEDED_WRTN_PREM_No_Claims_Rebate]				MONEY NULL,
			[SUMMABLE_CEDED_WRTN_PREM_No_Claims_Rebate_USD]			MONEY NULL,
			[SUMMABLE_WRTN_PREM_Reinstatement_Premium]				MONEY NULL,
			[SUMMABLE_WRTN_PREM_Reinstatement_Premium_USD]			MONEY NULL,
			[SUMMABLE_CEDED_WRTN_PREM_Reinstatement_Premium]		MONEY NULL,
			[SUMMABLE_CEDED_WRTN_PREM_Reinstatement_Premium_USD]	MONEY NULL,
			[SUMMABLE_Brokerage]							MONEY NULL,
			[SUMMABLE_Brokerage_USD]						MONEY NULL,
			[SUMMABLE_CEDED_Brokerage]						MONEY NULL,
			[SUMMABLE_CEDED_Brokerage_USD]					MONEY NULL,
			[SUMMABLE_Commission]							MONEY NULL,
			[SUMMABLE_Commission_USD]						MONEY NULL,
			[SUMMABLE_CEDED_Commission]						MONEY NULL,
			[SUMMABLE_CEDED_Commission_USD]					MONEY NULL,
			[SUMMABLE_tax_nonrefund]						MONEY NULL,
			[SUMMABLE_tax_nonrefund_USD]					MONEY NULL,
			[SUMMABLE_CEDED_tax_nonrefund]					MONEY NULL,
			[SUMMABLE_CEDED_tax_nonrefund_USD]				MONEY NULL,
			[SUMMABLE_tax_on_prem]							MONEY NULL,
			[SUMMABLE_tax_on_prem_USD]						MONEY NULL,
			[SUMMABLE_CEDED_tax_on_prem]					MONEY NULL,
			[SUMMABLE_CEDED_tax_on_prem_USD]				MONEY NULL,
			[SUMMABLE_tax_refund]							MONEY NULL,
			[SUMMABLE_tax_refund_USD]						MONEY NULL,
			[SUMMABLE_CEDED_tax_refund]						MONEY NULL,
			[SUMMABLE_CEDED_tax_refund_USD]					MONEY NULL,
			[SUMMABLE_Profit_Commission_Paid]				MONEY NULL,
			[SUMMABLE_Profit_Commission_Paid_USD]			MONEY NULL,
			[SUMMABLE_CEDED_Profit_Commission_Paid]			MONEY NULL,
			[SUMMABLE_CEDED_Profit_Commission_Paid_USD]		MONEY NULL,
			[SUMMABLE_Sliding_Scale_Commission]				MONEY NULL,
			[SUMMABLE_Sliding_Scale_Commission_USD]			MONEY NULL,
			[SUMMABLE_CEDED_Sliding_Scale_Commission]		MONEY NULL,
			[SUMMABLE_CEDED_Sliding_Scale_Commission_USD]	MONEY NULL,
			[SUMMABLE_Overrider_Commission]					MONEY NULL,
			[SUMMABLE_Overrider_Commission_USD]				MONEY NULL,
			[SUMMABLE_CEDED_Overrider_Commission]			MONEY NULL,
			[SUMMABLE_CEDED_Overrider_Commission_USD]       MONEY NULL,
			[SUMMABLE_Provisional_Commission]				MONEY NULL,
			[SUMMABLE_Provisional_Commission_USD]			MONEY NULL,
			[SUMMABLE_CEDED_Provisional_Commission]			MONEY NULL,
			[SUMMABLE_CEDED_Provisional_Commission_USD]		MONEY NULL,
			[SUMMABLE_Deferred_Commission]					MONEY NULL,
			[SUMMABLE_Deferred_Commission_USD]				MONEY NULL,
			[SUMMABLE_CEDED_Deferred_Commission]			MONEY NULL,
			[SUMMABLE_CEDED_Deferred_Commission_USD]		MONEY NULL,
			[SUMMABLE_int_funds_gross]						MONEY NULL,
			[SUMMABLE_int_funds_gross_USD]					MONEY NULL,
			[SUMMABLE_CEDED_int_funds_gross]				MONEY NULL,
			[SUMMABLE_CEDED_int_funds_gross_USD]			MONEY NULL,
			[SUMMABLE_int_funds_wth]						MONEY NULL,
			[SUMMABLE_int_funds_wth_USD]					MONEY NULL,
			[SUMMABLE_CEDED_int_funds_wth]					MONEY NULL,
			[SUMMABLE_CEDED_int_funds_wth_USD]				MONEY NULL,
			[SUMMABLE_fire_prevent_fund]					MONEY NULL,
			[SUMMABLE_fire_prevent_fund_USD]				MONEY NULL,
			[SUMMABLE_CEDED_fire_prevent_fund]				MONEY NULL,
			[SUMMABLE_CEDED_fire_prevent_fund_USD]			MONEY NULL,
			[SUMMABLE_xch_diff]								MONEY NULL,
			[SUMMABLE_xch_diff_USD]							MONEY NULL,
			[SUMMABLE_CEDED_xch_diff]						MONEY NULL,
			[SUMMABLE_CEDED_xch_diff_USD]					MONEY NULL,
			[SUMMABLE_NO_CLM_RBT]							MONEY NULL,
			[SUMMABLE_NO_CLM_RBT_USD]						MONEY NULL,
			[SUMMABLE_CEDED_NO_CLM_RBT]						MONEY NULL,
			[SUMMABLE_CEDED_NO_CLM_RBT_USD]					MONEY NULL,
			[SUMMABLE_funds_withheld_premium]				MONEY NULL,
			[SUMMABLE_funds_withheld_premium_USD]			MONEY NULL,
			[SUMMABLE_CEDED_funds_withheld_premium]			MONEY NULL,
			[SUMMABLE_CEDED_funds_withheld_premium_USD]		MONEY NULL,
			[SUMMABLE_funds_released_premium]				MONEY NULL,
			[SUMMABLE_funds_released_premium_USD]			MONEY NULL,
			[SUMMABLE_CEDED_funds_released_premium]			MONEY NULL,
			[SUMMABLE_CEDED_funds_released_premium_USD]		MONEY NULL,
			[SUMMABLE_funds_withheld_losses]				MONEY NULL,
			[SUMMABLE_funds_withheld_losses_USD]			MONEY NULL,
			[SUMMABLE_CEDED_funds_withheld_losses]			MONEY NULL,
			[SUMMABLE_CEDED_funds_withheld_losses_USD]		MONEY NULL,
			[SUMMABLE_deferred_withheld]					MONEY NULL,
			[SUMMABLE_deferred_withheld_USD]				MONEY NULL,
			[SUMMABLE_CEDED_deferred_withheld]				MONEY NULL,
			[SUMMABLE_CEDED_deferred_withheld_USD]			MONEY NULL,
			[SUMMABLE_deferred_released]					MONEY NULL,
			[SUMMABLE_deferred_released_USD]				MONEY NULL,
			[SUMMABLE_CEDED_deferred_released]				MONEY NULL,
			[SUMMABLE_CEDED_deferred_released_USD]			MONEY NULL,
			[SUMMABLE_UEPR]									MONEY NULL,
			[SUMMABLE_UEPR_USD]								MONEY NULL,
			[SUMMABLE_CEDED_UEPR]							MONEY NULL,
			[SUMMABLE_CEDED_UEPR_USD]						MONEY NULL,
			[SUMMABLE_UEPR_RPT_CURR1]						MONEY NULL,
			[SUMMABLE_UEPR_RPT_CURR2]						MONEY NULL,
			[SUMMABLE_DAC]									MONEY NULL,
			[SUMMABLE_DAC_USD]								MONEY NULL,
			[SUMMABLE_CEDED_DAC]							MONEY NULL,
			[SUMMABLE_CEDED_DAC_USD]						MONEY NULL,
			[SUMMABLE_DAC_RPT_CURR1]						MONEY NULL,
			[SUMMABLE_DAC_RPT_CURR2]						MONEY NULL,
			[SUMMABLE_FUNDS_RELEASED_LOSSES] 	            MONEY NULL,
			[SUMMABLE_FUNDS_RELEASED_LOSSES_USD] 	        MONEY NULL,
			---------
			[T7_CODE]					VARCHAR(100) COLLATE DATABASE_DEFAULT NULL,
			[T8_CODE]					VARCHAR(20) COLLATE DATABASE_DEFAULT NULL,
			[T9_CODE]					CHAR(1) COLLATE DATABASE_DEFAULT NULL,
			[MBU]						CHAR(3) COLLATE DATABASE_DEFAULT NULL,
			[L01]						CHAR(3) COLLATE DATABASE_DEFAULT NULL,
			[L02]						CHAR(3) COLLATE DATABASE_DEFAULT NULL,
			[L03]						VARCHAR(7) COLLATE DATABASE_DEFAULT NULL,
			[L04]						VARCHAR(1) COLLATE DATABASE_DEFAULT NULL,
			[L05]						VARCHAR(10) COLLATE DATABASE_DEFAULT NULL,
			[L06]						CHAR(4) COLLATE DATABASE_DEFAULT NULL,
			[L07]						VARCHAR(15) COLLATE DATABASE_DEFAULT NULL,
			[L08]						VARCHAR(10) COLLATE DATABASE_DEFAULT NULL,
			[L09]						VARCHAR(10) COLLATE DATABASE_DEFAULT NULL,
			[L10]						VARCHAR(10) COLLATE DATABASE_DEFAULT NULL,
			[GD1]						VARCHAR(10) COLLATE DATABASE_DEFAULT NULL,
			[RPTCURR1]					DECIMAL(38,10) NULL,
			[RPTCURR1_CD]				CHAR(3) COLLATE DATABASE_DEFAULT NULL,
			[RPTCURR2]					DECIMAL(38,10) NULL,
			[RPTCURR2_CD]				CHAR(3) COLLATE DATABASE_DEFAULT NULL,
			[InsurerCode]				VARCHAR(20) COLLATE DATABASE_DEFAULT NULL,
			[Financial_Lob]				VARCHAR(10) COLLATE DATABASE_DEFAULT NULL,
			[RPT_OFC_NM]				VARCHAR(255) COLLATE DATABASE_DEFAULT NULL,
			[RPT_OFF_NAME]				VARCHAR(255) COLLATE DATABASE_DEFAULT NULL,
			[ICP_CEDED_FLG]				CHAR(1) COLLATE DATABASE_DEFAULT NULL,
			[actuariallob]				VARCHAR(100) COLLATE DATABASE_DEFAULT NULL,
			[CLMS_PROCSS_CLM_DEPT]		CHAR(1) COLLATE DATABASE_DEFAULT NULL,
			[ID]						INT NULL,
			[Unmatched_Fields]			INT NULL,
			[topside_reg_date]			DATETIME NULL,
			[Blended_Rate]				DECIMAL(18,10) NULL,
			[MATCH_SOURCE_FLAG]			INT NULL,
			[TransactionTypeCode]		VARCHAR(10) COLLATE DATABASE_DEFAULT NULL,
			[TransactionTypeCategory]	VARCHAR(50) COLLATE DATABASE_DEFAULT NULL,
			----
			[DimContractID]								INT NULL,
			[Ceded_DimContractID]						INT NULL,
			[Intended_DimAccountingPeriodID]			INT NULL,
			[Actual_DimAccountingPeriodID]				INT NULL,
			[Intended_DimAccountingID]					INT NULL,
			[DimAccountingID]							INT NULL,
			[DimTransactionTypeID]						INT NULL,
			[DimAdjustmentTypeID]						INT NULL,
			[DimLineOfBusinessID]						INT NULL,		
			[DimDueDateID]								INT NULL,
			[DimFromDateID]                             INT NULL,
			[DimToDateID]                               INT NULL,
			[Orig_DimCurrencyID]						INT NULL,
			[OrigRpt1_DimExchangeRateID]				INT NULL,
			[OrigRpt2_DimExchangeRateID]				INT NULL,
			[DimDocumentID]								INT NULL,
			[DimBillingID]								INT NULL
		);
		--------------------------------------------------------------------------------	
		-- #UnderwritingLoadWide - INSERT TIRS data
		--------------------------------------------------------------------------------	
		INSERT INTO #UnderwritingLoadWide
		(
		   [TREATY_NBR]
		  ,[UNDERWRITING_YEAR]
		  ,[CONTRACT_NBR]
		  ,[CEDED_CONTRACT_NBR]
		  ,[SourceSystemKey]
		  ,[Source]
		  ,[TIRS_ORIG_CURR_CD]
		  ,[TIRS_ORIG_CURR_NAME]
		  ,[lob_name]
		  ,[reg_date]
		  ,[due_date]
		  ,[acct_from_dt]	
		  ,[acct_to_dt]
		  ,[doc_key] 
		  ,[bill_company_cd]
		  ,[aslob]
		  ,[solvency_II_regulatory_key]
		  ,[AdjustmentType]
		  ,[TIRS_UW_ASSM_CEDED_NAME]
		  ,[SUMMABLE_WRTN_PREM_ALL_DOC_TYPES]
		  ,[SUMMABLE_WRTN_PREM_ALL_DOC_TYPES_USD]
		  ,[SUMMABLE_CEDED_WRTN_PREM_ALL_DOC_TYPES]
		  ,[SUMMABLE_CEDED_WRTN_PREM_ALL_DOC_TYPES_USD]
		  ,[SUMMABLE_WRTN_PREM_No_Claims_Rebate]
		  ,[SUMMABLE_WRTN_PREM_No_Claims_Rebate_USD]
		  ,[SUMMABLE_CEDED_WRTN_PREM_No_Claims_Rebate]
		  ,[SUMMABLE_CEDED_WRTN_PREM_No_Claims_Rebate_USD]
		  ,[SUMMABLE_WRTN_PREM_Reinstatement_Premium]
		  ,[SUMMABLE_WRTN_PREM_Reinstatement_Premium_USD]
		  ,[SUMMABLE_CEDED_WRTN_PREM_Reinstatement_Premium]
		  ,[SUMMABLE_CEDED_WRTN_PREM_Reinstatement_Premium_USD]
		  ,[SUMMABLE_Brokerage]
		  ,[SUMMABLE_Brokerage_USD]
		  ,[SUMMABLE_CEDED_Brokerage]
		  ,[SUMMABLE_CEDED_Brokerage_USD]
		  ,[SUMMABLE_Commission]
		  ,[SUMMABLE_Commission_USD]
		  ,[SUMMABLE_CEDED_Commission]
		  ,[SUMMABLE_CEDED_Commission_USD]
		  ,[SUMMABLE_tax_nonrefund]
		  ,[SUMMABLE_tax_nonrefund_USD]
		  ,[SUMMABLE_CEDED_tax_nonrefund]
		  ,[SUMMABLE_CEDED_tax_nonrefund_USD]
		  ,[SUMMABLE_tax_on_prem]
		  ,[SUMMABLE_tax_on_prem_USD]
		  ,[SUMMABLE_CEDED_tax_on_prem]
		  ,[SUMMABLE_CEDED_tax_on_prem_USD]
		  ,[SUMMABLE_tax_refund]
		  ,[SUMMABLE_tax_refund_USD]
		  ,[SUMMABLE_CEDED_tax_refund]
		  ,[SUMMABLE_CEDED_tax_refund_USD]
		  ,[SUMMABLE_Profit_Commission_Paid]
		  ,[SUMMABLE_Profit_Commission_Paid_USD]
		  ,[SUMMABLE_CEDED_Profit_Commission_Paid]
		  ,[SUMMABLE_CEDED_Profit_Commission_Paid_USD]
		  ,[SUMMABLE_Sliding_Scale_Commission]
		  ,[SUMMABLE_Sliding_Scale_Commission_USD]
		  ,[SUMMABLE_CEDED_Sliding_Scale_Commission]
		  ,[SUMMABLE_CEDED_Sliding_Scale_Commission_USD]
		  ,[SUMMABLE_Overrider_Commission]
		  ,[SUMMABLE_Overrider_Commission_USD]
		  ,[SUMMABLE_CEDED_Overrider_Commission]
		  ,[SUMMABLE_CEDED_Overrider_Commission_USD]       
		  ,[SUMMABLE_Provisional_Commission]
		  ,[SUMMABLE_Provisional_Commission_USD]
		  ,[SUMMABLE_CEDED_Provisional_Commission]
		  ,[SUMMABLE_CEDED_Provisional_Commission_USD]
		  ,[SUMMABLE_Deferred_Commission]
		  ,[SUMMABLE_Deferred_Commission_USD]
		  ,[SUMMABLE_CEDED_Deferred_Commission]
		  ,[SUMMABLE_CEDED_Deferred_Commission_USD]
		  ,[SUMMABLE_int_funds_gross]
		  ,[SUMMABLE_int_funds_gross_USD]
		  ,[SUMMABLE_CEDED_int_funds_gross]
		  ,[SUMMABLE_CEDED_int_funds_gross_USD]
		  ,[SUMMABLE_int_funds_wth]
		  ,[SUMMABLE_int_funds_wth_USD]
		  ,[SUMMABLE_CEDED_int_funds_wth]
		  ,[SUMMABLE_CEDED_int_funds_wth_USD]
		  ,[SUMMABLE_fire_prevent_fund]
		  ,[SUMMABLE_fire_prevent_fund_USD]
		  ,[SUMMABLE_CEDED_fire_prevent_fund]
		  ,[SUMMABLE_CEDED_fire_prevent_fund_USD]
		  ,[SUMMABLE_xch_diff]
		  ,[SUMMABLE_xch_diff_USD]
		  ,[SUMMABLE_CEDED_xch_diff]
		  ,[SUMMABLE_CEDED_xch_diff_USD]
		  ,[SUMMABLE_NO_CLM_RBT]
		  ,[SUMMABLE_NO_CLM_RBT_USD]
		  ,[SUMMABLE_CEDED_NO_CLM_RBT]
		  ,[SUMMABLE_CEDED_NO_CLM_RBT_USD]
		  ,[SUMMABLE_funds_withheld_premium]
		  ,[SUMMABLE_funds_withheld_premium_USD]
		  ,[SUMMABLE_CEDED_funds_withheld_premium]
		  ,[SUMMABLE_CEDED_funds_withheld_premium_USD]
		  ,[SUMMABLE_funds_released_premium]
		  ,[SUMMABLE_funds_released_premium_USD]
		  ,[SUMMABLE_CEDED_funds_released_premium]
		  ,[SUMMABLE_CEDED_funds_released_premium_USD]
		  ,[SUMMABLE_funds_withheld_losses]
		  ,[SUMMABLE_funds_withheld_losses_USD]
		  ,[SUMMABLE_CEDED_funds_withheld_losses]
		  ,[SUMMABLE_CEDED_funds_withheld_losses_USD]
		  ,[SUMMABLE_deferred_withheld]
		  ,[SUMMABLE_deferred_withheld_USD]
		  ,[SUMMABLE_CEDED_deferred_withheld]
		  ,[SUMMABLE_CEDED_deferred_withheld_USD]
		  ,[SUMMABLE_deferred_released]
		  ,[SUMMABLE_deferred_released_USD]
		  ,[SUMMABLE_CEDED_deferred_released]
		  ,[SUMMABLE_CEDED_deferred_released_USD]
		  ,[SUMMABLE_UEPR]
		  ,[SUMMABLE_UEPR_USD]
		  ,[SUMMABLE_CEDED_UEPR]
		  ,[SUMMABLE_CEDED_UEPR_USD]
		  ,[SUMMABLE_UEPR_RPT_CURR1]
		  ,[SUMMABLE_UEPR_RPT_CURR2]
		  ,[SUMMABLE_DAC]
		  ,[SUMMABLE_DAC_USD]
		  ,[SUMMABLE_CEDED_DAC]
		  ,[SUMMABLE_CEDED_DAC_USD]
		  ,[SUMMABLE_DAC_RPT_CURR1]
		  ,[SUMMABLE_DAC_RPT_CURR2]
		  ,[SUMMABLE_FUNDS_RELEASED_LOSSES] 	 
          ,[SUMMABLE_FUNDS_RELEASED_LOSSES_USD]
		  ,[T7_CODE]
		  ,[T8_CODE]
		  ,[T9_CODE]
		  ,[MBU]
		  ,[L01]
		  ,[L02]
		  ,[L03]
		  ,[L04]
		  ,[L05]
		  ,[L06]
		  ,[L07]
		  ,[L08]
		  ,[L09]
		  ,[L10]
		  ,[GD1]
		  ,[RPTCURR1]
		  ,[RPTCURR1_CD]
		  ,[RPTCURR2]
		  ,[RPTCURR2_CD]
		  ,[InsurerCode]
		  ,[Financial_Lob]
		  ,[RPT_OFC_NM]
		  ,[RPT_OFF_NAME]
		  ,[ICP_CEDED_FLG]
		  ,[actuariallob]
		  ,[CLMS_PROCSS_CLM_DEPT]
		  ,[ID]
		  ,[Unmatched_Fields]
		  ,[topside_reg_date]
		  ,[Blended_Rate]
		  ,[MATCH_SOURCE_FLAG]
		  ,[TransactionTypeCode]
		  ,[TransactionTypeCategory]
		)
		SELECT
			 [TREATY_NBR]				= stg.TREATY_NBR
			,[UNDERWRITING_YEAR]		= stg.UNDERWRITING_YEAR
			,[CONTRACT_NBR]				= stg.CONTRACT_NBR
			,[CEDED_CONTRACT_NBR]		= stg.CEDED_CONTRACT_NBR
			,[SourceSystemKey]			= stg.byline_key
			,[Source]					= 'TIRS'
			,[TIRS_ORIG_CURR_CD]		= stg.TIRS_ORIG_CURR_CD
			,[TIRS_ORIG_CURR_NAME]		= TRIM(cn.curr_nm)	COLLATE DATABASE_DEFAULT
			,[lob_name]					= h.lob_name
			,[reg_date]					= stg.reg_date
			,[due_date]					= stg.due_date
			,[acct_from_dt]		        = stg.acct_from_dt
		    ,[acct_to_dt]			    = stg.acct_to_dt  
		    ,[doc_key] 					= stg.doc_key
			,[bill_company_cd]			= stg.bill_company_cd
			,[aslob]					= stg.aslob
			,[solvency_II_regulatory_key]= solII.solvency_II_regulatory_key
			,[AdjustmentType]			= CONVERT(CHAR(3),'N/A') COLLATE DATABASE_DEFAULT
			,[TIRS_UW_ASSM_CEDED_NAME]	= CASE stg.assumed_ceded_flg 
											WHEN 'C' THEN 'Ceded'
											WHEN 'A' THEN 'Assumed' END
			----------
			,[SUMMABLE_WRTN_PREM_ALL_DOC_TYPES]					= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'A', ISNULL(stg.SUMMABLE_WRTN_PREM_ALL_DOC_TYPES,0) ,0))
			,[SUMMABLE_WRTN_PREM_ALL_DOC_TYPES_USD]				= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'A', ISNULL(stg.SUMMABLE_WRTN_PREM_ALL_DOC_TYPES_USD,0) ,0))
			,[SUMMABLE_CEDED_WRTN_PREM_ALL_DOC_TYPES]			= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'C', ISNULL(stg.SUMMABLE_WRTN_PREM_ALL_DOC_TYPES,0) ,0))
			,[SUMMABLE_CEDED_WRTN_PREM_ALL_DOC_TYPES_USD]		= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'C', ISNULL(stg.SUMMABLE_WRTN_PREM_ALL_DOC_TYPES_USD,0) ,0))

			,[SUMMABLE_WRTN_PREM_No_Claims_Rebate]				= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'A', ISNULL(stg.SUMMABLE_WRTN_PREM_No_Claims_Rebate,0) ,0))
			,[SUMMABLE_WRTN_PREM_No_Claims_Rebate_USD]			= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'A', ISNULL(stg.SUMMABLE_WRTN_PREM_No_Claims_Rebate_USD,0) ,0))
			,[SUMMABLE_CEDED_WRTN_PREM_No_Claims_Rebate]		= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'C', ISNULL(stg.SUMMABLE_WRTN_PREM_No_Claims_Rebate,0) ,0))
			,[SUMMABLE_CEDED_WRTN_PREM_No_Claims_Rebate_USD]	= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'C', ISNULL(stg.SUMMABLE_WRTN_PREM_No_Claims_Rebate_USD,0) ,0))

			,[SUMMABLE_WRTN_PREM_Reinstatement_Premium]			= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'A', ISNULL(stg.SUMMABLE_WRTN_PREM_Reinstatement_Premium,0) ,0))
			,[SUMMABLE_WRTN_PREM_Reinstatement_Premium_USD]		= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'A', ISNULL(stg.SUMMABLE_WRTN_PREM_Reinstatement_Premium_USD,0) ,0))
			,[SUMMABLE_CEDED_WRTN_PREM_Reinstatement_Premium]	= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'C', ISNULL(stg.SUMMABLE_WRTN_PREM_Reinstatement_Premium,0) ,0))
			,[SUMMABLE_CEDED_WRTN_PREM_Reinstatement_Premium_USD]=CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'C', ISNULL(stg.SUMMABLE_WRTN_PREM_Reinstatement_Premium_USD,0) ,0))

			,[SUMMABLE_Brokerage]								= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'A', ISNULL(stg.SUMMABLE_Brokerage,0) ,0))
			,[SUMMABLE_Brokerage_USD]							= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'A', ISNULL(stg.SUMMABLE_Brokerage_USD,0) ,0))
			,[SUMMABLE_CEDED_Brokerage]							= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'C', ISNULL(stg.SUMMABLE_Brokerage,0) ,0))
			,[SUMMABLE_CEDED_Brokerage_USD]						= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'C', ISNULL(stg.SUMMABLE_Brokerage_USD,0) ,0))

			,[SUMMABLE_Commission]								= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'A', ISNULL(stg.SUMMABLE_Commission,0) ,0))
			,[SUMMABLE_Commission_USD]							= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'A', ISNULL(stg.SUMMABLE_Commission_USD,0) ,0))
			,[SUMMABLE_CEDED_Commission]						= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'C', ISNULL(stg.SUMMABLE_Commission,0) ,0))
			,[SUMMABLE_CEDED_Commission_USD]					= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'C', ISNULL(stg.SUMMABLE_Commission_USD,0) ,0))

			,[SUMMABLE_tax_nonrefund]							= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'A', ISNULL(stg.SUMMABLE_tax_nonrefund,0) ,0))
			,[SUMMABLE_tax_nonrefund_USD]						= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'A', ISNULL(stg.SUMMABLE_tax_nonrefund_USD,0) ,0))
			,[SUMMABLE_CEDED_tax_nonrefund]						= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'C', ISNULL(stg.SUMMABLE_tax_nonrefund,0) ,0))
			,[SUMMABLE_CEDED_tax_nonrefund_USD]					= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'C', ISNULL(stg.SUMMABLE_tax_nonrefund_USD,0) ,0))

			,[SUMMABLE_tax_on_prem]								= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'A', ISNULL(stg.SUMMABLE_tax_on_prem,0) ,0))
			,[SUMMABLE_tax_on_prem_USD]							= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'A', ISNULL(stg.SUMMABLE_tax_on_prem_USD,0) ,0))
			,[SUMMABLE_CEDED_tax_on_prem]						= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'C', ISNULL(stg.SUMMABLE_tax_on_prem,0) ,0))
			,[SUMMABLE_CEDED_tax_on_prem_USD]					= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'C', ISNULL(stg.SUMMABLE_tax_on_prem_USD,0) ,0))

			,[SUMMABLE_Tax_refund]								= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'A', ISNULL(stg.SUMMABLE_Tax_refund,0) ,0))
			,[SUMMABLE_Tax_refund_USD]							= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'A', ISNULL(stg.SUMMABLE_Tax_refund_USD,0) ,0))
			,[SUMMABLE_CEDED_Tax_refund]						= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'C', ISNULL(stg.SUMMABLE_Tax_refund,0) ,0))
			,[SUMMABLE_CEDED_Tax_refund_USD]					= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'C', ISNULL(stg.SUMMABLE_Tax_refund_USD,0) ,0))

			,[SUMMABLE_Profit_Commission_Paid]					= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'A', ISNULL(stg.SUMMABLE_Profit_Commission_Paid,0) ,0))
			,[SUMMABLE_Profit_Commission_Paid_USD]				= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'A', ISNULL(stg.SUMMABLE_Profit_Commission_Paid_USD,0) ,0))
			,[SUMMABLE_CEDED_Profit_Commission_Paid]			= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'C', ISNULL(stg.SUMMABLE_Profit_Commission_Paid,0) ,0))
			,[SUMMABLE_CEDED_Profit_Commission_Paid_USD]		= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'C', ISNULL(stg.SUMMABLE_Profit_Commission_Paid_USD,0) ,0))

			,[SUMMABLE_Sliding_Scale_Commission]				= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'A', ISNULL(stg.SUMMABLE_Sliding_Scale_Commission,0) ,0))
			,[SUMMABLE_Sliding_Scale_Commission_USD]			= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'A', ISNULL(stg.SUMMABLE_Sliding_Scale_Commission_USD,0) ,0))
			,[SUMMABLE_CEDED_Sliding_Scale_Commission]			= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'C', ISNULL(stg.SUMMABLE_Sliding_Scale_Commission,0) ,0))
			,[SUMMABLE_CEDED_Sliding_Scale_Commission_USD]		= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'C', ISNULL(stg.SUMMABLE_Sliding_Scale_Commission_USD,0) ,0))

			,[SUMMABLE_Overrider_Commission]					= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'A', ISNULL(stg.SUMMABLE_Overrider_Commission,0) ,0))
			,[SUMMABLE_Overrider_Commission_USD]				= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'A', ISNULL(stg.SUMMABLE_Overrider_Commission_USD,0) ,0))
			,[SUMMABLE_CEDED_Overrider_Commission]				= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'C', ISNULL(stg.SUMMABLE_Overrider_Commission,0) ,0))
			,[SUMMABLE_CEDED_Overrider_Commission_USD]			= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'C', ISNULL(stg.SUMMABLE_Overrider_Commission_USD,0) ,0))

			,[SUMMABLE_Provisional_Commission]					= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'A', ISNULL(stg.SUMMABLE_Provisional_Commission,0) ,0))
			,[SUMMABLE_Provisional_Commission_USD]				= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'A', ISNULL(stg.SUMMABLE_Provisional_Commission_USD,0) ,0))
			,[SUMMABLE_CEDED_Provisional_Commission]			= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'C', ISNULL(stg.SUMMABLE_Provisional_Commission,0) ,0))
			,[SUMMABLE_CEDED_Provisional_Commission_USD]		= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'C', ISNULL(stg.SUMMABLE_Provisional_Commission_USD,0) ,0))

			,[SUMMABLE_Deferred_Commission]						= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'A', ISNULL(stg.SUMMABLE_Deferred_Commission,0) ,0))
			,[SUMMABLE_Deferred_Commission_USD]					= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'A', ISNULL(stg.SUMMABLE_Deferred_Commission_USD,0) ,0))
			,[SUMMABLE_CEDED_Deferred_Commission]				= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'C', ISNULL(stg.SUMMABLE_Deferred_Commission,0) ,0))
			,[SUMMABLE_CEDED_Deferred_Commission_USD]			= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'C', ISNULL(stg.SUMMABLE_Deferred_Commission_USD,0) ,0))

			,[SUMMABLE_int_funds_gross]							= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'A', ISNULL(stg.SUMMABLE_int_funds_gross,0) ,0))
			,[SUMMABLE_int_funds_gross_USD]						= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'A', ISNULL(stg.SUMMABLE_int_funds_gross_USD,0) ,0))
			,[SUMMABLE_CEDED_int_funds_gross]					= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'C', ISNULL(stg.SUMMABLE_int_funds_gross,0) ,0))
			,[SUMMABLE_CEDED_int_funds_gross_USD]				= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'C', ISNULL(stg.SUMMABLE_int_funds_gross_USD,0) ,0))

			,[SUMMABLE_int_funds_wth]							= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'A', ISNULL(stg.SUMMABLE_int_funds_wth,0) ,0))
			,[SUMMABLE_int_funds_wth_USD]						= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'A', ISNULL(stg.SUMMABLE_int_funds_wth_USD,0) ,0))
			,[SUMMABLE_CEDED_int_funds_wth]						= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'C', ISNULL(stg.SUMMABLE_int_funds_wth,0) ,0))
			,[SUMMABLE_CEDED_int_funds_wth_USD]					= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'C', ISNULL(stg.SUMMABLE_int_funds_wth_USD,0) ,0))

			,[SUMMABLE_fire_prevent_fund]						= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'A', ISNULL(stg.SUMMABLE_fire_prevent_fund,0) ,0))
			,[SUMMABLE_fire_prevent_fund_USD]					= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'A', ISNULL(stg.SUMMABLE_fire_prevent_fund_USD,0) ,0))
			,[SUMMABLE_CEDED_fire_prevent_fund]					= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'C', ISNULL(stg.SUMMABLE_fire_prevent_fund,0) ,0))
			,[SUMMABLE_CEDED_fire_prevent_fund_USD]				= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'C', ISNULL(stg.SUMMABLE_fire_prevent_fund_USD,0) ,0))

			,[SUMMABLE_xch_diff]								= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'A', ISNULL(stg.SUMMABLE_xch_diff,0) ,0))
			,[SUMMABLE_xch_diff_USD]							= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'A', ISNULL(stg.SUMMABLE_xch_diff_USD,0) ,0))
			,[SUMMABLE_CEDED_xch_diff]							= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'C', ISNULL(stg.SUMMABLE_xch_diff,0) ,0))
			,[SUMMABLE_CEDED_xch_diff_USD]						= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'C', ISNULL(stg.SUMMABLE_xch_diff_USD,0) ,0))

			,[SUMMABLE_NO_CLM_RBT]								= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'A', ISNULL(stg.SUMMABLE_NO_CLM_RBT,0) ,0))
			,[SUMMABLE_NO_CLM_RBT_USD]							= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'A', ISNULL(stg.SUMMABLE_NO_CLM_RBT_USD,0) ,0))
			,[SUMMABLE_CEDED_NO_CLM_RBT]						= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'C', ISNULL(stg.SUMMABLE_NO_CLM_RBT,0) ,0))
			,[SUMMABLE_CEDED_NO_CLM_RBT_USD]					= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'C', ISNULL(stg.SUMMABLE_NO_CLM_RBT_USD,0) ,0))

			,[SUMMABLE_funds_withheld_premium]					= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'A', ISNULL(stg.SUMMABLE_funds_withheld_premium,0) ,0))
			,[SUMMABLE_funds_withheld_premium_USD]				= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'A', ISNULL(stg.SUMMABLE_funds_withheld_premium_USD,0) ,0))
			,[SUMMABLE_CEDED_funds_withheld_premium]			= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'C', ISNULL(stg.SUMMABLE_funds_withheld_premium,0) ,0))
			,[SUMMABLE_CEDED_funds_withheld_premium_USD]		= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'C', ISNULL(stg.SUMMABLE_funds_withheld_premium_USD,0) ,0))

			,[SUMMABLE_funds_released_premium]					= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'A', ISNULL(stg.SUMMABLE_funds_released_premium,0) ,0))
			,[SUMMABLE_funds_released_premium_USD]				= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'A', ISNULL(stg.SUMMABLE_funds_released_premium_USD,0) ,0))
			,[SUMMABLE_CEDED_funds_released_premium]			= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'C', ISNULL(stg.SUMMABLE_funds_released_premium,0) ,0))
			,[SUMMABLE_CEDED_funds_released_premium_USD]		= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'C', ISNULL(stg.SUMMABLE_funds_released_premium_USD,0) ,0))

			,[SUMMABLE_funds_withheld_losses]					= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'A', ISNULL(stg.SUMMABLE_funds_withheld_losses,0) ,0))
			,[SUMMABLE_funds_withheld_losses_USD]				= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'A', ISNULL(stg.SUMMABLE_funds_withheld_losses_USD,0) ,0))
			,[SUMMABLE_CEDED_funds_withheld_losses]				= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'C', ISNULL(stg.SUMMABLE_funds_withheld_losses,0) ,0))
			,[SUMMABLE_CEDED_funds_withheld_losses_USD]			= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'C', ISNULL(stg.SUMMABLE_funds_withheld_losses_USD,0) ,0))

			,[SUMMABLE_deferred_withheld]						= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'A', ISNULL(stg.SUMMABLE_deferred_withheld,0) ,0))
			,[SUMMABLE_deferred_withheld_USD]					= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'A', ISNULL(stg.SUMMABLE_deferred_withheld_USD,0) ,0))
			,[SUMMABLE_CEDED_deferred_withheld]					= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'C', ISNULL(stg.SUMMABLE_deferred_withheld,0) ,0))
			,[SUMMABLE_CEDED_deferred_withheld_USD]				= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'C', ISNULL(stg.SUMMABLE_deferred_withheld_USD,0) ,0))

			,[SUMMABLE_deferred_released]						= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'A', ISNULL(stg.SUMMABLE_deferred_released,0) ,0))
			,[SUMMABLE_deferred_released_USD]					= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'A', ISNULL(stg.SUMMABLE_deferred_released_USD,0) ,0))
			,[SUMMABLE_CEDED_deferred_released]					= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'C', ISNULL(stg.SUMMABLE_deferred_released,0) ,0))
			,[SUMMABLE_CEDED_deferred_released_USD]				= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'C', ISNULL(stg.SUMMABLE_deferred_released_USD,0) ,0))

			,[SUMMABLE_UEPR]									= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'A', ISNULL(stg.SUMMABLE_UEPR,0) ,0))
			,[SUMMABLE_UEPR_USD]								= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'A', ISNULL(stg.SUMMABLE_UEPR_USD,0) ,0))
			,[SUMMABLE_CEDED_UEPR]								= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'C', ISNULL(stg.SUMMABLE_UEPR,0) ,0))
			,[SUMMABLE_CEDED_UEPR_USD]							= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'C', ISNULL(stg.SUMMABLE_UEPR_USD,0) ,0))
			,[SUMMABLE_UEPR_RPT_CURR1]							= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'A', ISNULL(stg.SUMMABLE_UEPR_RPT_CURR1,0) ,0))
			,[SUMMABLE_UEPR_RPT_CURR2]							= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'A', ISNULL(stg.SUMMABLE_UEPR_RPT_CURR2,0) ,0))

			,[SUMMABLE_DAC]										= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'A', ISNULL(stg.SUMMABLE_DAC,0) ,0))
			,[SUMMABLE_DAC_USD]									= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'A', ISNULL(stg.SUMMABLE_DAC_USD,0) ,0))
			,[SUMMABLE_CEDED_DAC]								= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'C', ISNULL(stg.SUMMABLE_DAC,0) ,0))
			,[SUMMABLE_CEDED_DAC_USD]							= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'C', ISNULL(stg.SUMMABLE_DAC_USD,0) ,0))
			,[SUMMABLE_DAC_RPT_CURR1]							= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'A', ISNULL(stg.SUMMABLE_DAC_RPT_CURR1,0) ,0))
			,[SUMMABLE_DAC_RPT_CURR2]							= CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'A', ISNULL(stg.SUMMABLE_DAC_RPT_CURR2,0) ,0))
			,[SUMMABLE_FUNDS_RELEASED_LOSSES] 	                = CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'A', ISNULL(stg.SUMMABLE_FUNDS_RELEASED_LOSSES,0) ,0))
            ,[SUMMABLE_FUNDS_RELEASED_LOSSES_USD]               = CONVERT(MONEY, IIF(stg.assumed_ceded_flg = 'A', ISNULL(stg.SUMMABLE_FUNDS_RELEASED_LOSSES_USD,0) ,0))

			----------
			,[T7_CODE]				= h.T7_CODE
			,[T8_CODE]				= h.T8_CODE
			,[T9_CODE]				= h.T9_CODE
			,[MBU]					= h.MBU
			,[L01]					= h.L01
			,[L02]					= h.L02
			,[L03]					= h.L03
			,[L04]					= ''
			,[L05]					= NULL
			,[L06]					= h.L06
			,[l07]					= h.L07
			,[L08]					= NULL
			,[L09]					= NULL
			,[L10]					= h.L10
			,[GD1]					= h.GD1
			,[RPTCURR1]				= CAST(IIF(R.K1CURRENCY_CODE='USD',1, Rorig.ExchangeRate) * (1/NULLIF(RT1.ExchangeRate,0))  AS FLOAT)
			,[RPTCURR1_CD]			= h.RPTCURR1_CD
			,[RPTCURR2]				= CAST(IIF(R.K1CURRENCY_CODE='USD',1, Rorig.ExchangeRate) * (1/NULLIF(RT2.ExchangeRate,0))  AS FLOAT)
			,[RPTCURR2_CD] 			= h.RPTCURR2_CD
			,[InsurerCode]			= h.InsurerCode
			,[Financial_Lob]		= h.t2_code
			,[RPT_OFC_NM]			= h.RPT_OFC_NM
			,[RPT_OFF_NAME]			= h.RPT_OFF_NAME
			,[ICP_CEDED_FLG]		= h.ICP_CEDED_FLG
			,[actuariallob]			= h.ActuarialLob
			,[CLMS_PROCSS_CLM_DEPT]	= h.CLMS_PROCSS_CLM_DEPT
			,[ID]					= NULL/*'To be define'*/
			,[Unmatched_Fields]		= NULL/*'To be define'*/
			,[topside_reg_date]		= CAST(NULL AS DATETIME)
			,[Blended_Rate]			= NULL/*'To be define'*/
			,[MATCH_SOURCE_FLAG]	= NULL/*'To be define'*/
			,[TransactionTypeCode]	= CAST(stg.doc_type_cd AS VARCHAR(10))
			,[TransactionTypeCategory] = 'Document Type'
		 FROM EDW_Staging.assumed.TIRS_UW_staging	AS stg
		 LEFT JOIN	(
					SELECT h.contract_NBR		,h.lob_name				,ActuarialLob = COALESCE(ame.ActuarialLob,am.ActuarialLob)
						  ,h.RPT_OFF_NAME		,CLMS_PROCSS_CLM_DEPT	,ICP_CEDED_FLG	,tim.[InsurerCode]
						  ,T2_code				,h.T7_CODE				,h.T8_CODE		,h.T9_CODE
						  ,tim.rpt_ofc_nm		,[MBU]					,[GD1]
						  ,[L01]				,[L02]					,[L03]			,[L06]
						  ,[l07]				,[L10]					,[RPTCURR1_CD]	,[RPTCURR2_CD]
					  FROM  EDW_PREPROD.dbo.T_Code_history	H	
					  LEFT JOIN EDW_STAGING.dbo.TIRS_InsurerCodeMapping				TIM	ON H.RPT_OFF_NAME= TIM.[rpt_ofc_nm]
					  LEFT JOIN EDW_STAGING.dbo.TIRS_ActuarialLobMapping			AM	ON AM.rpt_ofc_nm=H.RPT_OFF_NAME AND AM.division_nm=H.DIV_NAME AND AM.dept_nm=H.DEPT_NAME AND AM.sub_dept_nm=H.SUB_DEPT_NAME AND AM.UNDERWRITING_YEAR=RIGHT(RTRIM(h.Contract_NBR),4) COLLATE DATABASE_DEFAULT
					  LEFT JOIN EDW_STAGING.dbo.TIRS_ActuarialLobMapping_Exceptions AME ON AME.CONTRACT_NBR=H.Contract_NBR 
					  CROSS JOIN #Parameters prm
					WHERE prm.ProcessingDate >= H.start_date AND prm.ProcessingDate < H.end_date
					) AS H								ON	stg.contract_nbr COLLATE DATABASE_DEFAULT	= h.contract_nbr
														AND stg.lob_name	 COLLATE DATABASE_DEFAULT	= h.lob_name
		 LEFT JOIN EDW_PREPROD.dbo.EDW_TIRS_ROE	AS R	ON  stg.TIRS_ORIG_CURR_CD COLLATE DATABASE_DEFAULT =R.TIRS_CURRENCY_CODE COLLATE DATABASE_DEFAULT 
														AND stg.reg_date = r.K1PERIOD_OF_TIME
		OUTER APPLY (  SELECT TOP 1 * FROM  #LGC Rorig	WHERE Rorig.ISOCode COLLATE DATABASE_DEFAULT=R.K1CURRENCY_CODE  AND Rorig.JoinMonth=FORMAT(stg.reg_date, 'yyyy/MM', 'en-US' )) Rorig
		OUTER APPLY (  SELECT TOP 1 * FROM  #LGC RT1	WHERE RT1.ISOCode COLLATE DATABASE_DEFAULT=H.RPTCURR1_CD   AND RT1.JoinMonth=FORMAT(stg.reg_date, 'yyyy/MM', 'en-US' )) RT1
		OUTER APPLY (  SELECT TOP 1 * FROM  #LGC RT2	WHERE RT2.ISOCode COLLATE DATABASE_DEFAULT=H.RPTCURR2_CD   AND RT2.JoinMonth=FORMAT(stg.reg_date, 'yyyy/MM', 'en-US' )) RT2
		LEFT  JOIN SRC_TIRS_DB.dbo.xrf_curr_names		AS cn 		ON stg.TIRS_ORIG_CURR_CD = cn.curr_cd
		LEFT  JOIN SRC_TIRS_DB.dbo.trty_master			AS tm		ON tm.trty_key = stg.trty_key
		LEFT  JOIN SRC_TIRS_DB.dbo.xrf_lob_cds			AS lob		ON lob.lob_cd = stg.pr_cls_cd

		LEFT  JOIN SRC_TIRS_DB.dbo.xrf_annl_stmt_line	AS aslob	ON lob.annl_stmt_key = aslob.annl_stmt_key
		LEFT  JOIN EDW_STAGING.dbo.TIRS_ASLOBCodeMapping AS am  	ON am.pro_xol_flg=tm.pro_xol_flg COLLATE DATABASE_DEFAULT AND am.annl_stmt_ln=aslob.annl_stmt_ln COLLATE DATABASE_DEFAULT
		LEFT  JOIN SRC_TIRS_DB.dbo.xrf_rpt_ofc			AS XR		ON XR.rpt_ofc_cd= tm.rpt_ofc_cd
		LEFT  JOIN SRC_TIRS_DB.dbo.xrf_sub_dept_cds		AS sd		ON tm.sub_dept_key = sd.sub_dept_key
		LEFT  JOIN EDW_PREPROD.dbo.solvency_II_regulatory_etl AS solII	ON	solII.source='TIRS' 
																		AND solII.assumed_or_direct = 'Assumed'
																		AND ISNULL(solII.branch_name,'')			collate Latin1_General_CI_AI = isnull(XR.rpt_ofc_nm,'') 
																		AND ISNULL(solII.product_group_name,'')		collate Latin1_General_CI_AI = isnull(sd.division_nm,'') 
																		AND ISNULL(solII.product_department_name,'')collate Latin1_General_CI_AI = isnull(sd.dept_nm,'') 
																		AND ISNULL(solII.sub_product,'')			collate Latin1_General_CI_AI = isnull(Sd.sub_dept_nm,'') 
																		AND ISNULL(solII.lob_name,'')				collate Latin1_General_CI_AI = isnull(lob.desc_txt,'') 
																		AND ISNULL(solII.prorata_or_xol,'')			collate Latin1_General_CI_AI = isnull(iif(tm.pro_xol_flg ='X', 'XOL', 'Pro Rata'),'')  
																		AND ISNULL(solII.treaty_or_fav,'')			collate Latin1_General_CI_AI = isnull(iif(tm.trty_or_fac_flg='F', 'FAC', 'Treaty'),'') 
																		AND ISNULL(solII.property_or_casualty,'')	collate Latin1_General_CI_AI = isnull(case  when sd.division_nm like '%property%'	then 'PROPERTY'
																																								when sd.division_nm like '%marine%'		then 'PROPERTY'  
																																								else 'CASUALTY' END,'')
																		AND ISNULL(solII.is_lloyds,'')				collate Latin1_General_CI_AI = isnull(iif(XR.rpt_ofc_nm like '%lloyd%', 'Lloyds', 'Non-Lloyds'),'')
																		AND ISNULL(solII.transaction_ASLOB_code,'')	collate Latin1_General_CI_AI = isnull(aslob.annl_stmt_ln,'') 
																		AND COALESCE(tm.inception_dt, '1900-01-01') 
																			BETWEEN COALESCE(solII.InceptionFrom, '1900-01-01') AND COALESCE(solII.InceptionTo, '9999-12-31') 
		WHERE stg.EndDate='9999-12-31'
		  AND EXISTS (SELECT *
					    FROM #ContractFilter	AS cf
					   WHERE cf.CONTRACT_NBR = stg.CONTRACT_NBR COLLATE DATABASE_DEFAULT )

		SET @v_RowCount = ROWCOUNT_BIG();
		INSERT INTO ##Timings_UW SELECT SYSDATETIME(), 'Inserted #UnderwritingLoadWide - TIRS', @v_RowCount;
		--------------------------------------------------------------------------------	
		-- #UnderwritingLoadWide - INSERT OPENBOX data
		--------------------------------------------------------------------------------	
		INSERT INTO #UnderwritingLoadWide
		(
		   [TREATY_NBR]
		  ,[UNDERWRITING_YEAR]
		  ,[CONTRACT_NBR]
		  ,[CEDED_CONTRACT_NBR]
		  ,[SourceSystemKey]
		  ,[Source]
		  ,[TIRS_ORIG_CURR_CD]
		  ,[TIRS_ORIG_CURR_NAME]
		  ,[lob_name]
		  ,[reg_date]
		  ,[due_date]
		  ,[acct_from_dt]	
		  ,[acct_to_dt]	
		  ,[doc_key]
		  ,[bill_company_cd]
		  ,[aslob]
		  ,[solvency_II_regulatory_key]
		  ,[AdjustmentType]
		  ,[TIRS_UW_ASSM_CEDED_NAME]
		  ,[SUMMABLE_WRTN_PREM_ALL_DOC_TYPES]
		  ,[SUMMABLE_WRTN_PREM_ALL_DOC_TYPES_USD]
		  ,[SUMMABLE_CEDED_WRTN_PREM_ALL_DOC_TYPES]
		  ,[SUMMABLE_CEDED_WRTN_PREM_ALL_DOC_TYPES_USD]
		  ,[SUMMABLE_WRTN_PREM_No_Claims_Rebate]
		  ,[SUMMABLE_WRTN_PREM_No_Claims_Rebate_USD]
		  ,[SUMMABLE_CEDED_WRTN_PREM_No_Claims_Rebate]
		  ,[SUMMABLE_CEDED_WRTN_PREM_No_Claims_Rebate_USD]
		  ,[SUMMABLE_WRTN_PREM_Reinstatement_Premium]
		  ,[SUMMABLE_WRTN_PREM_Reinstatement_Premium_USD]
		  ,[SUMMABLE_CEDED_WRTN_PREM_Reinstatement_Premium]
		  ,[SUMMABLE_CEDED_WRTN_PREM_Reinstatement_Premium_USD]
		  ,[SUMMABLE_Brokerage]
		  ,[SUMMABLE_Brokerage_USD]
		  ,[SUMMABLE_CEDED_Brokerage]
		  ,[SUMMABLE_CEDED_Brokerage_USD]
		  ,[SUMMABLE_Commission]
		  ,[SUMMABLE_Commission_USD]
		  ,[SUMMABLE_CEDED_Commission]
		  ,[SUMMABLE_CEDED_Commission_USD]
		  ,[SUMMABLE_tax_nonrefund]
		  ,[SUMMABLE_tax_nonrefund_USD]
		  ,[SUMMABLE_CEDED_tax_nonrefund]
		  ,[SUMMABLE_CEDED_tax_nonrefund_USD]
		  ,[SUMMABLE_tax_on_prem]
		  ,[SUMMABLE_tax_on_prem_USD]
		  ,[SUMMABLE_CEDED_tax_on_prem]
		  ,[SUMMABLE_CEDED_tax_on_prem_USD]
		  ,[SUMMABLE_tax_refund]
		  ,[SUMMABLE_tax_refund_USD]
		  ,[SUMMABLE_CEDED_tax_refund]
		  ,[SUMMABLE_CEDED_tax_refund_USD]
		  ,[SUMMABLE_Profit_Commission_Paid]
		  ,[SUMMABLE_Profit_Commission_Paid_USD]
		  ,[SUMMABLE_CEDED_Profit_Commission_Paid]
		  ,[SUMMABLE_CEDED_Profit_Commission_Paid_USD]
		  ,[SUMMABLE_Sliding_Scale_Commission]
		  ,[SUMMABLE_Sliding_Scale_Commission_USD]
		  ,[SUMMABLE_CEDED_Sliding_Scale_Commission]
		  ,[SUMMABLE_CEDED_Sliding_Scale_Commission_USD]
		  ,[SUMMABLE_Overrider_Commission]
		  ,[SUMMABLE_Overrider_Commission_USD]
		  ,[SUMMABLE_CEDED_Overrider_Commission]
		  ,[SUMMABLE_CEDED_Overrider_Commission_USD]       
		  ,[SUMMABLE_Provisional_Commission]
		  ,[SUMMABLE_Provisional_Commission_USD]
		  ,[SUMMABLE_CEDED_Provisional_Commission]
		  ,[SUMMABLE_CEDED_Provisional_Commission_USD]
		  ,[SUMMABLE_Deferred_Commission]
		  ,[SUMMABLE_Deferred_Commission_USD]
		  ,[SUMMABLE_CEDED_Deferred_Commission]
		  ,[SUMMABLE_CEDED_Deferred_Commission_USD]
		  ,[SUMMABLE_int_funds_gross]
		  ,[SUMMABLE_int_funds_gross_USD]
		  ,[SUMMABLE_CEDED_int_funds_gross]
		  ,[SUMMABLE_CEDED_int_funds_gross_USD]
		  ,[SUMMABLE_int_funds_wth]
		  ,[SUMMABLE_int_funds_wth_USD]
		  ,[SUMMABLE_CEDED_int_funds_wth]
		  ,[SUMMABLE_CEDED_int_funds_wth_USD]
		  ,[SUMMABLE_fire_prevent_fund]
		  ,[SUMMABLE_fire_prevent_fund_USD]
		  ,[SUMMABLE_CEDED_fire_prevent_fund]
		  ,[SUMMABLE_CEDED_fire_prevent_fund_USD]
		  ,[SUMMABLE_xch_diff]
		  ,[SUMMABLE_xch_diff_USD]
		  ,[SUMMABLE_CEDED_xch_diff]
		  ,[SUMMABLE_CEDED_xch_diff_USD]
		  ,[SUMMABLE_NO_CLM_RBT]
		  ,[SUMMABLE_NO_CLM_RBT_USD]
		  ,[SUMMABLE_CEDED_NO_CLM_RBT]
		  ,[SUMMABLE_CEDED_NO_CLM_RBT_USD]
		  ,[SUMMABLE_funds_withheld_premium]
		  ,[SUMMABLE_funds_withheld_premium_USD]
		  ,[SUMMABLE_CEDED_funds_withheld_premium]
		  ,[SUMMABLE_CEDED_funds_withheld_premium_USD]
		  ,[SUMMABLE_funds_released_premium]
		  ,[SUMMABLE_funds_released_premium_USD]
		  ,[SUMMABLE_CEDED_funds_released_premium]
		  ,[SUMMABLE_CEDED_funds_released_premium_USD]
		  ,[SUMMABLE_funds_withheld_losses]
		  ,[SUMMABLE_funds_withheld_losses_USD]
		  ,[SUMMABLE_CEDED_funds_withheld_losses]
		  ,[SUMMABLE_CEDED_funds_withheld_losses_USD]
		  ,[SUMMABLE_deferred_withheld]
		  ,[SUMMABLE_deferred_withheld_USD]
		  ,[SUMMABLE_CEDED_deferred_withheld]
		  ,[SUMMABLE_CEDED_deferred_withheld_USD]
		  ,[SUMMABLE_deferred_released]
		  ,[SUMMABLE_deferred_released_USD]
		  ,[SUMMABLE_CEDED_deferred_released]
		  ,[SUMMABLE_CEDED_deferred_released_USD]
		  ,[SUMMABLE_UEPR]
		  ,[SUMMABLE_UEPR_USD]
		  ,[SUMMABLE_CEDED_UEPR]
		  ,[SUMMABLE_CEDED_UEPR_USD]
		  ,[SUMMABLE_UEPR_RPT_CURR1]
		  ,[SUMMABLE_UEPR_RPT_CURR2]
		  ,[SUMMABLE_DAC]
		  ,[SUMMABLE_DAC_USD]
		  ,[SUMMABLE_CEDED_DAC]
		  ,[SUMMABLE_CEDED_DAC_USD]
		  ,[SUMMABLE_DAC_RPT_CURR1]
		  ,[SUMMABLE_DAC_RPT_CURR2]
		  ,[SUMMABLE_FUNDS_RELEASED_LOSSES] 	
          ,[SUMMABLE_FUNDS_RELEASED_LOSSES_USD]
		  ,[T7_CODE]
		  ,[T8_CODE]
		  ,[T9_CODE]
		  ,[MBU]
		  ,[L01]
		  ,[L02]
		  ,[L03]
		  ,[L04]
		  ,[L05]
		  ,[L06]
		  ,[L07]
		  ,[L08]
		  ,[L09]
		  ,[L10]
		  ,[GD1]
		  ,[RPTCURR1]
		  ,[RPTCURR1_CD]
		  ,[RPTCURR2]
		  ,[RPTCURR2_CD]
		  ,[InsurerCode]
		  ,[Financial_Lob]
		  ,[RPT_OFC_NM]
		  ,[RPT_OFF_NAME]
		  ,[ICP_CEDED_FLG]
		  ,[actuariallob]
		  ,[CLMS_PROCSS_CLM_DEPT]
		  ,[ID]
		  ,[Unmatched_Fields]
		  ,[topside_reg_date]
		  ,[Blended_Rate]
		  ,[MATCH_SOURCE_FLAG]
		  ,[TransactionTypeCode]
		  ,[TransactionTypeCategory]
		)
	SELECT [TREATY_NBR]		
		  ,[UNDERWRITING_YEAR]
		  ,[CONTRACT_NBR]
		  ,[CEDED_CONTRACT_NBR]	= NULL
		  ,[SourceSystemKey]	= SourceSystemKey
		  ,[Source]				= 'OPENBOX'
		  ,[TIRS_ORIG_CURR_CD]
		  ,[TIRS_ORIG_CURR_NAME]
		  ,[lob_name]
		  ,[reg_date]
		  ,[due_date]			= DueDate
		  ,[acct_from_dt]		= FromDate 
		  ,[acct_to_dt]			= ToDate 
		  ,[doc_key]			= doc_key
		  ,[bill_company_cd]	= NULL
		  ,[aslob]
		  ,[solvency_II_regulatory_key]
		  ,[AdjustmentType]
		  ,[TIRS_UW_ASSM_CEDED_NAME]
		  ,[SUMMABLE_WRTN_PREM_ALL_DOC_TYPES]
		  ,[SUMMABLE_WRTN_PREM_ALL_DOC_TYPES_USD]
		  ,[SUMMABLE_CEDED_WRTN_PREM_ALL_DOC_TYPES]			= CONVERT(MONEY, 0)
		  ,[SUMMABLE_CEDED_WRTN_PREM_ALL_DOC_TYPES_USD]		= CONVERT(MONEY, 0)
		  ,[SUMMABLE_WRTN_PREM_No_Claims_Rebate]			= CONVERT(MONEY, 0)
		  ,[SUMMABLE_WRTN_PREM_No_Claims_Rebate_USD]		= CONVERT(MONEY, 0)
		  ,[SUMMABLE_CEDED_WRTN_PREM_No_Claims_Rebate]		= CONVERT(MONEY, 0)
		  ,[SUMMABLE_CEDED_WRTN_PREM_No_Claims_Rebate_USD]	= CONVERT(MONEY, 0)
		  ,[SUMMABLE_WRTN_PREM_Reinstatement_Premium]		= CONVERT(MONEY, 0)
		  ,[SUMMABLE_WRTN_PREM_Reinstatement_Premium_USD]	= CONVERT(MONEY, 0)
		  ,[SUMMABLE_CEDED_WRTN_PREM_Reinstatement_Premium]	= CONVERT(MONEY, 0)
		  ,[SUMMABLE_CEDED_WRTN_PREM_Reinstatement_Premium_USD]	= CONVERT(MONEY, 0)
		  ,[SUMMABLE_Brokerage]
		  ,[SUMMABLE_Brokerage_USD]
		  ,[SUMMABLE_CEDED_Brokerage]						= CONVERT(MONEY, 0)
		  ,[SUMMABLE_CEDED_Brokerage_USD]					= CONVERT(MONEY, 0)
		  ,[SUMMABLE_Commission]
		  ,[SUMMABLE_Commission_USD]
		  ,[SUMMABLE_CEDED_Commission]						= CONVERT(MONEY, 0)
		  ,[SUMMABLE_CEDED_Commission_USD]					= CONVERT(MONEY, 0)
		  ,[SUMMABLE_tax_nonrefund]
		  ,[SUMMABLE_tax_nonrefund_USD]
		  ,[SUMMABLE_CEDED_tax_nonrefund]					= CONVERT(MONEY, 0)
		  ,[SUMMABLE_CEDED_tax_nonrefund_USD]				= CONVERT(MONEY, 0)
		  ,[SUMMABLE_tax_on_prem]
		  ,[SUMMABLE_tax_on_prem_USD]
		  ,[SUMMABLE_CEDED_tax_on_prem]						= CONVERT(MONEY, 0)
		  ,[SUMMABLE_CEDED_tax_on_prem_USD]					= CONVERT(MONEY, 0)
		  ,[SUMMABLE_tax_refund]							= CONVERT(MONEY, 0)
		  ,[SUMMABLE_tax_refund_USD]						= CONVERT(MONEY, 0)
		  ,[SUMMABLE_CEDED_tax_refund]						= CONVERT(MONEY, 0)
		  ,[SUMMABLE_CEDED_tax_refund_USD]					= CONVERT(MONEY, 0)
		  ,[SUMMABLE_Profit_Commission_Paid]				= CONVERT(MONEY, 0)
		  ,[SUMMABLE_Profit_Commission_Paid_USD]			= CONVERT(MONEY, 0)
		  ,[SUMMABLE_CEDED_Profit_Commission_Paid]			= CONVERT(MONEY, 0)
		  ,[SUMMABLE_CEDED_Profit_Commission_Paid_USD]		= CONVERT(MONEY, 0)
		  ,[SUMMABLE_Sliding_Scale_Commission]				= CONVERT(MONEY, 0)
		  ,[SUMMABLE_Sliding_Scale_Commission_USD]			= CONVERT(MONEY, 0)
		  ,[SUMMABLE_CEDED_Sliding_Scale_Commission]		= CONVERT(MONEY, 0)
		  ,[SUMMABLE_CEDED_Sliding_Scale_Commission_USD]	= CONVERT(MONEY, 0)
		  ,[SUMMABLE_Overrider_Commission]					= CONVERT(MONEY, 0)
		  ,[SUMMABLE_Overrider_Commission_USD]				= CONVERT(MONEY, 0)
		  ,[SUMMABLE_CEDED_Overrider_Commission]			= CONVERT(MONEY, 0)
		  ,[SUMMABLE_CEDED_Overrider_Commission_USD]       	= CONVERT(MONEY, 0)
		  ,[SUMMABLE_Provisional_Commission]				= CONVERT(MONEY, 0)
		  ,[SUMMABLE_Provisional_Commission_USD]			= CONVERT(MONEY, 0)
		  ,[SUMMABLE_CEDED_Provisional_Commission]			= CONVERT(MONEY, 0)
		  ,[SUMMABLE_CEDED_Provisional_Commission_USD]		= CONVERT(MONEY, 0)
		  ,[SUMMABLE_Deferred_Commission]					= CONVERT(MONEY, 0)
		  ,[SUMMABLE_Deferred_Commission_USD]				= CONVERT(MONEY, 0)
		  ,[SUMMABLE_CEDED_Deferred_Commission]				= CONVERT(MONEY, 0)
		  ,[SUMMABLE_CEDED_Deferred_Commission_USD]			= CONVERT(MONEY, 0)
		  ,[SUMMABLE_int_funds_gross]						= CONVERT(MONEY, 0)
		  ,[SUMMABLE_int_funds_gross_USD]					= CONVERT(MONEY, 0)
		  ,[SUMMABLE_CEDED_int_funds_gross]					= CONVERT(MONEY, 0)
		  ,[SUMMABLE_CEDED_int_funds_gross_USD]				= CONVERT(MONEY, 0)
		  ,[SUMMABLE_int_funds_wth]							= CONVERT(MONEY, 0)
		  ,[SUMMABLE_int_funds_wth_USD]						= CONVERT(MONEY, 0)
		  ,[SUMMABLE_CEDED_int_funds_wth]					= CONVERT(MONEY, 0)
		  ,[SUMMABLE_CEDED_int_funds_wth_USD]				= CONVERT(MONEY, 0)
		  ,[SUMMABLE_fire_prevent_fund]						= CONVERT(MONEY, 0)
		  ,[SUMMABLE_fire_prevent_fund_USD]					= CONVERT(MONEY, 0)
		  ,[SUMMABLE_CEDED_fire_prevent_fund]				= CONVERT(MONEY, 0)
		  ,[SUMMABLE_CEDED_fire_prevent_fund_USD]			= CONVERT(MONEY, 0)
		  ,[SUMMABLE_xch_diff]								= CONVERT(MONEY, 0)
		  ,[SUMMABLE_xch_diff_USD]							= CONVERT(MONEY, 0)
		  ,[SUMMABLE_CEDED_xch_diff]						= CONVERT(MONEY, 0)
		  ,[SUMMABLE_CEDED_xch_diff_USD]					= CONVERT(MONEY, 0)
		  ,[SUMMABLE_NO_CLM_RBT]							= CONVERT(MONEY, 0)
		  ,[SUMMABLE_NO_CLM_RBT_USD]						= CONVERT(MONEY, 0)
		  ,[SUMMABLE_CEDED_NO_CLM_RBT]						= CONVERT(MONEY, 0)
		  ,[SUMMABLE_CEDED_NO_CLM_RBT_USD]					= CONVERT(MONEY, 0)
		  ,[SUMMABLE_funds_withheld_premium]				= CONVERT(MONEY, 0)
		  ,[SUMMABLE_funds_withheld_premium_USD]			= CONVERT(MONEY, 0)
		  ,[SUMMABLE_CEDED_funds_withheld_premium]			= CONVERT(MONEY, 0)
		  ,[SUMMABLE_CEDED_funds_withheld_premium_USD]		= CONVERT(MONEY, 0)
		  ,[SUMMABLE_funds_released_premium]				= CONVERT(MONEY, 0)
		  ,[SUMMABLE_funds_released_premium_USD]			= CONVERT(MONEY, 0)
		  ,[SUMMABLE_CEDED_funds_released_premium]			= CONVERT(MONEY, 0)
		  ,[SUMMABLE_CEDED_funds_released_premium_USD]		= CONVERT(MONEY, 0)
		  ,[SUMMABLE_funds_withheld_losses]					= CONVERT(MONEY, 0)
		  ,[SUMMABLE_funds_withheld_losses_USD]				= CONVERT(MONEY, 0)
		  ,[SUMMABLE_CEDED_funds_withheld_losses]			= CONVERT(MONEY, 0)
		  ,[SUMMABLE_CEDED_funds_withheld_losses_USD]		= CONVERT(MONEY, 0)
		  ,[SUMMABLE_deferred_withheld]						= CONVERT(MONEY, 0)
		  ,[SUMMABLE_deferred_withheld_USD]					= CONVERT(MONEY, 0)
		  ,[SUMMABLE_CEDED_deferred_withheld]				= CONVERT(MONEY, 0)
		  ,[SUMMABLE_CEDED_deferred_withheld_USD]			= CONVERT(MONEY, 0)
		  ,[SUMMABLE_deferred_released]						= CONVERT(MONEY, 0)
		  ,[SUMMABLE_deferred_released_USD]					= CONVERT(MONEY, 0)
		  ,[SUMMABLE_CEDED_deferred_released]				= CONVERT(MONEY, 0)
		  ,[SUMMABLE_CEDED_deferred_released_USD]			= CONVERT(MONEY, 0)
		  ,[SUMMABLE_UEPR]
		  ,[SUMMABLE_UEPR_USD]
		  ,[SUMMABLE_CEDED_UEPR]							= CONVERT(MONEY, 0)
		  ,[SUMMABLE_CEDED_UEPR_USD]						= CONVERT(MONEY, 0)
		  ,[SUMMABLE_UEPR_RPT_CURR1]
		  ,[SUMMABLE_UEPR_RPT_CURR2]						= CONVERT(MONEY, 0)
		  ,[SUMMABLE_DAC]
		  ,[SUMMABLE_DAC_USD]
		  ,[SUMMABLE_CEDED_DAC]								= CONVERT(MONEY, 0)
		  ,[SUMMABLE_CEDED_DAC_USD]							= CONVERT(MONEY, 0)
		  ,[SUMMABLE_DAC_RPT_CURR1]
		  ,[SUMMABLE_DAC_RPT_CURR2]							= CONVERT(MONEY, 0)
		  ,[SUMMABLE_FUNDS_RELEASED_LOSSES] 	            = CONVERT(MONEY, 0)
          ,[SUMMABLE_FUNDS_RELEASED_LOSSES_USD]             = CONVERT(MONEY, 0)
		  ,[T7_CODE]
		  ,[T8_CODE]
		  ,[T9_CODE]
		  ,[MBU]
		  ,[L01]
		  ,[L02]
		  ,[L03]
		  ,[L04]
		  ,[L05]			= NULL
		  ,[L06]
		  ,[L07]
		  ,[L08]			= NULL
		  ,[L09]			= NULL
		  ,[L10]
		  ,[GD1]
		  ,[RPTCURR1]
		  ,[RPTCURR1_CD]
		  ,[RPTCURR2]
		  ,[RPTCURR2_CD]
		  ,[InsurerCode]
		  ,[Financial_Lob]
		  ,[RPT_OFC_NM]
		  ,[RPT_OFF_NAME]
		  ,[ICP_CEDED_FLG]
		  ,[actuariallob]
		  ,[CLMS_PROCSS_CLM_DEPT]	= NULL
		  ,[ID]						= NULL
		  ,[Unmatched_Fields]		= NULL
		  ,[topside_reg_date]		= NULL
		  ,[Blended_Rate]
		  ,[MATCH_SOURCE_FLAG]		= NULL
		  ,[TransactionTypeCode]	= stg.TransactionTypeCode
		  ,[TransactionTypeCategory]= stg.TransactionTypeCategory
		FROM [EDW_Staging].[assumed].[OPENBOX_UW_staging] AS stg
	   WHERE stg.EndDate = '9999-12-31'
		 AND EXISTS (SELECT *
					   FROM #ContractFilter	AS cf
					  WHERE cf.CONTRACT_NBR = stg.CONTRACT_NBR COLLATE DATABASE_DEFAULT )

		SET @v_RowCount = ROWCOUNT_BIG();
		INSERT INTO ##Timings_UW SELECT SYSDATETIME(), 'Inserted #UnderwritingLoadWide - OPENBOX', @v_RowCount;
		--------------------------------------------------------------------------------	
		-- #UnderwritingLoadWide - INSERT TOPSIDES data
		--------------------------------------------------------------------------------	
		INSERT INTO #UnderwritingLoadWide
		(
		   [TREATY_NBR]
		  ,[UNDERWRITING_YEAR]
		  ,[CONTRACT_NBR]
		  ,[CEDED_CONTRACT_NBR]
		  ,[SourceSystemKey]
		  ,[Source]
		  ,[TIRS_ORIG_CURR_CD]
		  ,[TIRS_ORIG_CURR_NAME]
		  ,[lob_name]
		  ,[reg_date]
		  ,[due_date]
		  ,[acct_from_dt]	
		  ,[acct_to_dt]	
		  ,[doc_key]
		  ,[bill_company_cd]
		  ,[aslob]
		  ,[solvency_II_regulatory_key]
		  ,[AdjustmentType]
		  ,[TIRS_UW_ASSM_CEDED_NAME]
		  ,[SUMMABLE_WRTN_PREM_ALL_DOC_TYPES]
		  ,[SUMMABLE_WRTN_PREM_ALL_DOC_TYPES_USD]
		  ,[SUMMABLE_CEDED_WRTN_PREM_ALL_DOC_TYPES]
		  ,[SUMMABLE_CEDED_WRTN_PREM_ALL_DOC_TYPES_USD]
		  ,[SUMMABLE_WRTN_PREM_No_Claims_Rebate]
		  ,[SUMMABLE_WRTN_PREM_No_Claims_Rebate_USD]
		  ,[SUMMABLE_CEDED_WRTN_PREM_No_Claims_Rebate]
		  ,[SUMMABLE_CEDED_WRTN_PREM_No_Claims_Rebate_USD]
		  ,[SUMMABLE_WRTN_PREM_Reinstatement_Premium]
		  ,[SUMMABLE_WRTN_PREM_Reinstatement_Premium_USD]
		  ,[SUMMABLE_CEDED_WRTN_PREM_Reinstatement_Premium]
		  ,[SUMMABLE_CEDED_WRTN_PREM_Reinstatement_Premium_USD]
		  ,[SUMMABLE_Brokerage]
		  ,[SUMMABLE_Brokerage_USD]
		  ,[SUMMABLE_CEDED_Brokerage]
		  ,[SUMMABLE_CEDED_Brokerage_USD]
		  ,[SUMMABLE_Commission]
		  ,[SUMMABLE_Commission_USD]
		  ,[SUMMABLE_CEDED_Commission]
		  ,[SUMMABLE_CEDED_Commission_USD]
		  ,[SUMMABLE_tax_nonrefund]
		  ,[SUMMABLE_tax_nonrefund_USD]
		  ,[SUMMABLE_CEDED_tax_nonrefund]
		  ,[SUMMABLE_CEDED_tax_nonrefund_USD]
		  ,[SUMMABLE_tax_on_prem]
		  ,[SUMMABLE_tax_on_prem_USD]
		  ,[SUMMABLE_CEDED_tax_on_prem]
		  ,[SUMMABLE_CEDED_tax_on_prem_USD]
		  ,[SUMMABLE_tax_refund]
		  ,[SUMMABLE_tax_refund_USD]
		  ,[SUMMABLE_CEDED_tax_refund]
		  ,[SUMMABLE_CEDED_tax_refund_USD]
		  ,[SUMMABLE_Profit_Commission_Paid]
		  ,[SUMMABLE_Profit_Commission_Paid_USD]
		  ,[SUMMABLE_CEDED_Profit_Commission_Paid]
		  ,[SUMMABLE_CEDED_Profit_Commission_Paid_USD]
		  ,[SUMMABLE_Sliding_Scale_Commission]
		  ,[SUMMABLE_Sliding_Scale_Commission_USD]
		  ,[SUMMABLE_CEDED_Sliding_Scale_Commission]
		  ,[SUMMABLE_CEDED_Sliding_Scale_Commission_USD]
		  ,[SUMMABLE_Overrider_Commission]
		  ,[SUMMABLE_Overrider_Commission_USD]
		  ,[SUMMABLE_CEDED_Overrider_Commission]
		  ,[SUMMABLE_CEDED_Overrider_Commission_USD]       
		  ,[SUMMABLE_Provisional_Commission]
		  ,[SUMMABLE_Provisional_Commission_USD]
		  ,[SUMMABLE_CEDED_Provisional_Commission]
		  ,[SUMMABLE_CEDED_Provisional_Commission_USD]
		  ,[SUMMABLE_Deferred_Commission]
		  ,[SUMMABLE_Deferred_Commission_USD]
		  ,[SUMMABLE_CEDED_Deferred_Commission]
		  ,[SUMMABLE_CEDED_Deferred_Commission_USD]
		  ,[SUMMABLE_int_funds_gross]
		  ,[SUMMABLE_int_funds_gross_USD]
		  ,[SUMMABLE_CEDED_int_funds_gross]
		  ,[SUMMABLE_CEDED_int_funds_gross_USD]
		  ,[SUMMABLE_int_funds_wth]
		  ,[SUMMABLE_int_funds_wth_USD]
		  ,[SUMMABLE_CEDED_int_funds_wth]
		  ,[SUMMABLE_CEDED_int_funds_wth_USD]
		  ,[SUMMABLE_fire_prevent_fund]
		  ,[SUMMABLE_fire_prevent_fund_USD]
		  ,[SUMMABLE_CEDED_fire_prevent_fund]
		  ,[SUMMABLE_CEDED_fire_prevent_fund_USD]
		  ,[SUMMABLE_xch_diff]
		  ,[SUMMABLE_xch_diff_USD]
		  ,[SUMMABLE_CEDED_xch_diff]
		  ,[SUMMABLE_CEDED_xch_diff_USD]
		  ,[SUMMABLE_NO_CLM_RBT]
		  ,[SUMMABLE_NO_CLM_RBT_USD]
		  ,[SUMMABLE_CEDED_NO_CLM_RBT]
		  ,[SUMMABLE_CEDED_NO_CLM_RBT_USD]
		  ,[SUMMABLE_funds_withheld_premium]
		  ,[SUMMABLE_funds_withheld_premium_USD]
		  ,[SUMMABLE_CEDED_funds_withheld_premium]
		  ,[SUMMABLE_CEDED_funds_withheld_premium_USD]
		  ,[SUMMABLE_funds_released_premium]
		  ,[SUMMABLE_funds_released_premium_USD]
		  ,[SUMMABLE_CEDED_funds_released_premium]
		  ,[SUMMABLE_CEDED_funds_released_premium_USD]
		  ,[SUMMABLE_funds_withheld_losses]
		  ,[SUMMABLE_funds_withheld_losses_USD]
		  ,[SUMMABLE_CEDED_funds_withheld_losses]
		  ,[SUMMABLE_CEDED_funds_withheld_losses_USD]
		  ,[SUMMABLE_deferred_withheld]
		  ,[SUMMABLE_deferred_withheld_USD]
		  ,[SUMMABLE_CEDED_deferred_withheld]
		  ,[SUMMABLE_CEDED_deferred_withheld_USD]
		  ,[SUMMABLE_deferred_released]
		  ,[SUMMABLE_deferred_released_USD]
		  ,[SUMMABLE_CEDED_deferred_released]
		  ,[SUMMABLE_CEDED_deferred_released_USD]
		  ,[SUMMABLE_UEPR]
		  ,[SUMMABLE_UEPR_USD]
		  ,[SUMMABLE_CEDED_UEPR]
		  ,[SUMMABLE_CEDED_UEPR_USD]
		  ,[SUMMABLE_UEPR_RPT_CURR1]
		  ,[SUMMABLE_UEPR_RPT_CURR2]
		  ,[SUMMABLE_DAC]
		  ,[SUMMABLE_DAC_USD]
		  ,[SUMMABLE_CEDED_DAC]
		  ,[SUMMABLE_CEDED_DAC_USD]
		  ,[SUMMABLE_DAC_RPT_CURR1]
		  ,[SUMMABLE_DAC_RPT_CURR2]
		  ,[SUMMABLE_FUNDS_RELEASED_LOSSES] 	 
          ,[SUMMABLE_FUNDS_RELEASED_LOSSES_USD]
		  ,[T7_CODE]
		  ,[T8_CODE]
		  ,[T9_CODE]
		  ,[MBU]
		  ,[L01]
		  ,[L02]
		  ,[L03]
		  ,[L04]
		  ,[L05]
		  ,[L06]
		  ,[L07]
		  ,[L08]
		  ,[L09]
		  ,[L10]
		  ,[GD1]
		  ,[RPTCURR1]
		  ,[RPTCURR1_CD]
		  ,[RPTCURR2]
		  ,[RPTCURR2_CD]
		  ,[InsurerCode]
		  ,[Financial_Lob]
		  ,[RPT_OFC_NM]
		  ,[RPT_OFF_NAME]
		  ,[ICP_CEDED_FLG]
		  ,[actuariallob]
		  ,[CLMS_PROCSS_CLM_DEPT]
		  ,[ID]
		  ,[Unmatched_Fields]
		  ,[topside_reg_date]
		  ,[Blended_Rate]
		  ,[MATCH_SOURCE_FLAG]
		  ,[TransactionTypeCode]
		  ,[TransactionTypeCategory]
		)
	SELECT	  [TREATY_NBR]											= stg.[TREATY_NBR]	
			, [UNDERWRITING_YEAR]									= stg.[UNDERWRITING_YEAR]
			, [CONTRACT_NBR]										= stg.[CONTRACT_NBR]
			, [CEDED_CONTRACT_NBR]									= stg.[CEDED_CONTRACT_NBR]
			, [SourceSystemKey]										= NULL
			, [Source]												= dc.PLCY_SRC
			, [TIRS_ORIG_CURR_CD]									= stg.[TIRS_ORIG_CURR_CD]
			, [TIRS_ORIG_CURR_NAME]									= stg.[TIRS_ORIG_CURR_NAME]
			, [lob_name]											= stg.[lob_name]
			, [reg_date]											= stg.[reg_date]
		    , [due_date]											= NULL /*'To be define'*/
		    , [acct_from_dt]										= NULL /*'To be define'*/
		    , [acct_to_dt]											= NULL /*'To be define'*/
		    , [doc_key]												= NULL
		    , [bill_company_cd]										= NULL
			, [aslob]												= stg.[aslob]
			, [solvency_II_regulatory_key]							= stg.[solvency_II_regulatory_key]
			, [AdjustmentType]										= stg.[AdjustmentType]
			, [TIRS_UW_ASSM_CEDED_NAME]								= stg.[TIRS_UW_ASSM_CEDED_NAME]
			, [SUMMABLE_WRTN_PREM_ALL_DOC_TYPES]					= stg.[SUMMABLE_WRTN_PREM_ALL_DOC_TYPES]
			, [SUMMABLE_WRTN_PREM_ALL_DOC_TYPES_USD]				= stg.[SUMMABLE_WRTN_PREM_ALL_DOC_TYPES_USD]
			, [SUMMABLE_CEDED_WRTN_PREM_ALL_DOC_TYPES]				= stg.[SUMMABLE_CEDED_WRTN_PREM_ALL_DOC_TYPES]
			, [SUMMABLE_CEDED_WRTN_PREM_ALL_DOC_TYPES_USD]			= stg.[SUMMABLE_CEDED_WRTN_PREM_ALL_DOC_TYPES_USD]
			, [SUMMABLE_WRTN_PREM_No_Claims_Rebate]					= stg.[SUMMABLE_WRTN_PREM_No_Claims_Rebate]
			, [SUMMABLE_WRTN_PREM_No_Claims_Rebate_USD]				= stg.[SUMMABLE_WRTN_PREM_No_Claims_Rebate_USD]
			, [SUMMABLE_CEDED_WRTN_PREM_No_Claims_Rebate]			= stg.[SUMMABLE_CEDED_WRTN_PREM_No_Claims_Rebate]
			, [SUMMABLE_CEDED_WRTN_PREM_No_Claims_Rebate_USD]		= stg.[SUMMABLE_CEDED_WRTN_PREM_No_Claims_Rebate_USD]
			, [SUMMABLE_WRTN_PREM_Reinstatement_Premium]			= stg.[SUMMABLE_WRTN_PREM_Reinstatement_Premium]
			, [SUMMABLE_WRTN_PREM_Reinstatement_Premium_USD]		= stg.[SUMMABLE_WRTN_PREM_Reinstatement_Premium_USD]
			, [SUMMABLE_CEDED_WRTN_PREM_Reinstatement_Premium]		= stg.[SUMMABLE_CEDED_WRTN_PREM_Reinstatement_Premium]
			, [SUMMABLE_CEDED_WRTN_PREM_Reinstatement_Premium_USD]	= stg.[SUMMABLE_CEDED_WRTN_PREM_Reinstatement_Premium_USD]
    		, [SUMMABLE_Brokerage]									= stg.[SUMMABLE_Brokerage]
			, [SUMMABLE_Brokerage_USD]								= stg.[SUMMABLE_Brokerage_USD]
			, [SUMMABLE_CEDED_Brokerage]							= stg.[SUMMABLE_CEDED_Brokerage]
			, [SUMMABLE_CEDED_Brokerage_USD]						= stg.[SUMMABLE_CEDED_Brokerage_USD]
			, [SUMMABLE_Commission]									= stg.[SUMMABLE_Commission]
			, [SUMMABLE_Commission_USD]								= stg.[SUMMABLE_Commission_USD]
			, [SUMMABLE_CEDED_Commission]							= stg.[SUMMABLE_CEDED_Commission]
			, [SUMMABLE_CEDED_Commission_USD]						= stg.[SUMMABLE_CEDED_Commission_USD]
			, [SUMMABLE_tax_nonrefund]								= stg.[SUMMABLE_tax_nonrefund]
			, [SUMMABLE_tax_nonrefund_USD]							= stg.[SUMMABLE_tax_nonrefund_USD]
			, [SUMMABLE_CEDED_tax_nonrefund]						= stg.[SUMMABLE_CEDED_tax_nonrefund]
			, [SUMMABLE_CEDED_tax_nonrefund_USD]					= stg.[SUMMABLE_CEDED_tax_nonrefund_USD]
			, [SUMMABLE_tax_on_prem]								= stg.[SUMMABLE_tax_on_prem]
			, [SUMMABLE_tax_on_prem_USD]							= stg.[SUMMABLE_tax_on_prem_USD]
			, [SUMMABLE_CEDED_tax_on_prem]							= stg.[SUMMABLE_CEDED_tax_on_prem]
			, [SUMMABLE_CEDED_tax_on_prem_USD]						= stg.[SUMMABLE_CEDED_tax_on_prem_USD]
			, [SUMMABLE_tax_refund]									= stg.[SUMMABLE_tax_refund]
			, [SUMMABLE_tax_refund_USD]								= stg.[SUMMABLE_tax_refund_USD]
			, [SUMMABLE_CEDED_tax_refund]							= stg.[SUMMABLE_CEDED_tax_refund]
			, [SUMMABLE_CEDED_tax_refund_USD]						= stg.[SUMMABLE_CEDED_tax_refund_USD]
			, [SUMMABLE_Profit_Commission_Paid]						= stg.[SUMMABLE_Profit_Commission_Paid]
			, [SUMMABLE_Profit_Commission_Paid_USD]					= stg.[SUMMABLE_Profit_Commission_Paid_USD]
			, [SUMMABLE_CEDED_Profit_Commission_Paid]				= stg.[SUMMABLE_CEDED_Profit_Commission_Paid]
			, [SUMMABLE_CEDED_Profit_Commission_Paid_USD]			= stg.[SUMMABLE_CEDED_Profit_Commission_Paid_USD]
			, [SUMMABLE_Sliding_Scale_Commission]					= stg.[SUMMABLE_Sliding_Scale_Commission]
			, [SUMMABLE_Sliding_Scale_Commission_USD]				= stg.[SUMMABLE_Sliding_Scale_Commission_USD]
			, [SUMMABLE_CEDED_Sliding_Scale_Commission]				= stg.[SUMMABLE_CEDED_Sliding_Scale_Commission]
			, [SUMMABLE_CEDED_Sliding_Scale_Commission_USD]			= stg.[SUMMABLE_CEDED_Sliding_Scale_Commission_USD]
			, [SUMMABLE_Overrider_Commission]						= stg.[SUMMABLE_Overrider_Commission]
			, [SUMMABLE_Overrider_Commission_USD]					= stg.[SUMMABLE_Overrider_Commission_USD]
			, [SUMMABLE_CEDED_Overrider_Commission]					= stg.[SUMMABLE_CEDED_Overrider_Commission]
			, [SUMMABLE_CEDED_Overrider_Commission_USD]				= stg.[SUMMABLE_CEDED_Overrider_Commission_USD]
			, [SUMMABLE_Provisional_Commission]						= stg.[SUMMABLE_Provisional_Commission]
			, [SUMMABLE_Provisional_Commission_USD]					= stg.[SUMMABLE_Provisional_Commission_USD]
			, [SUMMABLE_CEDED_Provisional_Commission]				= stg.[SUMMABLE_CEDED_Provisional_Commission]
			, [SUMMABLE_CEDED_Provisional_Commission_USD]			= stg.[SUMMABLE_CEDED_Provisional_Commission_USD]
			, [SUMMABLE_Deferred_Commission]						= stg.[SUMMABLE_Deferred_Commission]
			, [SUMMABLE_Deferred_Commission_USD]					= stg.[SUMMABLE_Deferred_Commission_USD]
			, [SUMMABLE_CEDED_Deferred_Commission]					= stg.[SUMMABLE_CEDED_Deferred_Commission]
			, [SUMMABLE_CEDED_Deferred_Commission_USD]				= stg.[SUMMABLE_CEDED_Deferred_Commission_USD]    
		    , [SUMMABLE_int_funds_gross]							= stg.[SUMMABLE_int_funds_gross]
			, [SUMMABLE_int_funds_gross_USD]						= stg.[SUMMABLE_int_funds_gross_USD]
			, [SUMMABLE_CEDED_int_funds_gross]						= stg.[SUMMABLE_CEDED_int_funds_gross]
			, [SUMMABLE_CEDED_int_funds_gross_USD]					= stg.[SUMMABLE_CEDED_int_funds_gross_USD]
			, [SUMMABLE_int_funds_wth]								= stg.[SUMMABLE_int_funds_wth]
			, [SUMMABLE_int_funds_wth_USD]							= stg.[SUMMABLE_int_funds_wth_USD]
			, [SUMMABLE_CEDED_int_funds_wth]						= stg.[SUMMABLE_CEDED_int_funds_wth]
			, [SUMMABLE_CEDED_int_funds_wth_USD]					= stg.[SUMMABLE_CEDED_int_funds_wth_USD]
			, [SUMMABLE_fire_prevent_fund]							= stg.[SUMMABLE_fire_prevent_fund]
			, [SUMMABLE_fire_prevent_fund_USD]						= stg.[SUMMABLE_fire_prevent_fund_USD]
			, [SUMMABLE_CEDED_fire_prevent_fund]					= stg.[SUMMABLE_CEDED_fire_prevent_fund]
			, [SUMMABLE_CEDED_fire_prevent_fund_USD]				= stg.[SUMMABLE_CEDED_fire_prevent_fund_USD]
			, [SUMMABLE_xch_diff]									= stg.[SUMMABLE_xch_diff]
			, [SUMMABLE_xch_diff_USD]								= stg.[SUMMABLE_xch_diff_USD]
			, [SUMMABLE_CEDED_xch_diff]								= stg.[SUMMABLE_CEDED_xch_diff]
			, [SUMMABLE_CEDED_xch_diff_USD]							= stg.[SUMMABLE_CEDED_xch_diff_USD]
			, [SUMMABLE_NO_CLM_RBT]									= stg.[SUMMABLE_NO_CLM_RBT]
			, [SUMMABLE_NO_CLM_RBT_USD]								= stg.[SUMMABLE_NO_CLM_RBT_USD]
			, [SUMMABLE_CEDED_NO_CLM_RBT]							= stg.[SUMMABLE_CEDED_NO_CLM_RBT]
			, [SUMMABLE_CEDED_NO_CLM_RBT_USD]						= stg.[SUMMABLE_CEDED_NO_CLM_RBT_USD]
			, [SUMMABLE_funds_withheld_premium]						= stg.[SUMMABLE_funds_withheld_premium]
			, [SUMMABLE_funds_withheld_premium_USD]					= stg.[SUMMABLE_funds_withheld_premium_USD]
			, [SUMMABLE_CEDED_funds_withheld_premium]				= stg.[SUMMABLE_CEDED_funds_withheld_premium]
			, [SUMMABLE_CEDED_funds_withheld_premium_USD]			= stg.[SUMMABLE_CEDED_funds_withheld_premium_USD]
			, [SUMMABLE_funds_released_premium]						= stg.[SUMMABLE_funds_released_premium]
			, [SUMMABLE_funds_released_premium_USD]					= stg.[SUMMABLE_funds_released_premium_USD]
			, [SUMMABLE_CEDED_funds_released_premium]				= stg.[SUMMABLE_CEDED_funds_released_premium]
			, [SUMMABLE_CEDED_funds_released_premium_USD]			= stg.[SUMMABLE_CEDED_funds_released_premium_USD]
			, [SUMMABLE_funds_withheld_losses]						= stg.[SUMMABLE_funds_withheld_losses]
			, [SUMMABLE_funds_withheld_losses_USD]					= stg.[SUMMABLE_funds_withheld_losses_USD]
			, [SUMMABLE_CEDED_funds_withheld_losses]				= stg.[SUMMABLE_CEDED_funds_withheld_losses]
			, [SUMMABLE_CEDED_funds_withheld_losses_USD]			= stg.[SUMMABLE_CEDED_funds_withheld_losses_USD]
			, [SUMMABLE_deferred_withheld]							= stg.[SUMMABLE_deferred_withheld]
			, [SUMMABLE_deferred_withheld_USD]						= stg.[SUMMABLE_deferred_withheld_USD]
			, [SUMMABLE_CEDED_deferred_withheld]					= stg.[SUMMABLE_CEDED_deferred_withheld]
			, [SUMMABLE_CEDED_deferred_withheld_USD]				= stg.[SUMMABLE_CEDED_deferred_withheld_USD]
			, [SUMMABLE_deferred_released]							= stg.[SUMMABLE_deferred_released]
			, [SUMMABLE_deferred_released_USD]						= stg.[SUMMABLE_deferred_released_USD]
			, [SUMMABLE_CEDED_deferred_released]					= stg.[SUMMABLE_CEDED_deferred_released]
			, [SUMMABLE_CEDED_deferred_released_USD]				= stg.[SUMMABLE_CEDED_deferred_released_USD]
			, [SUMMABLE_UEPR]										= stg.[SUMMABLE_UEPR]
			, [SUMMABLE_UEPR_USD]									= stg.[SUMMABLE_UEPR_USD]
			, [SUMMABLE_CEDED_UEPR]									= stg.[SUMMABLE_CEDED_UEPR]
			, [SUMMABLE_CEDED_UEPR_USD]								= stg.[SUMMABLE_CEDED_UEPR_USD]
			, [SUMMABLE_UEPR_RPT_CURR1]								= stg.[SUMMABLE_UEPR_RPT_CURR1]
			, [SUMMABLE_UEPR_RPT_CURR2]								= stg.[SUMMABLE_UEPR_RPT_CURR2]
			, [SUMMABLE_DAC]										= stg.[SUMMABLE_DAC]
			, [SUMMABLE_DAC_USD]									= stg.[SUMMABLE_DAC_USD]
			, [SUMMABLE_CEDED_DAC]									= stg.[SUMMABLE_CEDED_DAC]
			, [SUMMABLE_CEDED_DAC_USD]								= stg.[SUMMABLE_CEDED_DAC_USD]
			, [SUMMABLE_DAC_RPT_CURR1]								= stg.[SUMMABLE_DAC_RPT_CURR1]
			, [SUMMABLE_DAC_RPT_CURR2]								= stg.[SUMMABLE_DAC_RPT_CURR2]
			, [SUMMABLE_FUNDS_RELEASED_LOSSES]						= CONVERT(MONEY, 0)
			, [SUMMABLE_FUNDS_RELEASED_LOSSES_USD]					= CONVERT(MONEY, 0)
			, [T7_CODE]												= stg.[T7_CODE]
			, [T8_CODE]												= stg.[T8_CODE]
			, [T9_CODE]												= stg.[T9_CODE]
			, [MBU]													= stg.[MBU]
			, [L01]													= stg.[L01]
			, [L02]													= stg.[L02]
			, [L03]													= stg.[L03]
			, [L04]													= stg.[L04]
			, [L05]													= NULL
			, [L06]													= stg.[L06]
			, [L07]													= stg.[L07]
			, [L08]													= NULL
			, [L09]													= NULL
			, [L10]													= stg.[L10]
			, [GD1]													= stg.[GD1]
			, [RPTCURR1]											= stg.[RPTCURR1]
			, [RPTCURR1_CD]											= stg.[RPTCURR1_CD]
			, [RPTCURR2]											= stg.[RPTCURR2]
			, [RPTCURR2_CD]											= stg.[RPTCURR2_CD]
			, [InsurerCode]											= stg.[InsurerCode]
			, [Financial_Lob]										= stg.[Financial_Lob]
			, [RPT_OFC_NM]											= stg.[RPT_OFC_NM]
			, [RPT_OFF_NAME]										= stg.[RPT_OFC_NM]
			, [ICP_CEDED_FLG]										= stg.[ICP_CEDED_FLG]
			, [actuariallob]										= stg.[actuariallob]
			, [CLMS_PROCSS_CLM_DEPT]								= stg.[CLMS_PROCSS_CLM_DEPT]
			, [ID]													= NULL /*'To be define'*/
			, [Unmatched_Fields]									= NULL /*'To be define'*/
			, [topside_reg_date]									= stg.[topside_reg_date]
			, [Blended_Rate]										= stg.[Blended_Rate]
			, [MATCH_SOURCE_FLAG]									= NULL /*'To be define'*/
			, [TransactionTypeCode]									= 'Topside'
			, [TransactionTypeCategory]								= 'Topside'
		FROM [EDW_Staging].[assumed].[TopSides_UW_Staging] AS stg
		left join assumed.DimContract dc on dc.CONTRACT_NBR=stg.CONTRACT_NBR COLLATE DATABASE_DEFAULT
		AND dc.PLCY_SRC IN ('OPENBOX', 'TIRS')
	   WHERE stg.EndDate='9999-12-31'
		 AND EXISTS (SELECT *
					   FROM #ContractFilter	AS cf
					  WHERE cf.CONTRACT_NBR = stg.CONTRACT_NBR COLLATE DATABASE_DEFAULT )

		SET @v_RowCount = ROWCOUNT_BIG();
		INSERT INTO ##Timings_UW SELECT SYSDATETIME(), 'Inserted #UnderwritingLoadWide - TOPSIDES', @v_RowCount;
		--------------------------------------------------------------------------------	
		-- Lookup DimContractID
		--------------------------------------------------------------------------------
		UPDATE u
		   SET DimContractID = COALESCE(d.DimContractID, prm.DimContractUncoded) 
		  FROM #UnderwritingLoadWide	u
		 CROSS JOIN #Parameters			prm
		  LEFT JOIN EDW_PREPROD.assumed.DimContract d	ON  d.CONTRACT_NBR = u.CONTRACT_NBR
														AND COALESCE(d.PLCY_SRC, u.Source) = u.Source
														AND prm.ProcessingDate BETWEEN d.StartDate AND d.EndDate

		SET @v_RowCount = ROWCOUNT_BIG();
		INSERT INTO ##Timings_UW SELECT SYSDATETIME(), 'Looked up DimContractID', @v_RowCount;
        --------------------------------------------------------------------------------    
        -- Lookup Ceded_DimContractID
        --------------------------------------------------------------------------------
        UPDATE u
           SET Ceded_DimContractID = CASE
                                        WHEN NULLIF(u.CEDED_CONTRACT_NBR, '') IS NULL
                                        THEN prm.DimContractNA
                                        ELSE COALESCE(d.DimContractID, prm.DimContractUncoded) END
          FROM #UnderwritingLoadWide    u
         CROSS JOIN #Parameters         prm
          LEFT JOIN EDW_PREPROD.assumed.DimContract d   ON d.CONTRACT_NBR = u.CEDED_CONTRACT_NBR
                                                        AND COALESCE(d.PLCY_SRC, u.Source) = u.Source
                                                        AND prm.ProcessingDate BETWEEN d.StartDate AND d.EndDate
 

 		SET @v_RowCount = ROWCOUNT_BIG();
		INSERT INTO ##Timings_UW SELECT SYSDATETIME(), 'Looked up Ceded_DimContractID', @v_RowCount;
		--------------------------------------------------------------------------------	
		-- Lookup Intended_DimAccountingPeriodID
		--------------------------------------------------------------------------------
		UPDATE u
		   SET Intended_DimAccountingPeriodID = COALESCE(d.DimAccountingPeriodID, prm.DimAccountingPeriodUncoded)
		  FROM #UnderwritingLoadWide	u
		 CROSS JOIN #Parameters			prm
		 LEFT JOIN EDW_PREPROD.assumed.DimAccountingPeriod d	ON  d.AccountingPeriodDate = u.reg_date
																AND prm.ProcessingDate BETWEEN d.StartDate AND d.EndDate

 		SET @v_RowCount = ROWCOUNT_BIG();
		INSERT INTO ##Timings_UW SELECT SYSDATETIME(), 'Looked up DimAccountingPeriodID', @v_RowCount;
		--------------------------------------------------------------------------------	
		-- Lookup Intended_DimAccountingID
		--------------------------------------------------------------------------------
		UPDATE u
		   SET Intended_DimAccountingID = COALESCE(d.DimAccountingID, prm.DimAccountingUncoded)
		  FROM #UnderwritingLoadWide	u
		 CROSS JOIN #Parameters			prm
		  LEFT JOIN EDW_PREPROD.assumed.DimAccounting d		ON  COALESCE(d.ActuarialLob, '%^&')	= COALESCE(NULLIF(u.ActuarialLob, ''), '%^&')
															AND COALESCE(d.RPT_OFF_NAME, '%^&') = COALESCE(NULLIF(u.RPT_OFF_NAME, ''), '%^&')
															AND COALESCE(d.InsurerCode, '%^&')	= COALESCE(NULLIF(u.InsurerCode, ''), '%^&')
															AND COALESCE(d.FINANCIAL_LOB, '%^&')= COALESCE(NULLIF(u.FINANCIAL_LOB, ''), '%^&')
															AND COALESCE(d.T7_CODE, '%^&')		= COALESCE(NULLIF(u.T7_CODE, ''), '%^&')
															AND COALESCE(d.T8_CODE, '%^&')		= COALESCE(NULLIF(u.T8_CODE, ''), '%^&')
															AND COALESCE(d.T9_CODE, '%^&')		= COALESCE(NULLIF(u.T9_CODE, ''), '%^&')
															AND COALESCE(d.CLMS_PROCSS_CLM_DEPT, '%^&') = COALESCE(NULLIF(u.CLMS_PROCSS_CLM_DEPT, ''), '%^&')
															AND COALESCE(d.ICP_CEDED_FLG, '%^&')= COALESCE(NULLIF(u.ICP_CEDED_FLG, ''), '%^&')
															AND COALESCE(d.MBU, '%^&')			= COALESCE(NULLIF(u.MBU, ''), '%^&')
															AND COALESCE(d.L01, '%^&')			= COALESCE(NULLIF(u.L01, ''), '%^&')
															AND COALESCE(d.L02, '%^&')			= COALESCE(NULLIF(u.L02, ''), '%^&')
															AND COALESCE(d.L03, '%^&')			= COALESCE(NULLIF(u.L03, ''), '%^&')
															AND COALESCE(d.L06, '%^&')			= COALESCE(NULLIF(u.L06, ''), '%^&')
															AND COALESCE(d.L07, '%^&')			= COALESCE(NULLIF(u.L07, ''), '%^&')
															AND COALESCE(d.L10, '%^&')			= COALESCE(NULLIF(u.L10, ''), '%^&')
															AND COALESCE(d.GD1, '%^&')			= COALESCE(NULLIF(CASE WHEN u.GD1 = 'TIRS ADJ' THEN 'TIRS' ELSE u.GD1 END, ''), '%^&')
															AND COALESCE(d.RPTCURR1_CD, '%^&')	= COALESCE(NULLIF(u.RPTCURR1_CD, ''), '%^&')
															AND COALESCE(d.RPTCURR2_CD, '%^&')	= COALESCE(NULLIF(u.RPTCURR2_CD, ''), '%^&')
															AND COALESCE(d.ASLOB, '%^&')		= COALESCE(NULLIF(u.ASLOB, ''), '%^&')
															AND prm.ProcessingDate BETWEEN d.StartDate AND d.EndDate

 		SET @v_RowCount = ROWCOUNT_BIG();
		INSERT INTO ##Timings_UW SELECT SYSDATETIME(), 'Looked up Intended_DimAccountingID', @v_RowCount;
		--------------------------------------------------------------------------------	
		-- Lookup DimAccountingID
		--------------------------------------------------------------------------------
		UPDATE u
		   SET DimAccountingID = COALESCE(d.DimAccountingID, prm.DimAccountingUncoded)
		  FROM #UnderwritingLoadWide	u
		 CROSS JOIN #Parameters			prm
		  LEFT JOIN EDW_PREPROD.assumed.DimAccounting d	ON  COALESCE(d.ActuarialLob, '%^&')		= COALESCE(NULLIF(u.ActuarialLob, ''), '%^&')
														AND COALESCE(d.RPT_OFF_NAME, '%^&')		= COALESCE(NULLIF(u.RPT_OFF_NAME, ''), '%^&')
														AND COALESCE(d.InsurerCode, '%^&')		= COALESCE(NULLIF(u.InsurerCode, ''), '%^&')
														AND COALESCE(d.FINANCIAL_LOB, '%^&')	= COALESCE(NULLIF(u.FINANCIAL_LOB, ''), '%^&')
														AND COALESCE(d.T7_CODE, '%^&')			= COALESCE(NULLIF(u.T7_CODE, ''), '%^&')
														AND COALESCE(d.T8_CODE, '%^&')			= COALESCE(NULLIF(u.T8_CODE, ''), '%^&')
														AND COALESCE(d.T9_CODE, '%^&')			= COALESCE(NULLIF(u.T9_CODE, ''), '%^&')
														AND COALESCE(d.CLMS_PROCSS_CLM_DEPT, '%^&') = COALESCE(NULLIF(u.CLMS_PROCSS_CLM_DEPT, ''), '%^&')
														AND COALESCE(d.ICP_CEDED_FLG, '%^&')	= COALESCE(NULLIF(u.ICP_CEDED_FLG, ''), '%^&')
														AND COALESCE(d.MBU, '%^&')				= COALESCE(NULLIF(u.MBU, ''), '%^&')
														AND COALESCE(d.L01, '%^&')				= COALESCE(NULLIF(u.L01, ''), '%^&')
														AND COALESCE(d.L02, '%^&')				= COALESCE(NULLIF(u.L02, ''), '%^&')
														AND COALESCE(d.L03, '%^&')				= COALESCE(NULLIF(u.L03, ''), '%^&')
														AND COALESCE(d.L06, '%^&')				= COALESCE(NULLIF(u.L06, ''), '%^&')
														AND COALESCE(d.L07, '%^&')				= COALESCE(NULLIF(u.L07, ''), '%^&')
														AND COALESCE(d.L10, '%^&')				= COALESCE(NULLIF(u.L10, ''), '%^&')
														AND COALESCE(d.GD1, '%^&')				= COALESCE(NULLIF( IIF(/*u.AdjustedTCodeL04 = 1 AND*/ u.GD1 = 'TIRS', 'TIRS ADJ', u.GD1), ''), '%^&')
														AND COALESCE(d.RPTCURR1_CD, '%^&')		= COALESCE(NULLIF(u.RPTCURR1_CD, ''), '%^&')
														AND COALESCE(d.RPTCURR2_CD, '%^&')		= COALESCE(NULLIF(u.RPTCURR2_CD, ''), '%^&')
														AND COALESCE(d.ASLOB, '%^&')			= COALESCE(NULLIF(u.ASLOB, ''), '%^&')
														AND prm.ProcessingDate BETWEEN d.StartDate AND d.EndDate

		SET @v_RowCount = ROWCOUNT_BIG();
		INSERT INTO ##Timings_UW SELECT SYSDATETIME(), 'Looked up DimAccountingID', @v_RowCount;
		--------------------------------------------------------------------------------
		-- Lookup DimTransactionTypeID
		--------------------------------------------------------------------------------
		UPDATE u
		   SET DimTransactionTypeID = CASE WHEN u.TransactionTypeCode IS NULL THEN prm.DimTransactionTypeNA ELSE COALESCE(d.DimTransactionTypeID, prm.DimTransactionTypeUncoded) END
		  FROM #UnderwritingLoadWide	u
		 CROSS JOIN #Parameters			prm
		LEFT JOIN EDW_PREPROD.assumed.DimTransactionType d	ON  d.TransactionTypeCode = u.TransactionTypeCode
															AND d.Category = u.TransactionTypeCategory
															AND (d.Source = u.Source OR d.Source NOT IN ('TIRS', 'OPENBOX'))
															AND prm.ProcessingDate BETWEEN d.StartDate AND d.EndDate

		SET @v_RowCount = ROWCOUNT_BIG();
		INSERT INTO ##Timings_UW SELECT SYSDATETIME(), 'Looked up DimTransactionTypeID', @v_RowCount;
		--------------------------------------------------------------------------------	
		-- Lookup DimLineOfBusinessID
		--------------------------------------------------------------------------------
		UPDATE u
		   SET DimLineOfBusinessID = COALESCE(d.DimLineOfBusinessID, prm.DimLineOfBusinessUncoded)
		  FROM #UnderwritingLoadWide	u
		 CROSS JOIN #Parameters			prm
		  LEFT JOIN EDW_PREPROD.assumed.DimLineOfBusiness d		ON d.LineOfBusinessName = u.lob_name
																AND d.solvency_II_regulatory_key = u.solvency_II_regulatory_key
																AND prm.ProcessingDate BETWEEN d.StartDate AND d.EndDate

		SET @v_RowCount = ROWCOUNT_BIG();
		INSERT INTO ##Timings_UW SELECT SYSDATETIME(), 'Looked up DimLineOfBusiness', @v_RowCount;
		--------------------------------------------------------------------------------	
		-- Lookup DimAdjustmentType
		--------------------------------------------------------------------------------
		UPDATE u
		   SET DimAdjustmentTypeID = COALESCE(d.DimAdjustmentTypeID, prm.DimAdjustmentTypeUncoded)
		  FROM #UnderwritingLoadWide	u
		 CROSS JOIN #Parameters			prm
		  LEFT JOIN EDW_PREPROD.assumed.DimAdjustmentType d	ON d.AdjustmentType = u.adjustmenttype
															AND prm.ProcessingDate BETWEEN d.StartDate AND d.EndDate

		SET @v_RowCount = ROWCOUNT_BIG();
		INSERT INTO ##Timings_UW SELECT SYSDATETIME(), 'Looked up DimAdjustmentType', @v_RowCount;
		--------------------------------------------------------------------------------	
		-- Lookup DimLineOfBusiness
		--------------------------------------------------------------------------------
		UPDATE u
		   SET DimLineOfBusinessID = COALESCE(d.DimLineOfBusinessID, prm.DimLineOfBusinessUncoded)
		  FROM #UnderwritingLoadWide	u
		 CROSS JOIN #Parameters			prm
		 LEFT JOIN EDW_PREPROD.assumed.DimLineOfBusiness d	ON d.LineOfBusinessName	= u.lob_name
															AND COALESCE(d.solvency_II_regulatory_key, -1) = COALESCE(u.solvency_II_regulatory_key, -1)
															AND prm.ProcessingDate BETWEEN d.StartDate AND d.EndDate

		SET @v_RowCount = ROWCOUNT_BIG();
		INSERT INTO ##Timings_UW SELECT SYSDATETIME(), 'Looked up DimLineOfBusiness', @v_RowCount;
		--------------------------------------------------------------------------------	
		-- Lookup DimDueDateID
		--------------------------------------------------------------------------------	
		UPDATE u
		   SET DimDueDateID = CASE WHEN u.Due_Date IS NULL THEN prm.DimDateNA ELSE COALESCE(d.DimDateID, prm.DimDateUncoded) END
		  FROM #UnderwritingLoadWide	u
		 CROSS JOIN #Parameters			prm
		  LEFT JOIN EDW_PREPROD.assumed.DimDate d	ON d.Date = u.Due_Date
														AND prm.ProcessingDate BETWEEN d.StartDate AND d.EndDate

		SET @v_RowCount = ROWCOUNT_BIG();
		INSERT INTO ##Timings_UW SELECT SYSDATETIME(), 'Looked up DimDueDateID', @v_RowCount;
		--------------------------------------------------------------------------------	
		-- Lookup DimFromDateID and DimToDateID
		--------------------------------------------------------------------------------	
		UPDATE u
		   SET DimFromDateID	= CASE WHEN u.acct_from_dt IS NULL THEN prm.DimDateNA ELSE COALESCE(d.DimDateID, prm.DimDateUncoded) END
			  ,DimToDateID		= CASE WHEN u.acct_to_dt   IS NULL THEN prm.DimDateNA ELSE COALESCE(dd.DimDateID, prm.DimDateUncoded) END
		  FROM #UnderwritingLoadWide	u
		 CROSS JOIN #Parameters			prm
		  LEFT JOIN EDW_PREPROD.assumed.DimDate d	ON d.Date = u.acct_from_dt
														AND prm.ProcessingDate BETWEEN d.StartDate AND d.EndDate
          LEFT JOIN EDW_PREPROD.assumed.DimDate dd	ON dd.Date = u.acct_to_dt
														AND prm.ProcessingDate BETWEEN dd.StartDate AND dd.EndDate

		SET @v_RowCount = ROWCOUNT_BIG();
		INSERT INTO ##Timings_UW SELECT SYSDATETIME(), 'Looked up DimFromDateID and DimToDateID', @v_RowCount;
		--------------------------------------------------------------------------------	
		-- Lookup Orig_DimCurrencyID
		--------------------------------------------------------------------------------	
		UPDATE u
		   SET Orig_DimCurrencyID = COALESCE(d.DimCurrencyID, prm.DimCurrencyUncoded)
		  FROM #UnderwritingLoadWide	u
		 CROSS JOIN #Parameters			prm
		  LEFT JOIN EDW_PREPROD.assumed.DimCurrency d	ON  u.TIRS_ORIG_CURR_CD in (d.TIRS_CURR_CD, ISOCurrencyCode)
														AND prm.ProcessingDate BETWEEN d.StartDate AND d.EndDate

		SET @v_RowCount = ROWCOUNT_BIG();
		INSERT INTO ##Timings_UW SELECT SYSDATETIME(), 'Looked up Orig_DimCurrency', @v_RowCount;
		--------------------------------------------------------------------------------	
		-- Lookup OrigRpt1_DimExchangeRate
		--------------------------------------------------------------------------------
		UPDATE u
		   SET OrigRpt1_DimExchangeRateID = CASE WHEN NULLIF(u.RPTCURR1_CD, '') IS NULL THEN prm.DimExchangeRateNA ELSE COALESCE(d.DimExchangeRateID, prm.DimExchangeRateUncoded) END
		  FROM #UnderwritingLoadWide	u
		 CROSS JOIN #Parameters			prm
		 LEFT JOIN EDW_PREPROD.assumed.DimExchangeRate d	ON  IIF(TRY_CAST(u.TIRS_ORIG_CURR_CD AS INT) IS NULL, d.FromCurrency, d.TIRSFromCurrency) = u.TIRS_ORIG_CURR_CD
															AND d.ToCurrency	= u.RPTCURR1_CD
															AND d.AccountingPeriodDate = u.reg_date
															AND prm.ProcessingDate BETWEEN d.StartDate AND d.EndDate

		SET @v_RowCount = ROWCOUNT_BIG();
		INSERT INTO ##Timings_UW SELECT SYSDATETIME(), 'Looked up OrigRpt1_DimExchangeRate', @v_RowCount;
		--------------------------------------------------------------------------------	
		-- Lookup OrigRpt2_DimExchangeRate
		--------------------------------------------------------------------------------	
		UPDATE u
		   SET OrigRpt2_DimExchangeRateID = CASE WHEN NULLIF(u.RPTCURR2_CD, '') IS NULL THEN prm.DimExchangeRateNA ELSE COALESCE(d.DimExchangeRateID, prm.DimExchangeRateUncoded) END
		  FROM #UnderwritingLoadWide	u
		 CROSS JOIN #Parameters			prm
		  LEFT JOIN EDW_PREPROD.assumed.DimExchangeRate d	ON  IIF(TRY_CAST(u.TIRS_ORIG_CURR_CD AS INT) IS NULL, d.FromCurrency, d.TIRSFromCurrency) = u.TIRS_ORIG_CURR_CD
															AND d.ToCurrency	= u.RPTCURR2_CD
															AND d.AccountingPeriodDate = u.reg_date
															AND prm.ProcessingDate BETWEEN d.StartDate AND d.EndDate

		SET @v_RowCount = ROWCOUNT_BIG();
		INSERT INTO ##Timings_UW SELECT SYSDATETIME(), 'Looked up OrigRpt2_DimExchangeRate', @v_RowCount;
		--------------------------------------------------------------------------------	
		-- Lookup DimDocument
		--------------------------------------------------------------------------------
		UPDATE u
		   SET DimDocumentID = CASE WHEN u.doc_key IS NULL THEN prm.DimDocumentNA ELSE COALESCE(d.DimDocumentID, prm.DimDocumentUncoded) END		   
		  FROM #UnderwritingLoadWide	u
		 CROSS JOIN #Parameters			prm
		 LEFT  JOIN EDW_PREPROD.assumed.DimDocument d	ON  d.doc_key = u.doc_key
			AND d.SourceSysKey = u.SourceID
														AND prm.ProcessingDate BETWEEN d.StartDate AND d.EndDate

		SET @v_RowCount = ROWCOUNT_BIG();
		INSERT INTO ##Timings_UW SELECT SYSDATETIME(), 'Looked up DimDocument', @v_RowCount;
		--------------------------------------------------------------------------------	
		-- Lookup DimBilling
		--------------------------------------------------------------------------------
		UPDATE u
		   SET DimBillingID = CASE WHEN u.bill_company_cd IS NULL THEN prm.DimBillingNA ELSE COALESCE(d.DimBillingID, prm.DimBillingUncoded) END		   
		  FROM #UnderwritingLoadWide	u
		 CROSS JOIN #Parameters			prm
		 LEFT  JOIN EDW_PREPROD.assumed.DimBilling d	ON  d.bill_company_cd = u.bill_company_cd
														AND(
															(d.SourceSysKey= 4  AND U.Source='TIRS')
														 OR (d.SourceSysKey= 1  AND U.Source='OPENBOX')
														)
														AND prm.ProcessingDate BETWEEN d.StartDate AND d.EndDate

		SET @v_RowCount = ROWCOUNT_BIG();
		INSERT INTO ##Timings_UW SELECT SYSDATETIME(), 'Looked up DimBilling', @v_RowCount;

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
	    			SELECT
						tph.Contract_NBR
	    				,tph.Participant_Key
	    				,tph.Participant
	    				,CumulativeCessionShare = SUM(tph.CessionPercent) OVER (PARTITION BY tph.Contract_NBR ORDER BY tph.Participant_Key)
	    				,TotalCessionShare		= SUM(tph.CessionPercent) OVER (PARTITION BY tph.Contract_NBR)
	    			 FROM dbo.TIRS_PARTICIPANT_HISTORY tph
	    			WHERE tph.END_DATE = '9999-12-31'
	    		) x
	    LEFT JOIN assumed.DimParticipant	dp	ON  dp.Participant_key = x.Participant_Key
									    		AND dp.EndDate = '9999-12-31'
	    
		SET @v_RowCount = ROWCOUNT_BIG();
	    INSERT INTO ##Timings_UW SELECT SYSDATETIME(), 'Created #MapParticipant', @v_RowCount;	

		--------------------------------------------------------------------------------	
		-- #UnderwritingLoad - create the new table structure
		--------------------------------------------------------------------------------	
		DROP TABLE IF EXISTS #UnderwritingLoad

		SELECT
			 UnderwritingLoadWideID = MAX(w.UnderwritingLoadWideID)
			,w.SourceSystemKey
			,w.DimContractID
			,w.Ceded_DimContractID
			,w.Intended_DimAccountingPeriodID
			,w.Intended_DimAccountingID
			,w.DimAccountingID
			,w.DimTransactionTypeID
			,w.DimAdjustmentTypeID
			,w.Orig_DimCurrencyID
			,w.DimLineOfBusinessID
			,w.DimDueDateID
			,w.DimFromDateID
			,w.DimToDateID
			,w.OrigRpt1_DimExchangeRateID
			,w.OrigRpt2_DimExchangeRateID
			,w.DimDocumentID
			,w.DimBillingID
			,DimParticipantID	= COALESCE(mp.DimParticipantID, prm.DimParticipantNA)
			,DimMeasureID		= COALESCE(m.DimMeasureID, prm.DimMeasureUncoded)
			,Amount				= SUM(CASE  WHEN mp.CumulativeCessionShare IS NULL 
											THEN ROUND(x.Amount, COALESCE(cdp.DecPlaces, 2)) 
											ELSE ROUND(x.Amount * mp.CumulativeCessionShare / mp.TotalCessionShare, COALESCE(cdp.DecPlaces, 2)) 
											   - ROUND(x.Amount * mp.PreviousCumuluativeCessionShare / mp.TotalCessionShare, COALESCE(cdp.DecPlaces, 2)) END)
					  
		    ,AmountUSD			= SUM(CASE  WHEN mp.CumulativeCessionShare IS NULL 
											THEN ROUND(x.AmountUSD, 2) 
											ELSE ROUND(x.AmountUSD * mp.CumulativeCessionShare / mp.TotalCessionShare, 2) 
											   - ROUND(x.AmountUSD * mp.PreviousCumuluativeCessionShare / mp.TotalCessionShare, 2) END)
		    ,CreatedDate		= prm.ProcessingDate

		 INTO #UnderwritingLoad
		 FROM #UnderwritingLoadWide	w
		CROSS JOIN #Parameters		prm
		 LEFT JOIN EDW_PREPROD.assumed.DimCurrency			 c		ON  c.DimCurrencyID = w.Orig_DimCurrencyID
																	AND prm.ProcessingDate BETWEEN c.StartDate AND c.EndDate
		 LEFT JOIN EDW_Staging.assumed.CurrencyDecimalPlaces cdp	ON  cdp.CurrencyCode = c.ISOCurrencyCode COLLATE DATABASE_DEFAULT
																	AND prm.ProcessingDate BETWEEN cdp.StartDate AND cdp.EndDate
		CROSS APPLY (
			SELECT z.Business
				,z.CurrencyType
				,z.MeasureType
				,z.MeasureCode
				,z.Amount
				,z.AmountUSD
			FROM (
				VALUES(   'RI Assumed', 'Original', 'Premium'			,'SUMMABLE_WRTN_PREM_ALL_DOC_TYPES'			,w.SUMMABLE_WRTN_PREM_ALL_DOC_TYPES			,w.SUMMABLE_WRTN_PREM_ALL_DOC_TYPES_USD)
						,('RI Assumed', 'Original', 'Not used Atm '		,'SUMMABLE_WRTN_PREM_No_Claims_Rebate'		,w.SUMMABLE_WRTN_PREM_No_Claims_Rebate		,w.SUMMABLE_WRTN_PREM_No_Claims_Rebate_USD)
						,('RI Assumed', 'Original', 'Reinstatement Premium'	,'SUMMABLE_WRTN_PREM_Reinstatement_Premium'	,w.SUMMABLE_WRTN_PREM_Reinstatement_Premium	,w.SUMMABLE_WRTN_PREM_Reinstatement_Premium_USD)
						,('RI Assumed', 'Original', 'UEPR'				,'SUMMABLE_UEPR'							,w.SUMMABLE_UEPR							,w.SUMMABLE_UEPR_USD)
						,('RI Assumed', 'Original', 'Brokerage'			,'SUMMABLE_Brokerage'						,w.SUMMABLE_Brokerage						,w.SUMMABLE_Brokerage_USD)
						,('RI Assumed', 'Original', 'Commission'		,'SUMMABLE_Commission'						,w.SUMMABLE_Commission						,w.SUMMABLE_Commission_USD)
						,('RI Assumed', 'Original', 'Tax'				,'SUMMABLE_tax_nonrefund'					,w.SUMMABLE_tax_nonrefund					,w.SUMMABLE_tax_nonrefund_USD)
						,('RI Assumed', 'Original', 'Tax'				,'SUMMABLE_tax_on_prem'						,w.SUMMABLE_tax_on_prem						,w.SUMMABLE_tax_on_prem_USD)
						,('RI Assumed', 'Original', 'Tax'				,'SUMMABLE_Tax_refund'						,w.SUMMABLE_Tax_refund						,w.SUMMABLE_Tax_refund_USD)
						,('RI Assumed', 'Original', 'DAC'				,'SUMMABLE_DAC'								,w.SUMMABLE_DAC								,w.SUMMABLE_DAC_USD)
						,('RI Assumed', 'Original', 'Profit Commission Payable','SUMMABLE_Profit_Commission_Paid'	,w.SUMMABLE_Profit_Commission_Paid			,w.SUMMABLE_Profit_Commission_Paid_USD)
						,('RI Assumed', 'Original', 'Commission'		,'SUMMABLE_Sliding_Scale_Commission'		,w.SUMMABLE_Sliding_Scale_Commission		,w.SUMMABLE_Sliding_Scale_Commission_USD)
						,('RI Assumed', 'Original', 'Commission'		,'SUMMABLE_Overrider_Commission'			,w.SUMMABLE_Overrider_Commission			,w.SUMMABLE_Overrider_Commission_USD)
						,('RI Assumed', 'Original', 'Commission'		,'SUMMABLE_Provisional_Commission'			,w.SUMMABLE_Provisional_Commission			,w.SUMMABLE_Provisional_Commission_USD)
						,('RI Assumed', 'Original', 'Commission'		,'SUMMABLE_Deferred_Commission'				,w.SUMMABLE_Deferred_Commission				,w.SUMMABLE_Deferred_Commission_USD)
						,('RI Assumed', 'Original', 'Interest'			,'SUMMABLE_int_funds_gross'					,w.SUMMABLE_int_funds_gross					,w.SUMMABLE_int_funds_gross_USD)
						,('RI Assumed', 'Original', 'Interest'			,'SUMMABLE_int_funds_wth'					,w.SUMMABLE_int_funds_wth					,w.SUMMABLE_int_funds_wth_USD)
						,('RI Assumed', 'Original', 'Brokerage'			,'SUMMABLE_fire_prevent_fund'				,w.SUMMABLE_fire_prevent_fund				,w.SUMMABLE_fire_prevent_fund_USD)
						,('RI Assumed', 'Original', 'Brokerage'			,'SUMMABLE_xch_diff'						,w.SUMMABLE_xch_diff						,w.SUMMABLE_xch_diff_USD)
						,('RI Assumed', 'Original', 'Premium'			,'SUMMABLE_NO_CLM_RBT'						,w.SUMMABLE_NO_CLM_RBT						,w.SUMMABLE_NO_CLM_RBT_USD)
						,('RI Assumed', 'Original', 'FundHeld_Premium'	,'SUMMABLE_funds_withheld_premium'			,w.SUMMABLE_funds_withheld_premium			,w.SUMMABLE_funds_withheld_premium_USD)
						,('RI Assumed', 'Original', 'FundHeld_Premium'	,'SUMMABLE_funds_released_premium'			,w.SUMMABLE_funds_released_premium			,w.SUMMABLE_funds_released_premium_USD)
						,('RI Assumed', 'Original', 'FundHeld_Premium'	,'SUMMABLE_funds_withheld_losses'			,w.SUMMABLE_funds_withheld_losses			,w.SUMMABLE_funds_withheld_losses_USD)
						,('RI Assumed', 'Original', 'FundHeld_Premium'	,'SUMMABLE_deferred_withheld'				,w.SUMMABLE_deferred_withheld				,w.SUMMABLE_deferred_withheld_USD)
						,('RI Assumed', 'Original', 'FundHeld_Premium'	,'SUMMABLE_deferred_released'				,w.SUMMABLE_deferred_released				,w.SUMMABLE_deferred_released_USD)
						,('RI Assumed', 'Original', 'Unknown'	        ,'SUMMABLE_UEPR_RPT_CURR1'		            ,w.SUMMABLE_UEPR_RPT_CURR1		            ,CASE WHEN NULLIF(w.RPTCURR1_CD, '') IS NOT NULL THEN w.SUMMABLE_UEPR_USD ELSE 0 END)
						,('RI Assumed', 'Original', 'Unknown'	        ,'SUMMABLE_UEPR_RPT_CURR2'		            ,w.SUMMABLE_UEPR_RPT_CURR2		            ,CASE WHEN NULLIF(w.RPTCURR2_CD, '') IS NOT NULL THEN w.SUMMABLE_UEPR_USD ELSE 0 END)
						,('RI Assumed', 'Original', 'Unknown'	        ,'SUMMABLE_DAC_RPT_CURR1'			        ,w.SUMMABLE_DAC_RPT_CURR1			        ,CASE WHEN NULLIF(w.RPTCURR1_CD, '') IS NOT NULL THEN w.SUMMABLE_DAC_USD ELSE 0 END)
						,('RI Assumed', 'Original', 'Unknown'	        ,'SUMMABLE_DAC_RPT_CURR2'			        ,w.SUMMABLE_DAC_RPT_CURR2			        ,CASE WHEN NULLIF(w.RPTCURR2_CD, '') IS NOT NULL THEN w.SUMMABLE_DAC_USD ELSE 0 END)
						,('RI Assumed', 'Original', 'Funds Released Losses'	,'SUMMABLE_FUNDS_RELEASED_LOSSES'		,w.SUMMABLE_FUNDS_RELEASED_LOSSES			,w.SUMMABLE_FUNDS_RELEASED_LOSSES_USD)						
						-----------------------------------------------------------------------------------------------------------------------------------------------------------
						,('RI Ceded', 'Original', 'Premium'				,'SUMMABLE_CEDED_WRTN_PREM_ALL_DOC_TYPES'	,w.SUMMABLE_CEDED_WRTN_PREM_ALL_DOC_TYPES			,w.SUMMABLE_CEDED_WRTN_PREM_ALL_DOC_TYPES_USD)
						,('RI Ceded', 'Original', 'Not used Atm '		,'SUMMABLE_CEDED_WRTN_PREM_No_Claims_Rebate',w.SUMMABLE_CEDED_WRTN_PREM_No_Claims_Rebate		,w.SUMMABLE_CEDED_WRTN_PREM_No_Claims_Rebate_USD)
						,('RI Ceded', 'Original', 'Reinstatement Premium','SUMMABLE_CEDED_WRTN_PREM_Reinstatement_Premium',w.SUMMABLE_CEDED_WRTN_PREM_Reinstatement_Premium	,w.SUMMABLE_CEDED_WRTN_PREM_Reinstatement_Premium_USD)
						,('RI Ceded', 'Original', 'UEPR'				,'SUMMABLE_CEDED_UEPR'						,w.SUMMABLE_CEDED_UEPR								,w.SUMMABLE_CEDED_UEPR_USD)
						,('RI Ceded', 'Original', 'Brokerage'			,'SUMMABLE_CEDED_Brokerage'					,w.SUMMABLE_CEDED_Brokerage							,w.SUMMABLE_CEDED_Brokerage_USD)
						,('RI Ceded', 'Original', 'Commission'			,'SUMMABLE_CEDED_Commission'				,w.SUMMABLE_CEDED_Commission						,w.SUMMABLE_CEDED_Commission_USD)
						,('RI Ceded', 'Original', 'Tax'					,'SUMMABLE_CEDED_tax_nonrefund'				,w.SUMMABLE_CEDED_tax_nonrefund						,w.SUMMABLE_CEDED_tax_nonrefund_USD)
						,('RI Ceded', 'Original', 'Tax'					,'SUMMABLE_CEDED_tax_on_prem'				,w.SUMMABLE_CEDED_tax_on_prem						,w.SUMMABLE_CEDED_tax_on_prem_USD)
						,('RI Ceded', 'Original', 'Tax'					,'SUMMABLE_CEDED_Tax_refund'				,w.SUMMABLE_CEDED_Tax_refund						,w.SUMMABLE_CEDED_Tax_refund_USD)
						,('RI Ceded', 'Original', 'DAC'					,'SUMMABLE_CEDED_DAC'						,w.SUMMABLE_CEDED_DAC								,w.SUMMABLE_CEDED_DAC_USD)
						,('RI Ceded', 'Original', 'Profit Commission Payable','SUMMABLE_CEDED_Profit_Commission_Paid',w.SUMMABLE_CEDED_Profit_Commission_Paid			,w.SUMMABLE_CEDED_Profit_Commission_Paid_USD)
						,('RI Ceded', 'Original', 'Commission'			,'SUMMABLE_CEDED_Sliding_Scale_Commission'	,w.SUMMABLE_CEDED_Sliding_Scale_Commission			,w.SUMMABLE_CEDED_Sliding_Scale_Commission_USD)
						,('RI Ceded', 'Original', 'Commission'			,'SUMMABLE_CEDED_Overrider_Commission'		,w.SUMMABLE_CEDED_Overrider_Commission				,w.SUMMABLE_CEDED_Overrider_Commission_USD)
						,('RI Ceded', 'Original', 'Commission'			,'SUMMABLE_CEDED_Provisional_Commission'	,w.SUMMABLE_CEDED_Provisional_Commission			,w.SUMMABLE_CEDED_Provisional_Commission_USD)
						,('RI Ceded', 'Original', 'Commission'			,'SUMMABLE_CEDED_Deferred_Commission'		,w.SUMMABLE_CEDED_Deferred_Commission				,w.SUMMABLE_CEDED_Deferred_Commission_USD)
						,('RI Ceded', 'Original', 'Interest'			,'SUMMABLE_CEDED_int_funds_gross'			,w.SUMMABLE_CEDED_int_funds_gross					,w.SUMMABLE_CEDED_int_funds_gross_USD)
						,('RI Ceded', 'Original', 'Interest'			,'SUMMABLE_CEDED_int_funds_wth'				,w.SUMMABLE_CEDED_int_funds_wth						,w.SUMMABLE_CEDED_int_funds_wth_USD)
						,('RI Ceded', 'Original', 'Brokerage'			,'SUMMABLE_CEDED_fire_prevent_fund'			,w.SUMMABLE_CEDED_fire_prevent_fund					,w.SUMMABLE_CEDED_fire_prevent_fund_USD)
						,('RI Ceded', 'Original', 'Brokerage'			,'SUMMABLE_CEDED_xch_diff'					,w.SUMMABLE_CEDED_xch_diff							,w.SUMMABLE_CEDED_xch_diff_USD)
						,('RI Ceded', 'Original', 'Premium'				,'SUMMABLE_CEDED_NO_CLM_RBT'				,w.SUMMABLE_CEDED_NO_CLM_RBT						,w.SUMMABLE_CEDED_NO_CLM_RBT_USD)
						,('RI Ceded', 'Original', 'FundHeld_Premium'	,'SUMMABLE_CEDED_funds_withheld_premium'	,w.SUMMABLE_CEDED_funds_withheld_premium			,w.SUMMABLE_CEDED_funds_withheld_premium_USD)
						,('RI Ceded', 'Original', 'FundHeld_Premium'	,'SUMMABLE_CEDED_funds_released_premium'	,w.SUMMABLE_CEDED_funds_released_premium			,w.SUMMABLE_CEDED_funds_released_premium_USD)
						,('RI Ceded', 'Original', 'FundHeld_Premium'	,'SUMMABLE_CEDED_funds_withheld_losses'		,w.SUMMABLE_CEDED_funds_withheld_losses				,w.SUMMABLE_CEDED_funds_withheld_losses_USD)
						,('RI Ceded', 'Original', 'FundHeld_Premium'	,'SUMMABLE_CEDED_deferred_withheld'			,w.SUMMABLE_CEDED_deferred_withheld					,w.SUMMABLE_CEDED_deferred_withheld_USD)
						,('RI Ceded', 'Original', 'FundHeld_Premium'	,'SUMMABLE_CEDED_deferred_released'			,w.SUMMABLE_CEDED_deferred_released					,w.SUMMABLE_CEDED_deferred_released_USD)
				) z (Business, CurrencyType, MeasureType,MeasureCode, Amount, AmountUSD)
			WHERE NOT (
					z.Amount = 0
					AND z.AmountUSD = 0
					)
			) x
	LEFT JOIN EDW_PREPROD.assumed.DimMeasure	AS m	ON  m.Entity		= 'Premium'
														AND m.Business		= x.Business	
														AND m.CurrencyType	= x.CurrencyType
														AND m.MeasureType	= x.MeasureType
														AND m.MeasureCode	= x.MeasureCode
														AND prm.ProcessingDate BETWEEN m.StartDate and m.EndDate
    LEFT JOIN #MapParticipant					AS mp	ON mp.Contract_NBR	= w.Contract_NBR
	GROUP BY
		 w.SourceSystemKey
		,w.DimContractID	
		,w.Ceded_DimContractID
		,w.Intended_DimAccountingPeriodID
		,w.Intended_DimAccountingID
		,w.DimAccountingID
		,w.DimTransactionTypeID
		,w.DimAdjustmentTypeID
		,w.Orig_DimCurrencyID
		,w.DimLineOfBusinessID
		,w.DimDueDateID
		,w.DimFromDateID
		,w.DimToDateID
		,w.OrigRpt1_DimExchangeRateID
		,w.OrigRpt2_DimExchangeRateID
		,w.DimDocumentID
		,w.DimBillingID
		,COALESCE(mp.DimParticipantID, prm.DimParticipantNA)
		,COALESCE(m.DimMeasureID, prm.DimMeasureUncoded)
		,prm.ProcessingDate
	HAVING NULLIF(SUM(x.Amount), 0) IS NOT NULL 
	    OR NULLIF(SUM(x.AmountUSD), 0) IS NOT NULL

	SET @v_RowCount = ROWCOUNT_BIG();
	INSERT INTO ##Timings_UW SELECT SYSDATETIME(), 'Created #UnderwritingLoad', @v_RowCount;

	--------------------------------------------------------------------------------	
	-- PostUpdate #UnderwritingLoad (DimBillingID)
	--------------------------------------------------------------------------------
	DROP TABLE IF EXISTS #BillingOverride
		
	SELECT DISTINCT
		 Ceded_DimContractID = dc.DimContractID
		,dp.DimParticipantID
		,db.DimBillingID
	INTO #BillingOverride
	FROM SRC_TIRS_DB.dbo.acct_doc					AS ad
	INNER JOIN SRC_TIRS_DB.dbo.trty_master			AS ctm		ON  ctm.trty_key = ad.ceded_trty_key
	INNER JOIN SRC_TIRS_DB.dbo.trty_participant		AS tp		ON  tp.trty_key = ctm.trty_key
	INNER JOIN EDW_PREPROD.assumed.DimContract		AS dc		ON  dc.CONTRACT_NBR = CONCAT(LEFT(ctm.trty_no, 5), ctm.und_yr) COLLATE DATABASE_DEFAULT
																AND dc.EndDate = '31 Dec 9999'
	INNER JOIN EDW_PREPROD.assumed.DimParticipant	AS dp		ON  dp.Participant_Key = tp.participant_br_key
																AND dp.EndDate = '31 Dec 9999'
	INNER JOIN EDW_PREPROD.assumed.DimBilling		AS db		ON  db.bill_company_cd = CAST(tp.brkr_br_key AS VARCHAR(10))
																AND db.SourceSysKey = 4
																AND db.EndDate = '31 Dec 9999'

	UPDATE u
	   SET DimBillingID = bo.DimBillingID		   
	  FROM #UnderwritingLoad		u
	 INNER JOIN #BillingOverride	bo	ON  bo.Ceded_DimContractID	= u.Ceded_DimContractID
										AND bo.DimParticipantID		= u.DimParticipantID
										--AND u.Source='TIRS'

	SET @v_RowCount = ROWCOUNT_BIG();
	INSERT INTO ##Timings_UW SELECT SYSDATETIME(), 'PostUpdate DimBillingID', @v_RowCount;

	--------------------------------------------------------------------------------	
	-- FactUnderwritingUncoded INSERT (new uncoded values)
	--------------------------------------------------------------------------------
	BEGIN TRANSACTION

	INSERT INTO EDW_Staging.Assumed.FactUnderwritingUncoded
		(
			 [StartDate]                	
			,[UncodedDescription]      
			-------------------------------
			,[DimContractID]                
			,[Ceded_DimContractID]          
			,[Intended_DimAccountingPeriodID]
			,[Intended_DimAccountingID]     
			,[DimAccountingID]              
			,[DimTransactionTypeID]         
			,[DimAdjustmentTypeID]          
			,[Orig_DimCurrencyID]           
			,[DimLineOfBusinessID]          
			,[DimDueDateID]                 
			,[DimFromDateID]                
			,[DimToDateID]                  
			,[OrigRpt1_DimExchangeRateID]   
			,[OrigRpt2_DimExchangeRateID]   
			,[DimParticipantID]             
			,[DimDocumentID]					
			,[DimBillingID]                 
			,[DimMeasureID]                 
			-------------------------------
			,[TREATY_NBR]                   
			,[UNDERWRITING_YEAR]            
			,[CONTRACT_NBR]                 
			,[CEDED_CONTRACT_NBR]           
			,[SourceSystemKey]              
			,[Source]                       
			,[TIRS_ORIG_CURR_CD]            
			,[TIRS_ORIG_CURR_NAME]          
			,[lob_name]                     
			,[reg_date]                     
			,[due_date]                     
			,[aslob]                        
			,[solvency_II_regulatory_key]   
			,[AdjustmentType]               
			,[TIRS_UW_ASSM_CEDED_NAME]      
			,[T7_CODE]                      
			,[T8_CODE]                      
			,[T9_CODE]                      
			,[MBU]                          
			,[L01]                          
			,[L02]                          
			,[L03]                          
			,[L04]                          
			,[L05]                          
			,[L06]                          
			,[L07]                          
			,[L08]                          
			,[L09]                          
			,[L10]                          
			,[GD1]                          
			,[RPTCURR1]                     
			,[RPTCURR1_CD]                  
			,[RPTCURR2]                     
			,[RPTCURR2_CD]                  
			,[InsurerCode]                  
			,[Financial_Lob]                
			,[RPT_OFC_NM]                   
			,[RPT_OFF_NAME]                 
			,[ICP_CEDED_FLG]                
			,[actuariallob]                 
			,[CLMS_PROCSS_CLM_DEPT]         
			,[ID]                           
			,[Unmatched_Fields]             
			,[topside_reg_date]             
			,[Blended_Rate]                 
			,[MATCH_SOURCE_FLAG]            
			,[TransactionTypeCode]          
			,[TransactionTypeCategory]      
			,[doc_key]                      
			,[bill_company_cd]
		)
		SELECT
			 StartDate			= prm.ProcessingDate	
			,UncodedDescription = CONCAT_WS(',',
										 IIF(prm.DimContractUncoded			= l.DimContractID					,'DimContract'				 ,NULL)
										,IIF(prm.DimContractUncoded			= l.Ceded_DimContractID				,'Ceded_DimContractID'		 ,NULL)
										,IIF(prm.DimAccountingPeriodUncoded	= l.Intended_DimAccountingPeriodID	,'Intended_DimAccountingPeriodID' ,NULL)
										,IIF(prm.DimAccountingUncoded		= l.Intended_DimAccountingID		,'Intended_DimAccountingID'	 ,NULL)
										,IIF(prm.DimTransactionTypeUncoded	= l.DimTransactionTypeID			,'DimTransactionTypeID'		 ,NULL)
										,IIF(prm.DimAdjustmentTypeUncoded	= l.DimAdjustmentTypeID				,'DimAdjustmentTypeID'		 ,NULL)
										,IIF(prm.DimCurrencyUncoded			= l.Orig_DimCurrencyID				,'Orig_DimCurrencyID'		 ,NULL)
										,IIF(prm.DimLineOfBusinessUncoded	= l.DimLineOfBusinessID				,'DimLineOfBusinessID'		 ,NULL)
										,IIF(prm.DimDateUncoded			    = l.DimDueDateID					,'DimDueDateID'				 ,NULL)
										,IIF(prm.DimDateUncoded			    = l.DimFromDateID					,'DimFromDateID'			 ,NULL)
										,IIF(prm.DimDateUncoded			    = l.DimToDateID					    ,'DimToDateID'				 ,NULL)
										,IIF(prm.DimExchangeRateUncoded		= l.OrigRpt1_DimExchangeRateID		,'OrigRpt1_DimExchangeRateID',NULL)
										,IIF(prm.DimExchangeRateUncoded		= l.OrigRpt2_DimExchangeRateID		,'OrigRpt2_DimExchangeRateID',NULL)
										,IIF(prm.DimDocumentUncoded			= l.DimDocumentID					,'DimDocumentID'			 ,NULL)
										,IIF(prm.DimBillingUncoded			= l.DimBillingID					,'DimBillingID'				 ,NULL)
										,IIF(prm.DimParticipantUncoded		= l.DimParticipantID				,'DimParticipantID'			 ,NULL)
										,IIF(prm.DimMeasureUncoded			= l.DimMeasureID					,'DimMeasureID'				 ,NULL)
										)
			-------------------------------
			,l.[DimContractID]                
			,l.[Ceded_DimContractID]          
			,l.[Intended_DimAccountingPeriodID]
			,l.[Intended_DimAccountingID]     
			,l.[DimAccountingID]              
			,l.[DimTransactionTypeID]         
			,l.[DimAdjustmentTypeID]          
			,l.[Orig_DimCurrencyID]           
			,l.[DimLineOfBusinessID]          
			,l.[DimDueDateID]                 
			,l.[DimFromDateID]                
			,l.[DimToDateID]                  
			,l.[OrigRpt1_DimExchangeRateID]   
			,l.[OrigRpt2_DimExchangeRateID]   
			,l.[DimParticipantID]             
			,l.[DimDocumentID]					
			,l.[DimBillingID]                 
			,l.[DimMeasureID]                 
			-------------------------------
			,w.[TREATY_NBR]                   
			,w.[UNDERWRITING_YEAR]            
			,w.[CONTRACT_NBR]                 
			,w.[CEDED_CONTRACT_NBR]           
			,w.[SourceSystemKey]              
			,w.[Source]                       
			,w.[TIRS_ORIG_CURR_CD]            
			,w.[TIRS_ORIG_CURR_NAME]          
			,w.[lob_name]                     
			,w.[reg_date]                     
			,w.[due_date]                     
			,w.[aslob]                        
			,w.[solvency_II_regulatory_key]   
			,w.[AdjustmentType]               
			,w.[TIRS_UW_ASSM_CEDED_NAME]      
			,w.[T7_CODE]                      
			,w.[T8_CODE]                      
			,w.[T9_CODE]                      
			,w.[MBU]                          
			,w.[L01]                          
			,w.[L02]                          
			,w.[L03]                          
			,w.[L04]                          
			,w.[L05]                          
			,w.[L06]                          
			,w.[L07]                          
			,w.[L08]                          
			,w.[L09]                          
			,w.[L10]                          
			,w.[GD1]                          
			,w.[RPTCURR1]                     
			,w.[RPTCURR1_CD]                  
			,w.[RPTCURR2]                     
			,w.[RPTCURR2_CD]                  
			,w.[InsurerCode]                  
			,w.[Financial_Lob]                
			,w.[RPT_OFC_NM]                   
			,w.[RPT_OFF_NAME]                 
			,w.[ICP_CEDED_FLG]                
			,w.[actuariallob]                 
			,w.[CLMS_PROCSS_CLM_DEPT]         
			,w.[ID]                           
			,w.[Unmatched_Fields]             
			,w.[topside_reg_date]             
			,w.[Blended_Rate]                 
			,w.[MATCH_SOURCE_FLAG]            
			,w.[TransactionTypeCode]          
			,w.[TransactionTypeCategory]      
			,w.[doc_key]                      
			,w.[bill_company_cd]

		FROM #UnderwritingLoad 			l
	   INNER JOIN #UnderwritingLoadWide w	ON w.UnderwritingLoadWideID = l.UnderwritingLoadWideID
	   INNER JOIN #Parameters			prm	ON prm.DimContractUncoded			= l.DimContractID
											OR prm.DimContractUncoded			= l.Ceded_DimContractID
											OR prm.DimAccountingPeriodUncoded	= l.Intended_DimAccountingPeriodID
											OR prm.DimAccountingUncoded			= l.Intended_DimAccountingID
											OR prm.DimTransactionTypeUncoded	= l.DimTransactionTypeID
											OR prm.DimAdjustmentTypeUncoded		= l.DimAdjustmentTypeID
											OR prm.DimCurrencyUncoded			= l.Orig_DimCurrencyID
											OR prm.DimLineOfBusinessUncoded		= l.DimLineOfBusinessID
											OR prm.DimDateUncoded			    = l.DimDueDateID
											OR prm.DimDateUncoded			    = l.DimFromDateID
											OR prm.DimDateUncoded			    = l.DimToDateID
											OR prm.DimExchangeRateUncoded		= l.OrigRpt1_DimExchangeRateID
											OR prm.DimExchangeRateUncoded		= l.OrigRpt2_DimExchangeRateID
											OR prm.DimDocumentUncoded			= l.DimDocumentID	
											OR prm.DimBillingUncoded			= l.DimBillingID
											OR prm.DimParticipantUncoded 		= l.DimParticipantID
											OR prm.DimMeasureUncoded 			= l.DimMeasureID
		WHERE NOT EXISTS (SELECT * 
							FROM EDW_Staging.Assumed.FactUnderwritingUncoded u
						   WHERE prm.ProcessingDate BETWEEN u.StartDate AND u.EndDate
							  AND ISNULL(u.SourceSystemKey,-1)	= ISNULL(l.SourceSystemKey,-1)
							  AND u.DimContractID				= l.DimContractID 
							  AND u.Ceded_DimContractID			= l.Ceded_DimContractID
							  AND u.Intended_DimAccountingPeriodID = l.Intended_DimAccountingPeriodID
							  AND u.Intended_DimAccountingID	= l.Intended_DimAccountingID
							  AND u.DimTransactionTypeID		= l.DimTransactionTypeID
							  AND u.DimAdjustmentTypeID			= l.DimAdjustmentTypeID
							  AND u.Orig_DimCurrencyID			= l.Orig_DimCurrencyID
							  AND u.DimLineOfBusinessID			= l.DimLineOfBusinessID
							  AND u.DimDueDateID				= l.DimDueDateID
							  AND u.DimFromDateID				= l.DimFromDateID
							  AND u.DimToDateID				    = l.DimToDateID
							  AND u.OrigRpt1_DimExchangeRateID	= l.OrigRpt1_DimExchangeRateID
							  AND u.OrigRpt2_DimExchangeRateID	= l.OrigRpt2_DimExchangeRateID
							  AND u.DimDocumentID				= l.DimDocumentID
							  AND u.DimBillingID				= l.DimBillingID
							  AND u.DimParticipantID			= l.DimParticipantID
							  AND u.DimMeasureID				= l.DimMeasureID
						)

	SET @v_RowCount = ROWCOUNT_BIG();
	INSERT INTO ##Timings_UW SELECT SYSDATETIME(), 'Created and uncoded entries in EDW_Staging.assumed.FactUnderwritingUncoded', @v_RowCount;


	DROP TABLE IF EXISTS #DetectReversalAdjustment

	SELECT x.DimContractID
		,x.DimLineOfBusinessID
		,x.Intended_DimAccountingPeriodID
		,IsAdjustment = CAST(CASE WHEN COALESCE(tcr.ID, -1) = COALESCE(otcr.ID, -1) THEN 0 ELSE 1 END AS BIT)
	INTO #DetectReversalAdjustment
	FROM (
		SELECT DISTINCT t.DimContractID
			,t.DimLineOfBusinessID
			,t.Intended_DimAccountingPeriodID
		FROM (
			SELECT t.*
			FROM assumed.FactUnderwriting t
			LEFT JOIN assumed.FactUnderwriting r
				ON r.ReversalOfFactUnderwritingID = t.FactUnderwritingID
			WHERE r.ReversalOfFactUnderwritingID IS NULL
				AND t.ReversalOfFactUnderwritingID IS NULL
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

	SET @v_RowCount = ROWCOUNT_BIG();
	INSERT INTO ##Timings_UW SELECT SYSDATETIME(), 'Created #DetectReversalAdjustment', @v_RowCount;

 	--------------------------------------------------------------------------------
	-- FactUnderwriting INSERT 1 (Reversals)
	--------------------------------------------------------------------------------	
	DROP TABLE IF EXISTS #ReversalCandidate;
    SELECT
		t.*
	 INTO #ReversalCandidate
     FROM assumed.FactUnderwriting t
	WHERE NOT EXISTS (SELECT * FROM assumed.FactUnderwriting r WHERE r.ReversalOfFactUnderwritingID = t.FactUnderwritingID)
	 AND t.ReversalOfFactUnderwritingID IS NULL ;


	INSERT INTO EDW_PREPROD.assumed.FactUnderwriting
	(
		 SourceSystemKey
		,DimContractID
		,Ceded_DimContractID
		,Intended_DimAccountingPeriodID
		,Actual_DimAccountingPeriodID
		,Intended_DimAccountingID
		,DimAccountingID
		,DimTransactionTypeID
		,DimAdjustmentTypeID
		,Orig_DimCurrencyID
		,DimLineOfBusinessID
		,DimDueDateID
		,DimFromDateID
		,DimToDateID
		,OrigRpt1_DimExchangeRateID
		,OrigRpt2_DimExchangeRateID
		,DimDocumentID
		,DimBillingID
		,DimParticipantID
		,DimMeasureID
		,Amount
		,AmountUSD
		,CreatedDate
		,ReversalOfFactUnderwritingID
	)
	SELECT
		[SourceSystemKey]					= t.[SourceSystemKey],
        [DimContractID]						= t.[DimContractID],
        [Ceded_DimContractID]				= t.[Ceded_DimContractID],
        [Intended_DimAccountingPeriodID]	= t.[Intended_DimAccountingPeriodID],
        [Actual_DimAccountingPeriodID]		= COALESCE(aapo.Actual_DimAccountingPeriodID, CASE  WHEN dap.AccountingPeriodDate < prm.CurrentAccountingPeriod
																								THEN prm.Current_DimAccountingPeriodID
																								ELSE t.Intended_DimAccountingPeriodID END),
        [Intended_DimAccountingID]			= t.[Intended_DimAccountingID],
        [DimAccountingID]					= CASE WHEN IsAdjustment = 0 THEN t.DimAccountingID ELSE pair.DimAccountingID END,
        [DimTransactionTypeID]				= t.[DimTransactionTypeID],
        [DimAdjustmentTypeID]				= t.[DimAdjustmentTypeID],
        [Orig_DimCurrencyID]				= t.[Orig_DimCurrencyID],
        [DimLineOfBusinessID]				= t.[DimLineOfBusinessID],
        [DimDueDateID]						= t.[DimDueDateID],
		[DimFromDateID]						= t.[DimFromDateID],
		[DimToDateID]						= t.[DimToDateID],
        [OrigRpt1_DimExchangeRateID]		= t.[OrigRpt1_DimExchangeRateID],
        [OrigRpt2_DimExchangeRateID]		= t.[OrigRpt2_DimExchangeRateID],
		[DimDocumentID]						= t.[DimDocumentID],
		[DimBillingID]						= t.[DimBillingID],
		[DimParticipantID]					= t.[DimParticipantID],
        [DimMeasureID]						= t.[DimMeasureID],
        [Amount]							= - t.[Amount],
        [AmountUSD]							= - t.[AmountUSD],
        [CreatedDate]						= prm.ProcessingDate,
        [ReversalOfFactUnderwritingID]		= t.[FactUnderwritingID]
    FROM #ReversalCandidate			t
    CROSS JOIN #Parameters			prm
	LEFT  JOIN #UnderwritingLoad	s	ON ISNULL(s.SourceSystemKey, - 1)= ISNULL(t.SourceSystemKey, - 1)
										AND s.DimContractID				= t.DimContractID
										AND s.Ceded_DimContractID		= t.Ceded_DimContractID
										AND s.Intended_DimAccountingPeriodID = t.Intended_DimAccountingPeriodID
										AND s.Intended_DimAccountingID	= t.Intended_DimAccountingID
										AND s.DimTransactionTypeID		= t.DimTransactionTypeID
										AND s.DimAdjustmentTypeID		= t.DimAdjustmentTypeID
										AND s.Orig_DimCurrencyID		= t.Orig_DimCurrencyID
										AND s.DimLineOfBusinessID		= t.DimLineOfBusinessID
										AND s.DimDueDateID				= t.DimDueDateID
										AND s.DimFromDateID				= t.DimFromDateID
										AND s.DimToDateID				= t.DimToDateID
										AND s.OrigRpt1_DimExchangeRateID= t.OrigRpt1_DimExchangeRateID
										AND s.OrigRpt2_DimExchangeRateID= t.OrigRpt2_DimExchangeRateID
										AND s.DimDocumentID				= t.DimDocumentID
										AND s.DimBillingID				= t.DimBillingID
										AND s.DimParticipantID			= t.DimParticipantID
										AND s.DimMeasureID				= t.DimMeasureID
	INNER JOIN #DetectReversalAdjustment dra
		ON dra.DimContractID = t.DimContractID
		AND dra.DimLineOfBusinessID = t.DimLineOfBusinessID
		AND dra.Intended_DimAccountingPeriodID = t.Intended_DimAccountingPeriodID
    INNER JOIN EDW_PREPROD.assumed.DimContract			dc		ON dc.DimContractID = t.DimContractID
    INNER JOIN EDW_PREPROD.assumed.DimAccountingPeriod	dap		ON dap.DimAccountingPeriodID = t.Intended_DimAccountingPeriodID
    INNER JOIN #DimAccountingPairing					pair	ON pair.Intended_DimAccountingID = t.Intended_DimAccountingID
	LEFT  JOIN #ActualAccountingPeriodOverride			aapo	ON aapo.Intended_DimAccountingPeriodID = t.Intended_DimAccountingPeriodID
    WHERE s.UnderwritingLoadWideID IS NULL
	  AND EXISTS (SELECT * 
					FROM #ContractFilter cf	
				   WHERE cf.CONTRACT_NBR  = dc.CONTRACT_NBR COLLATE DATABASE_DEFAULT )
 
	SET @v_RowCount_Fact = @v_RowCount_Fact + ROWCOUNT_BIG();
    INSERT INTO ##Timings_UW SELECT SYSDATETIME(), 'Perform reversals in assumed.FactUnderwriting', @v_RowCount_Fact;
	--------------------------------------------------------------------------------
	--#ConsolidatedTarget
	--------------------------------------------------------------------------------
	DROP TABLE IF EXISTS #ConsolidatedTarget

	SELECT
		 t.SourceSystemKey
		,t.DimContractID
		,t.Ceded_DimContractID
		,t.Intended_DimAccountingPeriodID
		,t.Intended_DimAccountingID
		,t.DimAccountingID
		,t.DimTransactionTypeID
		,t.DimAdjustmentTypeID
		,t.Orig_DimCurrencyID
		,t.DimLineOfBusinessID
		,t.DimDueDateID
		,t.DimFromDateID
		,t.DimToDateID
		,t.OrigRpt1_DimExchangeRateID
		,t.OrigRpt2_DimExchangeRateID
		,t.DimDocumentID
		,t.DimBillingID
		,t.DimParticipantID
		,t.DimMeasureID
		,Amount		= SUM(t.Amount)
		,AmountUSD	= SUM(t.AmountUSD)
	INTO #ConsolidatedTarget
	FROM EDW_PREPROD.assumed.FactUnderwriting	AS t
	INNER JOIN EDW_PREPROD.assumed.DimContract	AS dac	ON dac.DimContractID = t.DimContractID
	CROSS JOIN #Parameters						AS prm
	WHERE EXISTS (SELECT * 
					FROM #ContractFilter cf	
				   WHERE cf.CONTRACT_NBR  = dac.CONTRACT_NBR COLLATE DATABASE_DEFAULT )
	GROUP BY
		 t.SourceSystemKey
		,t.DimContractID
		,t.Ceded_DimContractID
		,t.Intended_DimAccountingPeriodID
		,t.Intended_DimAccountingID
		,t.DimAccountingID
		,t.DimTransactionTypeID
		,t.DimAdjustmentTypeID
		,t.Orig_DimCurrencyID
		,t.DimLineOfBusinessID
		,t.DimDueDateID
		,t.DimFromDateID
		,t.DimToDateID
		,t.OrigRpt1_DimExchangeRateID
		,t.OrigRpt2_DimExchangeRateID
		,t.DimDocumentID
		,t.DimBillingID
		,t.DimParticipantID
		,t.DimMeasureID

	SET @v_RowCount = ROWCOUNT_BIG();
	INSERT INTO ##Timings_UW SELECT SYSDATETIME(), 'Created #ConsolidatedTarget', @v_RowCount;

	DROP TABLE IF EXISTS #DetectAdjustment

	SELECT x.DimContractID
		,x.DimLineOfBusinessID
		,x.Intended_DimAccountingPeriodID
		,IsAdjustment = CAST(CASE WHEN COALESCE(tcr.ID, -1) = COALESCE(otcr.ID, -1) THEN 0 ELSE 1 END AS BIT)
	INTO #DetectAdjustment
	FROM (
		SELECT DISTINCT s.DimContractID
			,s.DimLineOfBusinessID
			,s.Intended_DimAccountingPeriodID
		FROM #UnderwritingLoad s
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

	SET @v_RowCount = ROWCOUNT_BIG();
	INSERT INTO ##Timings_UW SELECT SYSDATETIME(), 'Created #DetectAdjustment', @v_RowCount;

	--------------------------------------------------------------------------------
	-- FactUnderwriting INSERT 2 (new data)
	--------------------------------------------------------------------------------
	INSERT INTO EDW_PREPROD.assumed.FactUnderwriting
	(
		 SourceSystemKey
		,DimContractID
		,Ceded_DimContractID
		,Intended_DimAccountingPeriodID
		,Actual_DimAccountingPeriodID
		,Intended_DimAccountingID
		,DimAccountingID
		,DimTransactionTypeID
		,DimAdjustmentTypeID
		,Orig_DimCurrencyID
		,DimLineOfBusinessID
		,DimDueDateID
		,DimFromDateID
		,DimToDateID
		,OrigRpt1_DimExchangeRateID
		,OrigRpt2_DimExchangeRateID
		,DimDocumentID
		,DimBillingID
		,DimParticipantID
		,DimMeasureID
		,Amount
		,AmountUSD
		,CreatedDate
	)
	SELECT
		 SourceSystemKey				= s.SourceSystemKey
		,DimContractID					= s.DimContractID
		,Ceded_DimContractID			= s.Ceded_DimContractID
		,Intended_DimAccountingPeriodID	= s.Intended_DimAccountingPeriodID
		,Actual_DimAccountingPeriodID	= COALESCE(aapo.Actual_DimAccountingPeriodID, CASE	WHEN dap.AccountingPeriodDate < prm.CurrentAccountingPeriod 
												THEN prm.Current_DimAccountingPeriodID
												ELSE s.Intended_DimAccountingPeriodID END)
		,Intended_DimAccountingID		= s.Intended_DimAccountingID
		,DimAccountingID				= CASE WHEN da.IsAdjustment = 0 THEN s.Intended_DimAccountingID ELSE pair.DimAccountingID END
		,DimTransactionTypeID			= s.DimTransactionTypeID
		,DimAdjustmentTypeID			= s.DimAdjustmentTypeID
		,Orig_DimCurrencyID				= s.Orig_DimCurrencyID
		,DimLineOfBusinessID			= s.DimLineOfBusinessID
		,DimDueDateID					= s.DimDueDateID
		,DimFromDateID					= s.DimFromDateID
		,DimToDateID					= s.DimToDateID
		,OrigRpt1_DimExchangeRateID		= s.OrigRpt1_DimExchangeRateID
		,OrigRpt2_DimExchangeRateID		= s.OrigRpt2_DimExchangeRateID
		,DimDocumentID					= s.DimDocumentID
		,DimBillingID					= s.DimBillingID
		,DimParticipantID				= s.DimParticipantID
		,DimMeasureID					= s.DimMeasureID
		,Amount							= COALESCE(s.Amount, 0)    - COALESCE(t.Amount, 0)
		,AmountUSD						= COALESCE(s.AmountUSD, 0) - COALESCE(t.AmountUSD, 0)
		,CreatedDate					= prm.ProcessingDate
	FROM #UnderwritingLoad			AS s
	LEFT JOIN #ConsolidatedTarget	AS t ON COALESCE(t.SourceSystemKey, -1)		= COALESCE(s.SourceSystemKey, -1)
										AND t.DimContractID						= s.DimContractID
										AND t.Ceded_DimContractID				= s.Ceded_DimContractID
										AND t.Intended_DimAccountingPeriodID	= s.Intended_DimAccountingPeriodID
										AND t.Intended_DimAccountingID			= s.Intended_DimAccountingID
										AND t.DimTransactionTypeID				= s.DimTransactionTypeID
										AND t.DimAdjustmentTypeID				= s.DimAdjustmentTypeID
										AND t.Orig_DimCurrencyID				= s.Orig_DimCurrencyID
										AND t.DimLineOfBusinessID				= s.DimLineOfBusinessID
										AND t.DimDueDateID						= s.DimDueDateID
										AND t.DimFromDateID						= s.DimFromDateID
										AND t.DimToDateID						= s.DimToDateID
										AND t.OrigRpt1_DimExchangeRateID		= s.OrigRpt1_DimExchangeRateID
										AND t.OrigRpt2_DimExchangeRateID		= s.OrigRpt2_DimExchangeRateID
										AND t.DimDocumentID						= s.DimDocumentID
										AND t.DimBillingID						= s.DimBillingID
										AND t.DimParticipantID                  = s.DimParticipantID
										AND t.DimMeasureID						= s.DimMeasureID
	CROSS JOIN #Parameters	AS prm
	INNER JOIN #DetectAdjustment da
		ON da.DimContractID = s.DimContractID
		AND da.DimLineOfBusinessID = s.DimLineOfBusinessID
		AND da.Intended_DimAccountingPeriodID = s.Intended_DimAccountingPeriodID
	INNER JOIN EDW_PREPROD.assumed.DimAccountingPeriod	AS dap	ON  dap.DimAccountingPeriodID = s.Intended_DimAccountingPeriodID
																AND prm.ProcessingDate BETWEEN dap.StartDate AND dap.EndDate
	INNER JOIN #AccountingPeriod						AS ap	ON  ap.AccountingPeriodDate = dap.AccountingPeriodDate
	INNER JOIN #DimAccountingPairing					AS pair	ON  pair.Intended_DimAccountingID = s.Intended_DimAccountingID
	LEFT JOIN #ActualAccountingPeriodOverride aapo
		ON aapo.Intended_DimAccountingPeriodID = s.Intended_DimAccountingPeriodID
	WHERE ABS(COALESCE(s.Amount, 0) - COALESCE(t.Amount, 0)) >= 0.01
	   OR ABS(COALESCE(s.AmountUSD, 0) - COALESCE(t.AmountUSD, 0)) >= 0.01


	SET @v_RowCount_Fact = @v_RowCount_Fact + ROWCOUNT_BIG();
	INSERT INTO ##Timings_UW SELECT SYSDATETIME(), 'Final insert to FactUnderwriting', @v_RowCount_Fact;

	--------------------------------------------------------------------------------	
	-- FactUnderwritingUncoded UPDATE (recheck uncoded values and close EndDate for unactual records)
	--------------------------------------------------------------------------------
	UPDATE u
	   SET EndDate = prm.ProcessingDate
	  FROM EDW_Staging.Assumed.FactUnderwritingUncoded u
	 CROSS JOIN #Parameters	prm 
	 WHERE prm.ProcessingDate BETWEEN u.StartDate AND u.EndDate
	   AND NOT EXISTS (SELECT * 
						 FROM EDW_PREPROD.assumed.FactUnderwriting	f
						WHERE f.ReversalOfFactUnderwritingID IS NULL
							AND NOT EXISTS (SELECT * FROM EDW_PREPROD.assumed.FactUnderwriting rr WHERE f.FactUnderwritingID = rr.ReversalOfFactUnderwritingID)
							----
							AND ISNULL(u.SourceSystemKey,-1)	= ISNULL(f.SourceSystemKey,-1)
							AND u.DimContractID					= f.DimContractID 
							AND u.Ceded_DimContractID			= f.Ceded_DimContractID
							AND u.Intended_DimAccountingPeriodID= f.Intended_DimAccountingPeriodID
							AND u.Intended_DimAccountingID		= f.Intended_DimAccountingID
							AND u.DimTransactionTypeID			= f.DimTransactionTypeID
							AND u.DimAdjustmentTypeID			= f.DimAdjustmentTypeID
							AND u.Orig_DimCurrencyID			= f.Orig_DimCurrencyID
							AND u.DimLineOfBusinessID			= f.DimLineOfBusinessID
							AND u.DimDueDateID					= f.DimDueDateID
							AND u.DimFromDateID					= f.DimFromDateID
							AND u.DimToDateID					= f.DimToDateID
							AND u.OrigRpt1_DimExchangeRateID	= f.OrigRpt1_DimExchangeRateID
							AND u.OrigRpt2_DimExchangeRateID	= f.OrigRpt2_DimExchangeRateID
							AND u.DimDocumentID					= f.DimDocumentID
							AND u.DimBillingID					= f.DimBillingID
							AND u.DimParticipantID				= f.DimParticipantID
							AND u.DimMeasureID					= f.DimMeasureID
						)

	SET @v_RowCount = ROWCOUNT_BIG();
	INSERT INTO ##Timings_UW SELECT SYSDATETIME(), 'Close unactual uncoded entries in EDW_Staging.assumed.FactUnderwritingUncoded', @v_RowCount;
	COMMIT TRANSACTION

	-------------------------------------------------------
	-- Update etl_controller, flag SUCCESS
	-------------------------------------------------------
	SET @v_RowsProcessed	= @v_RowCount_Fact
	SET @v_ProcessingEnded	= GETDATE()
	SET @v_LastIdentity		= SCOPE_IDENTITY()
	SET @v_Comment			= CONCAT(@v_Comment, ' , FullLoad=', @FullLoad)

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

		RAISERROR(@v_ErrorMessage, @v_ErrorSeverity, @v_ErrorState)
    END CATCH 
