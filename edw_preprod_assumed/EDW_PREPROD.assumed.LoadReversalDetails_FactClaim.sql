-- Database: EDW_PREPROD
-- Schema: assumed
-- Procedure: LoadReversalDetails_FactClaim

CREATE   PROCEDURE [assumed].[LoadReversalDetails_FactClaim]
--DECLARE	
	@FactCreatedDate	DATETIME2(7) = NULL
AS
BEGIN TRY
	DECLARE
		@ProcessStartDate	DATETIME	= GETDATE(),
		@RowCount			BIGINT		= 0,
		@TableName			VARCHAR(255) = 'FactClaim'

	IF (SELECT COUNT(*) FROM EDW_PREPROD.assumed.FactClaim WITH (NOLOCK) WHERE ReversalOfFactClaimID IS NOT NULL AND CreatedDate=@FactCreatedDate )=0
	BEGIN
		RETURN
	END
	---------------------------------------------------------------------------------------------
	--#FactClaim_Delta
	---------------------------------------------------------------------------------------------
	DROP TABLE IF EXISTS #FactClaim_Delta;
	
	SELECT
		 c.PLCY_SRC 
		,c.CONTRACT_NBR
		,RegDate_Orig	= api.AccountingPeriodDate
		,RegDate_Actual	= apa.AccountingPeriodDate
		------
		,m.MeasureCode
		,m.MeasureType
		,m.Entity
		,m.Business
		,m.CurrencyType
		------
		,f.*
	  INTO #FactClaim_Delta
	  FROM EDW_PREPROD.assumed.FactClaim	AS f WITH (NOLOCK)
		LEFT JOIN (SELECT *
					 FROM EDW_PREPROD.assumed.DimMeasure
					WHERE Entity ='Claim'		)			AS m	ON m.DimMeasureID  = f.DimMeasureID
		LEFT JOIN EDW_PREPROD.assumed.DimContract			AS c	ON c.DimContractID = f.DimContractID
		LEFT JOIN EDW_PREPROD.assumed.DimAccountingPeriod	AS api	ON api.DimAccountingPeriodID = f.Intended_DimAccountingPeriodID
		LEFT JOIN EDW_PREPROD.assumed.DimAccountingPeriod	AS apa	ON apa.DimAccountingPeriodID = f.Actual_DimAccountingPeriodID
	 WHERE (f.SourceSystemKey IS NOT NULL OR (f.SourceSystemKey IS NULL AND (ABS(Amount)>=0.03 OR ABS(AmountUSD)>=0.03) ))
	   AND f.CreatedDate = @FactCreatedDate

	CREATE INDEX IND1 ON #FactClaim_Delta (FactClaimID);
	---------------------------------------------------------------------------------------------
	--#Reversal_Precalculation_ReversalID
	---------------------------------------------------------------------------------------------
	DROP TABLE IF EXISTS #Reversal_Precalculation_ReversalID;

	SELECT
		 PLCY_SRC							
		,CONTRACT_NBR						
		,RegDate_Orig						
		,RegDate_Actual
		,SourceSystemKey
		,Amount				= CONVERT(NVARCHAR(1000),Amount)
		,AmountUSD			= CONVERT(NVARCHAR(1000),AmountUSD)
		------
		,MeasureCode
		,MeasureType
		,Entity
		,Business
		,CurrencyType
		------
		,FactCreatedDate	= CreatedDate						
		,ReversalID							
		,FactClaimID		
		,FactClaimID_NEW	= IIF(RN_Link=1 ,FactClaimID_NEW ,NULL)
		,RN_Link
	  INTO #Reversal_Precalculation_ReversalID 
	  FROM (
		SELECT
			 CreatedDate			= f_Rev.CreatedDate
			,ReversalID				= f_Rev.ReversalOfFactClaimID
			,FactClaimID			= f_Rev.FactClaimID
			,PLCY_SRC				= f_Rev.PLCY_SRC
			,CONTRACT_NBR			= f_Rev.CONTRACT_NBR
			,RegDate_Orig			= f_Rev.RegDate_Orig
			,RegDate_Actual			= f_Rev.RegDate_Actual
			,SourceSystemKey		= f_Rev.SourceSystemKey
			,Amount					= f_Rev.Amount
			,AmountUSD				= f_Rev.AmountUSD
			----
			,MeasureCode			= f_Rev.MeasureCode
			,MeasureType			= f_Rev.MeasureType
			,Entity					= f_Rev.Entity
			,Business				= f_Rev.Business
			,CurrencyType			= f_Rev.CurrencyType
			----
			,FactClaimID_NEW	= f_New.FactClaimID
			,RN_Link = IIF(f_New.DimContractID IS NULL, 1, ROW_NUMBER() OVER(PARTITION BY f_New.FactClaimID,f_Rev.CONTRACT_NBR,f_Rev.MeasureCode
																				 ORDER BY f_Rev.ReversalOfFactClaimID DESC))											   																										   
		FROM #FactClaim_Delta	AS f_Rev WITH (NOLOCK)												   
		OUTER APPLY (SELECT TOP 1 f.*															   	
					   FROM #FactClaim_Delta	AS f WITH (NOLOCK)										   
					  WHERE f.ReversalOfFactClaimID IS NULL
						AND f.CreatedDate	= f_Rev.CreatedDate
						AND f.PLCY_SRC		= f_Rev.PLCY_SRC
						AND f.CONTRACT_NBR	= f_Rev.CONTRACT_NBR
						AND f.Intended_DimAccountingPeriodID= f_Rev.Intended_DimAccountingPeriodID
						AND f.Actual_DimAccountingPeriodID	= f_Rev.Actual_DimAccountingPeriodID
						---Unique combination---
						AND f.MeasureCode	= f_Rev.MeasureCode
						AND f.Business		= f_Rev.Business					
						AND f.CurrencyType	= f_Rev.CurrencyType
						------
						AND ISNULL(f.SourceSystemKey,-1)	=  ISNULL(f_Rev.SourceSystemKey,-1)
						AND ISNULL(f.SourceSystemKey,f.DimClaimTransactionID) = ISNULL(f_Rev.SourceSystemKey,f_Rev.DimClaimTransactionID)
						AND -1*f_Rev.Amount    BETWEEN -0.01+f.Amount    AND 0.01+f.Amount
						AND -1*f_Rev.AmountUSD BETWEEN -0.01+f.AmountUSD AND 0.01+f.AmountUSD
						ORDER BY f.Amount, f.AmountUSD
					) AS f_New
		WHERE f_Rev.ReversalOfFactClaimID IS NOT NULL
	) AS r;

	CREATE INDEX IND_Delta ON #FactClaim_Delta (FactClaimID);
	---------------------------------------------------------------------------------------------
	--#ReversalID_List
	---------------------------------------------------------------------------------------------	
	DROP TABLE IF EXISTS #ReversalID_List;

	SELECT DISTINCT FactCreatedDate, PLCY_SRC, CONTRACT_NBR, SourceSystemKey, ReversalID, FactClaimID, FactClaimID_NEW
	  INTO #ReversalID_List
	  FROM #Reversal_Precalculation_ReversalID;

	CREATE INDEX IND_ReversalID ON #ReversalID_List (CONTRACT_NBR, ReversalID, FactClaimID, FactClaimID_NEW);
	---------------------------------------------------------------------------------------------
	--#CheckColumns_List
	---------------------------------------------------------------------------------------------
	DROP TABLE IF EXISTS #CheckColumns_List;

	SELECT COLUMN_NAME, ORDINAL_POSITION
	  INTO #CheckColumns_List	
	  FROM INFORMATION_SCHEMA.COLUMNS
	 WHERE TABLE_SCHEMA = 'assumed'
	   AND TABLE_NAME   = 'FactClaim'
	   AND COLUMN_NAME LIKE '%ID%'
	   AND COLUMN_NAME NOT LIKE '%Fact%ID%';

	---------------------------------------------------------------------------------------------
	--Create the dynamic date columns string
	---------------------------------------------------------------------------------------------
	DECLARE @cols NVARCHAR(MAX)

	 SELECT @cols = STRING_AGG ('('''+ column_name +''','+ QUOTENAME(column_name)+')', ',')
	   FROM #CheckColumns_List

	--PRINT @cols
	---------------------------------------------------------------------------------------------
	--@SQL_OLD Unpivot using dynamic sql
	---------------------------------------------------------------------------------------------
	DROP TABLE IF EXISTS ##Staging_OLD;

	DECLARE @SQL_OLD NVARCHAR(MAX)
		SET @SQL_OLD = N'
			  SELECT r.CONTRACT_NBR, r.ReversalID, r.FactClaimID, r.FactClaimID_NEW, up.COLUMN_NAME, Value_old = CONVERT(nvarchar(1000),up.Value)
			    INTO ##Staging_OLD
				FROM #ReversalID_List as r
				LEFT JOIN #FactClaim_Delta AS f	ON f.FactClaimID=r.FactClaimID
			  CROSS APPLY( VALUES' + @cols + N') up(COLUMN_NAME ,Value)
			  '
	--PRINT @SQL_OLD
	EXEC(@SQL_OLD)
	CREATE INDEX IND_Staging_OLD ON ##Staging_OLD (CONTRACT_NBR, ReversalID, FactClaimID, FactClaimID_NEW, COLUMN_NAME);
	---------------------------------------------------------------------------------------------
	--@SQL_NEW Unpivot using dynamic sql
	---------------------------------------------------------------------------------------------
	DROP TABLE IF EXISTS ##Staging_NEW;

	DECLARE @SQL_NEW NVARCHAR(MAX)
		SET @SQL_NEW = N'
			  SELECT r.CONTRACT_NBR, r.ReversalID, r.FactClaimID, r.FactClaimID_NEW, up.COLUMN_NAME, Value_new = CONVERT(nvarchar(1000),up.Value)
			    INTO ##Staging_NEW
				FROM #ReversalID_List as r
				LEFT JOIN #FactClaim_Delta AS f	ON f.FactClaimID=r.FactClaimID_NEW
			  CROSS APPLY( VALUES' + @cols + N') up(COLUMN_NAME ,Value)
			  '
	--PRINT @SQL_OLD
	EXEC(@SQL_NEW)
	CREATE INDEX IND_Staging_NEW ON ##Staging_NEW (CONTRACT_NBR, ReversalID, FactClaimID, FactClaimID_NEW, COLUMN_NAME);
	---------------------------------------------------------------------------------------------
	--#ReversalID_Precalculation_DIFF: Compare OLD and NEW data
	---------------------------------------------------------------------------------------------
	DROP TABLE IF EXISTS #ReversalID_Precalculation_DIFF;

	SELECT *
	  INTO #ReversalID_Precalculation_DIFF
	  FROM (
			SELECT r.CONTRACT_NBR, r.ReversalID, r.FactClaimID, r.FactClaimID_NEW, old.COLUMN_NAME, old.Value_old, new.Value_new
			  FROM #ReversalID_List AS r
			  LEFT JOIN ##Staging_OLD AS old	ON  old.CONTRACT_NBR	= r.CONTRACT_NBR
												AND old.ReversalID		= r.ReversalID
												AND old.FactClaimID		= r.FactClaimID
												AND old.FactClaimID_NEW	= r.FactClaimID_NEW
			  LEFT JOIN ##Staging_NEW AS new	ON  new.CONTRACT_NBR	= r.CONTRACT_NBR
												AND new.ReversalID		= r.ReversalID
												AND new.FactClaimID		= r.FactClaimID
												AND new.FactClaimID_NEW	= r.FactClaimID_NEW
												AND new.COLUMN_NAME		= old.COLUMN_NAME
			WHERE old.Value_old <> new.Value_new
			UNION
			SELECT r.CONTRACT_NBR, r.ReversalID, r.FactClaimID, r.FactClaimID_NEW, COLUMN_NAME = r.MeasureCode COLLATE DATABASE_DEFAULT, 
				   Value_old = CONCAT('Amount = ', r.Amount, ', AmountUSD = ', r.AmountUSD), Value_new = CONCAT('Amount = 0', ', AmountUSD = 0')
			  FROM #Reversal_Precalculation_ReversalID AS r
			 WHERE r.FactClaimID_NEW IS NULL
	) d

	---------------------------------------------------------------------------------------------
	--#ReversalID_Precalculation_DIFF: Compare OLD and NEW data
	---------------------------------------------------------------------------------------------
	DROP TABLE IF EXISTS #Reversal_Precalculation_TXT;

	SELECT *
		,Description1	= CONCAT_WS(' ; '									
									,CONCAT('FactClaimID:',CONVERT(VARCHAR,FactClaimID)					,' -> '+CONVERT(VARCHAR,FactClaimID_NEW))
									,CONCAT(COLUMN_NAME, ' changed (',COALESCE(CONVERT(VARCHAR(1000),value_old),'NULL')	,' -> ', COALESCE(CONVERT(VARCHAR(1000),value_new),'NULL'),')'))
	  INTO #Reversal_Precalculation_TXT
	  FROM #ReversalID_Precalculation_DIFF
	 ORDER BY CONTRACT_NBR, ReversalID, FactClaimID, FactClaimID_NEW

	---------------------------------------------------------------------------------------------
	--FINAL INSERT
	---------------------------------------------------------------------------------------------
	BEGIN TRANSACTION
	DELETE 
	  FROM assumed.ReversalDetails
	 WHERE TableName = @TableName AND FactCreatedDate = @FactCreatedDate;

	INSERT INTO assumed.ReversalDetails
	(
		 FactCreatedDate
		,TableName
		,SourceSystem
		,ContractNumber
		,RegDate_Orig
		,RegDate_Actual
		,SourceSystemKey
		,FactID_OLD
		,FactID_NEW
		,EntityName
		,DimID_OLD
		,DimID_NEW
		,Description1
		,Description2
		,InsertedDate
	)
	SELECT
		 FactCreatedDate= r.FactCreatedDate
		,TableName		= @TableName
		,SourceSystem	= r.PLCY_SRC
		,ContractNumber = t.CONTRACT_NBR
		,RegDate_Orig	= r.RegDate_Orig
		,RegDate_Actual	= r.RegDate_Actual
		,SourceSystemKey= r.SourceSystemKey
		,FactID_OLD		= t.FactClaimID
		,FactID_NEW		= t.FactClaimID_NEW
		,EntityName		= t.COLUMN_NAME
		,DimID_OLD		= t.Value_old
		,DimID_NEW		= t.Value_new
		,Description1	= t.Description1
		,Description2	= NULL
		,InsertedDate	= GETDATE()
	FROM #Reversal_Precalculation_TXT	AS t
	LEFT JOIN #Reversal_Precalculation_ReversalID	AS r ON r.FactClaimID = t.FactClaimID
	ORDER BY Description1;

	SET @RowCount = @RowCount+ROWCOUNT_BIG();		
	COMMIT TRANSACTION

	DECLARE @ProcessName		VARCHAR(100)= OBJECT_SCHEMA_NAME(@@PROCID) + '.' + OBJECT_NAME(@@PROCID)
	DECLARE @LastIdentity		BIGINT		= SCOPE_IDENTITY()
	DECLARE @ProcessingStarted	DATETIME	= @ProcessStartDate
	DECLARE @ProcessingEnded	DATETIME	= GETDATE()
	DECLARE @SourceDataDate		DATETIME	= (SELECT [sql_date] FROM ETL.dbo.[day] WHERE today = 1)
	DECLARE @RowsProcessed		BIGINT		= @RowCount
	DECLARE @ps_comment			VARCHAR(100)= NULL;

	EXEC ETL.dbo.update_etl_controller 
		 @ps_process_name			= @ProcessName
		,@pn_rows_processed			= @RowsProcessed
		,@pdt_data_datetime			= @SourceDataDate
		,@pdt_process_start_datetime= @ProcessingStarted
		,@pdt_process_end_datetime	= @ProcessingEnded
		,@pn_error_number			= 0
		,@ps_comment				= @ps_comment
		,@pn_max_processed_event_id = @LastIdentity

	END TRY
BEGIN CATCH
		IF @@TRANCOUNT > 0
		BEGIN
			ROLLBACK
		END

		DECLARE @ErrorNumber		INT = ERROR_NUMBER()
		DECLARE @ErrorMessage		VARCHAR(8000) = ERROR_MESSAGE()
		DECLARE @ErrorSeverity		INT = ERROR_SEVERITY()
		DECLARE @ErrorState			INT = ERROR_STATE()
		DECLARE @ErrorDescription	VARCHAR(8000) = CONCAT('Error: ', @ErrorNumber, ' - ', @ErrorMessage, '; ', 'Occurred in procedure: ' + ERROR_PROCEDURE() + ', ', 'Line ', ERROR_LINE())

		DECLARE @ProcessNameC		VARCHAR(100) = OBJECT_SCHEMA_NAME(@@PROCID) + '.' + OBJECT_NAME(@@PROCID)
		DECLARE @ProcessingStartedC DATETIME = @ProcessStartDate
		DECLARE @ProcessingEndedC	DATETIME = GETDATE()
		DECLARE @SourceDataDateC	DATETIME = (SELECT [sql_date] FROM ETL.dbo.[day] WHERE today = 1)

		EXEC ETL.dbo.update_etl_controller 
			 @ps_process_name			= @ProcessNameC
			,@pn_rows_processed			= 0
			,@pdt_data_datetime			= @SourceDataDateC
			,@pdt_process_start_datetime= @ProcessingStartedC
			,@pdt_process_end_datetime	= @ProcessingEndedC
			,@pn_error_number			= @ErrorNumber
			,@ps_comment				= @ErrorDescription
			,@pn_max_processed_event_id = 0

		EXEC ETL.dbo.insert_error_log @process_name = @ProcessNameC
			,@object_name	= 0
			,@user_message	= @ErrorDescription
			,@status		= 0
			,@remedy		= 'Contact EDW team'

		PRINT @ErrorDescription
		--RAISERROR(@ErrorDescription, @ErrorSeverity, @ErrorState)
END CATCH
