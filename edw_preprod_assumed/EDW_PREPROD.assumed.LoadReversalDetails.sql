-- Database: EDW_PREPROD
-- Schema: assumed
-- Procedure: LoadReversalDetails

CREATE   PROCEDURE [assumed].[LoadReversalDetails]
--DECLARE	
	@Is_RD_fullLoad	INT = 0
AS
BEGIN TRY
		DECLARE @v_ProcessName			VARCHAR(100)= OBJECT_SCHEMA_NAME(@@PROCID) + '.' + OBJECT_NAME(@@PROCID)
		DECLARE @v_LastIdentity			BIGINT		= SCOPE_IDENTITY()
		DECLARE @v_ProcessingStarted	DATETIME	= GETDATE()
		DECLARE @v_ProcessingEnded		DATETIME	= GETDATE()
		DECLARE @v_SourceDataDate		DATE		= (SELECT [sql_date] FROM ETL.dbo.[day] WHERE today = 1)
		DECLARE @v_RowsProcessed		BIGINT		= 0
		DECLARE @v_Comment				VARCHAR(255)= 'IntegritySourceSetCheck='+CONVERT(VARCHAR,(SELECT EDW_Staging.assumed.Get_IntegritySourceSetCheck() ))
		DECLARE @v_FactClaim_FullLoadDT DATETIME2(7) = (SELECT FullLoad_DT=MIN(CreatedDate)
														 FROM EDW_PREPROD.assumed.FactClaim WITH (NOLOCK) 
														WHERE ReversalOfFactClaimID IS NOT NULL )
		DECLARE @v_FactUW_FullLoadDT 	DATETIME2(7) = (SELECT FullLoad_DT=MIN(CreatedDate)
														 FROM EDW_PREPROD.assumed.FactUnderwriting WITH (NOLOCK) 
														WHERE ReversalOfFactUnderwritingID IS NOT NULL )

	IF @Is_RD_fullLoad = 1
	BEGIN
		TRUNCATE TABLE assumed.ReversalDetails
	END
	-----------------------------------------------------------------------------------------------------
	-- #CreatedDateList - find new dates for handling
	-----------------------------------------------------------------------------------------------------
	DROP TABLE IF EXISTS #RD_FactCreatedDate;
	SELECT DISTINCT FactCreatedDate
	  INTO #RD_FactCreatedDate
	  FROM assumed.ReversalDetails  WITH (NOLOCK)

	DROP TABLE IF EXISTS #CreatedDateList;
	SELECT *
	  INTO #CreatedDateList
	  FROM (
			SELECT DISTINCT f.CreatedDate
			  FROM EDW_PREPROD.assumed.FactClaim AS f WITH (NOLOCK)
			 WHERE f.ReversalOfFactClaimID IS NOT NULL
			   AND f.CreatedDate > @v_FactClaim_FullLoadDT
			   AND NOT EXISTS (SELECT *
								 FROM #RD_FactCreatedDate AS e
								WHERE e.FactCreatedDate = f.CreatedDate)
			UNION
			SELECT DISTINCT f.CreatedDate
			  FROM EDW_PREPROD.assumed.FactUnderwriting AS f WITH (NOLOCK)
			 WHERE f.ReversalOfFactUnderwritingID IS NOT NULL
			   AND f.CreatedDate > @v_FactUW_FullLoadDT
			   AND NOT EXISTS (SELECT *
								 FROM #RD_FactCreatedDate AS e
								WHERE e.FactCreatedDate = f.CreatedDate)
		) AS s
	--WHERE CreatedDate >='2025-04-01';

	-----------------------------------------------------------------------------------------------------
	-- IF IntegretyCheck = 0 or #CreatedDateList = empty  - stop calculation
	-----------------------------------------------------------------------------------------------------
	IF (SELECT EDW_Staging.assumed.Get_IntegritySourceSetCheck() ) = 0
	   OR (SELECT COUNT(*) FROM #CreatedDateList ) = 0
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

	-----------------------------------------------------------------------------------------------------
	--Part 1 - insert reversals info into ReversalDetails
	-----------------------------------------------------------------------------------------------------
	DECLARE @Curr1					CURSOR
	DECLARE @FactCreatedDate		DATETIME2(7)

	  SET @Curr1 = CURSOR FOR SELECT * FROM #CreatedDateList ORDER BY CreatedDate;
	 OPEN @Curr1
	FETCH NEXT
	 FROM @Curr1 INTO @FactCreatedDate
	WHILE @@FETCH_STATUS = 0
	BEGIN
		EXEC assumed.LoadReversalDetails_FactClaim @FactCreatedDate;
		EXEC assumed.LoadReversalDetails_FactUnderwriting @FactCreatedDate;

		FETCH  NEXT FROM @Curr1 INTO @FactCreatedDate
	END
	CLOSE @Curr1
	DEALLOCATE @Curr1
	-----------------------------------------------------------------------------------------------------
	--Part 2 - post update ReversalDetails.Description2
	-----------------------------------------------------------------------------------------------------
	DECLARE @Curr2			CURSOR
	DECLARE @EntityName		VARCHAR (500)
	DECLARE @TableName		VARCHAR (255)	
	DECLARE @DimID			VARCHAR (255)	
	DECLARE @Cols			NVARCHAR(MAX)

	DROP TABLE IF EXISTS ##ReversalDetails;

	SELECT DISTINCT EntityName, DimID_OLD, DimID_NEW
	  INTO ##ReversalDetails
	  FROM EDW_PREPROD.assumed.ReversalDetails WITH (NOLOCK)
	 WHERE FactID_OLD IS NOT NULL AND FactID_NEW IS NOT NULL--EntityName NOT LIKE '%SUMMABLE%'
	   AND Description2 IS NULL

	DROP TABLE IF EXISTS ##ComparisonResult;
	CREATE TABLE ##ComparisonResult (
		 TableName		VARCHAR(500)
		,Fact_DimName	VARCHAR(500) 
		,DimID_OLD	 	VARCHAR(500) 
		,DimID_NEW	 	VARCHAR(500) 
		,Description2	VARCHAR(MAX) 
		,INDEX IND_ComparisonResult (Fact_DimName, DimID_OLD, DimID_NEW)
	);			   	
				   	
	  SET @Curr2 = CURSOR FOR SELECT DISTINCT EntityName FROM ##ReversalDetails ORDER BY EntityName;
	 OPEN @Curr2
	FETCH NEXT
	 FROM @Curr2 INTO @EntityName
	WHILE @@FETCH_STATUS = 0
	BEGIN
		---------------------------------------------------------------------------------------------
		--#DimName
		---------------------------------------------------------------------------------------------
		DROP TABLE IF EXISTS ##DimName;

		SELECT DISTINCT c.TABLE_SCHEMA, c.TABLE_NAME, DimID = c.COLUMN_NAME
		  INTO ##DimName
		  FROM INFORMATION_SCHEMA.COLUMNS as c
		 WHERE c.TABLE_SCHEMA = 'assumed'
		   AND c.TABLE_NAME LIKE '%Dim%' AND (c.TABLE_NAME NOT LIKE '%DEV%' AND c.TABLE_NAME NOT LIKE '%PROD%' )
		   AND c.ORDINAL_POSITION = 1
		   AND REPLACE(REPLACE(REPLACE(@EntityName,'Due',''),'From',''),'To','') LIKE '%'+ c.COLUMN_NAME + '%'
		---------------------------------------------------------------------------------------------
		--Create the dynamic date columns string
		---------------------------------------------------------------------------------------------
		SELECT @Cols = STRING_AGG ('('''+ column_name +''', '+ QUOTENAME(column_name)+')', ',') WITHIN GROUP (ORDER BY c.ORDINAL_POSITION) 
		  FROM INFORMATION_SCHEMA.COLUMNS as c
		 WHERE EXISTS (SELECT *
						 FROM ##DimName AS d
						WHERE d.TABLE_SCHEMA = c.TABLE_SCHEMA
						  AND d.TABLE_NAME = c.TABLE_NAME )
		AND c.COLUMN_NAME NOT IN ('StartDate','EndDate','UpdateDate')
		AND c.ORDINAL_POSITION > 1
		AND DATA_TYPE <> 'binary'

		SET @cols = REPLACE(REPLACE(@cols,'[','CONVERT(NVARCHAR,['),']','])')
		---------------------------------------------------------------------------------------------
		--@SQL_OLD Unpivot using dynamic sql
		---------------------------------------------------------------------------------------------
		DROP TABLE IF EXISTS ##DimData_OLD;

		DECLARE @SQL_OLD  NVARCHAR(MAX)
		SET @TableName	= (SELECT TABLE_SCHEMA+'.'+TABLE_NAME FROM ##DimName)
		SET @DimID		= (SELECT DimID FROM ##DimName)
 		SET @SQL_OLD	= N'
				  SELECT TableName = ''' + @TableName + ''',Fact_DimName = e.EntityName, e.DimID_OLD, e.DimID_NEW, up.COLUMN_NAME, Value_OLD = up.Value
					INTO ##DimData_OLD
					FROM ##ReversalDetails AS e
					JOIN '+ @TableName + ' AS d	ON e.DimID_OLD = d.'+@DimID+'
				   CROSS APPLY( VALUES' + @Cols + N') up(COLUMN_NAME ,Value)
				   WHERE e.EntityName = '''+ @EntityName +''''

		--SELECT @SQL_OLD
		EXEC(@SQL_OLD)
		---------------------------------------------------------------------------------------------
		--@SQL_NEW Unpivot using dynamic sql
		---------------------------------------------------------------------------------------------
		DROP TABLE IF EXISTS ##DimData_NEW;

		DECLARE @SQL_NEW NVARCHAR(MAX)
			SET @SQL_NEW = N'
				  SELECT TableName = ''' + @TableName + ''',Fact_DimName = e.EntityName, e.DimID_OLD, e.DimID_NEW, up.COLUMN_NAME, Value_NEW = up.Value
					INTO ##DimData_NEW
					FROM ##ReversalDetails AS e
					JOIN '+ @TableName +' AS d	ON e.DimID_NEW = d.'+@DimID+'
				   CROSS APPLY( VALUES' + @Cols + N') up(COLUMN_NAME ,Value)
				   WHERE e.EntityName = '''+ @EntityName +''''

		--SELECT @SQL_NEW
		EXEC(@SQL_NEW)
		---------------------------------------------------------------------------------------------
		--@SQL_NEW Unpivot using dynamic sql
		---------------------------------------------------------------------------------------------
		INSERT INTO ##ComparisonResult
			(TableName	
			,Fact_DimName
			,DimID_OLD	 
			,DimID_NEW	 
			,Description2 )
		SELECT
			 old.TableName
			,old.Fact_DimName
			,old.DimID_OLD	
			,old.DimID_NEW	
		    ,Description2 = REPLACE(old.TableName,'assumed.','') +' changed '+
							STRING_AGG ('('+ old.COLUMN_NAME COLLATE DATABASE_DEFAULT +': '+ ISNULL(old.Value_OLD,'NULL') +' -> '+ ISNULL(new.Value_NEW,'NULL') +')', ' , ')
		  FROM ##DimData_OLD		AS old
		  LEFT JOIN ##DimData_NEW	AS new	ON  old.TableName = new.TableName
											AND old.Fact_DimName = new.Fact_DimName
											AND old.DimID_OLD	 = new.DimID_OLD
											AND old.DimID_NEW	 = new.DimID_NEW
											AND old.COLUMN_NAME  = new.COLUMN_NAME
		WHERE ISNULL(old.Value_OLD,'NULL') <> ISNULL(new.Value_NEW,'NULL')
		GROUP BY
			 old.TableName
			,old.Fact_DimName
			,old.DimID_OLD	
			,old.DimID_NEW

		FETCH  NEXT FROM @Curr2 INTO @EntityName
	END
	CLOSE @Curr2
	DEALLOCATE @Curr2

	---------------------------------------------------------------------------------------------
	--UPDATE ReversalDetails
	---------------------------------------------------------------------------------------------
	UPDATE r
	   SET r.Description2 = cr.Description2 COLLATE DATABASE_DEFAULT
	  FROM EDW_PREPROD.assumed.ReversalDetails AS r
	 INNER JOIN ##ComparisonResult AS cr	ON  cr.Fact_DimName COLLATE database_default = r.EntityName 
											AND cr.DimID_OLD	COLLATE database_default = r.DimID_OLD 
											AND cr.DimID_NEW	COLLATE database_default = r.DimID_NEW 
	 WHERE r.Description2 IS NULL

	------------------------------------------------------------------------------------------------------
	--Log process
	------------------------------------------------------------------------------------------------------
	DECLARE @ProcessName		VARCHAR(100)= @v_ProcessName
	DECLARE @ProcessingStarted	DATETIME	= @v_ProcessingStarted
	DECLARE @ProcessingEnded	DATETIME	= GETDATE()
	DECLARE @SourceDataDate		DATETIME	= @v_SourceDataDate
	DECLARE @comment			VARCHAR(255)= @v_comment;
	DECLARE @LastIdentity		BIGINT		= SCOPE_IDENTITY()
	DECLARE @RowsProcessed		BIGINT		= (SELECT COUNT(*) 
												 FROM EDW_PREPROD.assumed.ReversalDetails 
												WHERE InsertedDate BETWEEN @ProcessingStarted AND @ProcessingEnded);
	EXEC ETL.dbo.update_etl_controller 
		 @ps_process_name			= @ProcessName
		,@pn_rows_processed			= @RowsProcessed
		,@pdt_data_datetime			= @SourceDataDate
		,@pdt_process_start_datetime= @ProcessingStarted
		,@pdt_process_end_datetime	= @ProcessingEnded
		,@pn_error_number			= 0
		,@ps_comment				= @comment
		,@pn_max_processed_event_id = @LastIdentity

	END TRY
BEGIN CATCH
			IF @@TRANCOUNT > 0
			BEGIN
				ROLLBACK
			END

		DECLARE @ErrorDescription	VARCHAR(8000) = CONCAT('Error: ', ERROR_NUMBER(), ' - ', ERROR_MESSAGE(), '; ', 'Occurred in procedure: ' + ERROR_PROCEDURE() + ', ', 'Line ', ERROR_LINE())
		DECLARE @ErrorNumber		INT = ERROR_NUMBER()
		DECLARE @ErrorMessage		VARCHAR(255) = ERROR_MESSAGE()
		DECLARE @ErrorSeverity		INT = ERROR_SEVERITY()
		DECLARE @ErrorState			INT = ERROR_STATE()
		DECLARE @ProcessNameC		VARCHAR(100) = OBJECT_SCHEMA_NAME(@@PROCID) + '.' + OBJECT_NAME(@@PROCID)
		DECLARE @ProcessingStartedC DATETIME = @v_ProcessingStarted
		DECLARE @ProcessingEndedC	DATETIME = GETDATE()
		DECLARE @SourceDataDateC	DATETIME = (SELECT [sql_date] FROM ETL.dbo.[day] WHERE today = 1)

		EXEC ETL.dbo.update_etl_controller 
			 @ps_process_name			= @ProcessNameC
			,@pn_rows_processed			= 0
			,@pdt_data_datetime			= @SourceDataDateC
			,@pdt_process_start_datetime= @ProcessingStartedC
			,@pdt_process_end_datetime	= @ProcessingEndedC
			,@pn_error_number			= @ErrorNumber
			,@ps_comment				= @ErrorMessage
			,@pn_max_processed_event_id = 0

		EXEC ETL.dbo.insert_error_log @process_name = @ProcessNameC
			,@object_name	= 0
			,@user_message	= @ErrorDescription
			,@status		= 0
			,@remedy		= 'Contact EDW team'

		PRINT @ErrorDescription
		--RAISERROR(@ErrorDescription, @ErrorSeverity, @ErrorState)
END CATCH
