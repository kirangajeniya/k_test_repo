-- Database: EDW_PREPROD
-- Schema: assumed
-- Procedure: SendReversalsUncodedReport

CREATE PROCEDURE assumed.SendReversalsUncodedReport
--DECLARE
	@OverrideRecipients NVARCHAR(MAX) = NULL
AS
BEGIN TRY
	-----------------------------------------------------------------------
    --#Parameters - define parameters
	-----------------------------------------------------------------------
    DROP TABLE IF EXISTS #Parameters
    SELECT
        ProcessName			= ISNULL(OBJECT_SCHEMA_NAME(@@PROCID) + '.' + OBJECT_NAME(@@PROCID), 'assumed.SendReversalsUncodedReport'),
		ProcessStartDate	= SYSDATETIME(),
		SenderProfile		= erc.SenderProfile,
        ServerName			= erc.EnvironmentName,
        Recipients			= ISNULL(@OverrideRecipients, erc.Recipients),
		------
        ReportDate			= CONVERT(DATE,SYSDATETIME()),
		RowsCnt				= CONVERT(INT,0)
    INTO #Parameters
	FROM EDW_Staging.assumed.EmailReportConfiguration erc
	WHERE erc.ReportName = 'Reversals and Uncoded Report'


	IF NOT EXISTS (SELECT 1 FROM #Parameters)
	BEGIN
		;THROW 50000, 'Missing email configuration', 10
	END
	-----------------------------------------------------------------------
	-- #ReportData (Reversals)
	-----------------------------------------------------------------------
    DROP TABLE IF EXISTS #ReportData_Reversals

	SELECT Fact_CreatedDate = CONVERT(VARCHAR(30),f.FactCreatedDate,121), Table_Name = f.TableName, f.Actions, Entity_Name = f.EntityName, Rows_Count = f.RowsCount
	  INTO #ReportData_Reversals
	  FROM EDW_PREPROD.assumed.v_ReversalDetails	AS f
	 CROSS JOIN #Parameters					AS p
	 WHERE CONVERT(DATE,f.FactCreatedDate) = p.ReportDate

	UPDATE #Parameters SET RowsCnt = RowsCnt+ROWCOUNT_BIG();
	-----------------------------------------------------------------------
    -- collect table data (Reversals)
 	-----------------------------------------------------------------------
    DECLARE @htmlTable_Rev	NVARCHAR(MAX);
	DECLARE @xmlData_Rev	XML = ( SELECT Fact_CreatedDate, Table_Name, Actions, Entity_Name, Rows_Count
									  FROM #ReportData_Reversals Record
									 ORDER BY
										   Fact_CreatedDate DESC, Table_Name, Actions, Rows_Count DESC, Entity_Name
									FOR XML auto, elements XSINIL	)

    SET @htmlTable_Rev = N'<table  border=''1'' style=''border-collapse:collapse;font-size:12px''><tr>';

    -- table headers
    SELECT @htmlTable_Rev = @htmlTable_Rev + N'<th min-width:40">' + REPLACE(a.value('local-name(.)', 'NVARCHAR(MAX)'), '_', ' ') + N'</th>'
      FROM @xmlData_Rev.nodes('/Record[1]/*') AS t(a);

    SET @htmlTable_Rev = @htmlTable_Rev + N'</tr>' + CHAR(13) + CHAR(10);

    -- table rows
    SELECT @htmlTable_Rev = @htmlTable_Rev + N'<tr>' + (
            SELECT '<td style="min-width:180px;font-size:12px">' + ISNULL(t.c.value('.', 'NVARCHAR(MAX)'), '') + '</td>' AS [td]
            FROM a.nodes('*') AS t(c)
            FOR XML PATH(''), TYPE				).value('.', 'NVARCHAR(MAX)') + N'</tr>' + CHAR(13) + CHAR(10)
    FROM @xmlData_Rev.nodes('/Record') AS t(a);

    SET @htmlTable_Rev = @htmlTable_Rev + N'</table>'
	-----------------------------------------------------------------------
	-- #ReportData (Uncoded)
	-----------------------------------------------------------------------
    DROP TABLE IF EXISTS #ReportData_Uncoded

	SELECT Uncoded_CreatedDate = u.StartDate, Table_Name = u.TableName, Actions, Entity_Name = u.EntityName, Rows_Count = SUM(RowsCount) 
	  INTO #ReportData_Uncoded
	  FROM EDW_Staging.assumed.v_UncodedDimensions	AS u
	 WHERE u.EndDate = '9999-12-31'
	 GROUP BY u.StartDate, u.TableName, Actions, u.EntityName

	UPDATE #Parameters SET RowsCnt = RowsCnt+ROWCOUNT_BIG();
	-----------------------------------------------------------------------
    -- collect table data (Uncoded)
 	-----------------------------------------------------------------------
    DECLARE @htmlTable_Un	NVARCHAR(MAX);
	DECLARE @xmlData_Un		XML = ( SELECT Uncoded_CreatedDate, Table_Name, Actions, Entity_Name, Rows_Count
									  FROM #ReportData_Uncoded Record
									 ORDER BY
										   Uncoded_CreatedDate DESC, Table_Name, Actions, Rows_Count DESC, Entity_Name
									FOR XML auto, elements XSINIL	)

    SET @htmlTable_Un = N'<table  border=''1'' style=''border-collapse:collapse;font-size:12px''><tr>';

    -- table headers
    SELECT @htmlTable_Un = @htmlTable_Un + N'<th min-width:40">' + REPLACE(a.value('local-name(.)', 'NVARCHAR(MAX)'), '_', ' ') + N'</th>'
      FROM @xmlData_Un.nodes('/Record[1]/*') AS t(a);

    SET @htmlTable_Un = @htmlTable_Un + N'</tr>' + CHAR(13) + CHAR(10);

    -- table rows
    SELECT @htmlTable_Un = @htmlTable_Un + N'<tr>' + (
            SELECT '<td style="min-width:180px;font-size:12px">' + ISNULL(t.c.value('.', 'NVARCHAR(MAX)'), '') + '</td>' AS [td]
            FROM a.nodes('*') AS t(c)
            FOR XML PATH(''), TYPE				).value('.', 'NVARCHAR(MAX)') + N'</tr>' + CHAR(13) + CHAR(10)
    FROM @xmlData_Un.nodes('/Record') AS t(a);

    SET @htmlTable_Un = @htmlTable_Un + N'</table>'
	-------------------------------------------------------------------------
    -- Compose message
	-------------------------------------------------------------------------
    DECLARE @Subj			NVARCHAR(MAX)
    DECLARE @SubHeader_Rev	NVARCHAR(MAX)
    DECLARE @SubHeader_Un	NVARCHAR(MAX)
    DECLARE @Header			NVARCHAR(MAX)
    DECLARE @Footer			NVARCHAR(MAX)
    DECLARE @Recipients		NVARCHAR(MAX)
	DECLARE @ProfileName	SYSNAME

    SELECT
        @Header		  = FORMATMESSAGE('<p>%s Reversals and Uncoded Report %s</p>', ServerName, CONVERT(VARCHAR, ReportDate, 23)),
		@Subj		  = FORMATMESSAGE('%s Reversals and Uncoded Report %s', ServerName, CONVERT(VARCHAR, ReportDate, 23)),
		@SubHeader_Rev = FORMATMESSAGE('<p><span style="font-weight:bold;color:green">REVERSALS:</p>'),
		@SubHeader_Un = FORMATMESSAGE('<p><span style="font-weight:bold;color:green">UNCODED:</p>'),
        @Footer		  = FORMATMESSAGE('<br><br><span style="font-size:11px;font-style:italic;color:#827a78">This email was sent using an unmonitored mailbox from %s environment. Please do not reply to this email.<br>generated by <b>%s</b></span><br><br>Thank You,<br><b>EDW Team</b>', ServerName, ProcessName),
        @Recipients   = Recipients,
		@ProfileName  = SenderProfile
    FROM #Parameters

    DECLARE @body NVARCHAR(MAX) = CONCAT ('<html><head><style></style></head><body>',
										  @Header,
										  @SubHeader_Un,
										  IIF((SELECT COUNT(*) FROM #ReportData_Uncoded)=0, 'No data', @HtmlTable_Un),
										  @SubHeader_Rev,
										  IIF((SELECT COUNT(*) FROM #ReportData_Reversals)=0, 'No data', @HtmlTable_Rev),
										  @Footer,
										 '</body></html>'
										)
	-----------------------------------------------------------------------
	-- send email IF IntegrityCheck = 1
	-----------------------------------------------------------------------
	IF (SELECT EDW_Staging.assumed.Get_IntegritySourceSetCheck() ) = 1
	BEGIN
		EXEC msdb.dbo.sp_send_dbmail 
			@profile_name	= @ProfileName,
			@body			= @Body,
			@Recipients		= @Recipients,
			@subject		= @Subj,
			@body_format	= 'HTML',
			@file_attachments = NULL
	END
	-------------------------------------------------------------------------

    DECLARE @ProcessName		VARCHAR(100)= (SELECT ProcessName FROM #Parameters)
    DECLARE @ProcessingStarted	DATETIME	= (SELECT ProcessStartDate FROM #Parameters)
    DECLARE @ProcessingEnded	DATETIME	= GETDATE()
    DECLARE @RowsProcessed		BIGINT		= (SELECT RowsCnt FROM #Parameters)
    DECLARE @LastIdentity		BIGINT		= SCOPE_IDENTITY()
    DECLARE @SourceDataDate		DATETIME	= (SELECT [sql_date] FROM ETL.dbo.[day] WHERE today = 1)
	DECLARE @Comment			VARCHAR(MAX)= 'IntegritySourceSetCheck='+CONVERT(VARCHAR,(SELECT EDW_Staging.assumed.Get_IntegritySourceSetCheck() ))

    EXEC ETL.dbo.update_etl_controller
		@ps_process_name			= @ProcessName,
        @pn_rows_processed			= @RowsProcessed,
        @pdt_data_datetime			= @SourceDataDate,
        @pdt_process_start_datetime = @ProcessingStarted,
        @pdt_process_end_datetime	= @ProcessingEnded,
        @pn_error_number			= 0,
        @ps_comment					= @Comment,
        @pn_max_processed_event_id	= @LastIdentity

END TRY

BEGIN CATCH
    IF @@TRANCOUNT > 0
    BEGIN
        ROLLBACK
    END

    DECLARE @ProcessNameC		VARCHAR(100)	= (SELECT ProcessName  FROM #Parameters)
    DECLARE @ProcessingStartedC DATETIME		= (SELECT ProcessStartDate FROM #Parameters)
    DECLARE @ProcessingEndedC	DATETIME		= GETDATE()
    DECLARE @SourceDataDateC	DATETIME		= (SELECT [sql_date] FROM ETL.dbo.[day] WHERE today = 1)
    DECLARE @ErrorNumber		INT				= ERROR_NUMBER()
    DECLARE @ErrorMessage		VARCHAR(8000)	= ERROR_MESSAGE()
    DECLARE @ErrorSeverity		INT				= ERROR_SEVERITY()
    DECLARE @ErrorState			INT				= ERROR_STATE()
    DECLARE @ErrorDescription	VARCHAR(8000)	= CONCAT('Error: ',ERROR_NUMBER(),' - ',ERROR_MESSAGE(),'; ',
														 'Occurred in procedure: ' + ERROR_PROCEDURE() + ', ',
														 'Line ',ERROR_LINE()
														)
    EXEC ETL.dbo.update_etl_controller
		@ps_process_name			= @ProcessNameC,
        @pn_rows_processed			= 0,
        @pdt_data_datetime			= @SourceDataDateC,
        @pdt_process_start_datetime = @ProcessingStartedC,
        @pdt_process_end_datetime	= @ProcessingEndedC,
        @pn_error_number			= @ErrorNumber,
        @ps_comment					= @ErrorDescription,
        @pn_max_processed_event_id	= 0

    EXEC ETL.dbo.insert_error_log
		@process_name	= @ProcessNameC,
        @object_name	= 0,
        @user_message	= @ErrorDescription,
        @status			= 0,
        @remedy			= 'Contact EDW team'

    -- Do not raise error at this point
    PRINT @ErrorDescription
        --RAISERROR (@ErrorMessage, @ErrorSeverity, @ErrorState)
END CATCH
