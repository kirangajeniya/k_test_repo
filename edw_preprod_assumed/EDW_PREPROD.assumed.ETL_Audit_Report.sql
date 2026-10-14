-- Database: EDW_PREPROD
-- Schema: assumed
-- Procedure: ETL_Audit_Report


CREATE PROCEDURE [assumed].[ETL_Audit_Report] (@OverrideRecipients NVARCHAR(MAX) = NULL)
AS
BEGIN TRY
	/*
	DECLARE @OverrideRecipients NVARCHAR(MAX) = NULL
	--*/

    DROP TABLE IF EXISTS #Parameters

    -- define parameters as temp table
    SELECT ClosingEndDate = DATEADD(NANOSECOND, - 100, SYSDATETIME()),
        NewStartDate = SYSDATETIME(),
        recipients = ISNULL(@OverrideRecipients, erc.Recipients),
        servername = erc.EnvironmentName,
		SenderProfile = erc.SenderProfile,
        DefaultThreshold = 0.1,
        period_start = CONVERT(VARCHAR(10), (
                SELECT MIN([AccountingPeriodDate])
                FROM assumed.AuditResults a
                WHERE IsLatest = 1
            ), 126),
        period_end = CONVERT(VARCHAR(10), (
                SELECT MAX([AccountingPeriodDate])
                FROM assumed.AuditResults a
                WHERE IsLatest = 1
            ), 126)
    INTO #Parameters
	FROM EDW_Staging.assumed.EmailReportConfiguration erc
	WHERE erc.ReportName = 'Audit Report'

	IF NOT EXISTS (SELECT 1 FROM #Parameters)
	BEGIN
		;THROW 50000, 'Missing email configuration', 10
	END

    DROP TABLE IF EXISTS #MeasuresToIgnore;

    -- define measure that will be ignored 
    SELECT FactType,
        MeasureCode
    INTO #MeasuresToIgnore
    FROM (
        VALUES (
            'claims',
            'SUMMABLE_OS_LOSS'
        ),
            (
            'claims',
            'SUMMABLE_OS_LOSS_EXP'
        ),
            (
            'claims',
            'SUMMABLE_LOSS_EXP_PAID'
        ),
            (
            'underwriting',
            'SUMMABLE_UEPR'
        ),
            (
            'underwriting',
            'SUMMABLE_UEPR_RPT_CURR1'
        ),
            (
            'underwriting',
            'SUMMABLE_DAC'
        ),
            (
            'underwriting',
            'SUMMABLE_DAC_RPT_CURR1'
        ),
            (
            'underwriting',
            'SUMMABLE_DAC_RPT_CURR2'
        ),
            (
            'underwriting',
            'SUMMABLE_UEPR_RPT_CURR2'
        ),
            (
            'underwriting',
            'SUMMABLE_CEDED_DAC'
        ),
            (
            'underwriting',
            'SUMMABLE_CEDED_UEPR'
        )
		,('claims', 'FIRV_IBNR_BEGIN')
		,('claims', 'FIRV_IBNR_END')
    ) toIgnore(FactType, MeasureCode)

    DROP TABLE IF EXISTS #ReportData

    SELECT [AccountingPeriodDate] AS [Accounting_Period_Date],
        A.[FactType] AS [Fact_Type],
        CASE [BusinessType]
            WHEN 'C'
                THEN 'Ceded'
            WHEN 'A'
                THEN 'Assumed'
            ELSE ISNULL(A.[BusinessType], 'Unknown')
            END [Business_Type],
        ISNULL((
                SELECT source_name
                FROM Insight.dbo.sources
                WHERE source_key = [SourceSystemKey]
            ), 'Other') AS [Source_System],
        A.[MeasureCode] [Measure_Code],
        A.[RevenueCode] [Revenue_Code],
        CONVERT(NUMERIC(18, 2), ISNULL([SourceValue], 0)) [Source_Value],
        CONVERT(NUMERIC(18, 2), ISNULL([EDWValue], 0)) [EDW_Value],
        CONVERT(NUMERIC(18, 2), [DiffValue]) [Diff_Value],
        CONCAT_WS(';', CASE 
                WHEN i.FactType IS NOT NULL
                    THEN 'Ignore'
                WHEN ABS([DiffValue]) > prm.DefaultThreshold
                    THEN 'not OK'
                END, CASE 
                WHEN ISNULL([SourceSystemKey], 0) = 0
                    THEN 'Uncoded source system'
                END) [Result]
    INTO #ReportData
    FROM assumed.AuditResults A
    CROSS JOIN #Parameters prm
    LEFT JOIN #MeasuresToIgnore i
        ON A.MeasureCode = i.MeasureCode
            AND A.FactType = i.FactType
    WHERE A.IsLatest = 1
        AND A.SrcEnvironment IN ('SRC_UNDERWRITING', 'SRC_CLAIMS')

    -- calculate statistics
    DROP TABLE IF EXISTS #ReportStatistics

    SELECT DiffCount = SUM(CASE 
                WHEN [Result] LIKE '%Ignore%'
                    OR ABS([Diff_Value]) < DefaultThreshold
                    THEN 0
                ELSE 1
                END),
        IgnoreCount = SUM(CASE 
                WHEN [Result] LIKE '%Ignore%'
                    THEN 1
                ELSE 0
                END),
        TotalCount = COUNT(1)
    INTO #ReportStatistics
    FROM #ReportData
    CROSS JOIN #Parameters

    -- collect table data
    DECLARE @xmlData XML = (
            SELECT [Accounting_Period_Date],
                [Fact_Type],
                [Business_Type],
                [Source_System],
                [Measure_Code],
                [Revenue_Code],
                [Source_Value],
                [EDW_Value],
                [Diff_Value],
                [Result]
            FROM #ReportData Record
            WHERE [Result] NOT LIKE '%Ignore%'
            ORDER BY Fact_Type,
                Accounting_Period_Date,
                Source_System,
                Business_Type
            FOR XML auto,
                elements XSINIL
        )
    DECLARE @htmlTable NVARCHAR(MAX);

    SET @htmlTable = N'<table  border=''1'' style=''border-collapse:collapse''><tr>';

    -- add table headers
    SELECT @htmlTable = @htmlTable + N'<th>' + REPLACE(a.value('local-name(.)', 'NVARCHAR(MAX)'), '_', ' ') + N'</th>'
    FROM @xmlData.nodes('/Record[1]/*') AS t(a);

    SET @htmlTable = @htmlTable + N'</tr>' + CHAR(13) + CHAR(10);

    -- add table rows
    SELECT @htmlTable = @htmlTable + N'<tr>' + (
            SELECT '<td>' + ISNULL(t.c.value('.', 'NVARCHAR(MAX)'), '') + '</td>' AS [td]
            FROM a.nodes('*') AS t(c)
            FOR XML PATH(''),
                TYPE
        ).value('.', 'NVARCHAR(MAX)') + N'</tr>' + CHAR(13) + CHAR(10)
    FROM @xmlData.nodes('/Record') AS t(a);

    SET @htmlTable = @htmlTable + N'</table>';

    -- Compose message
    DECLARE @subj NVARCHAR(MAX)
    DECLARE @header NVARCHAR(MAX)
    DECLARE @footer NVARCHAR(MAX)
    DECLARE @recipients NVARCHAR(MAX)
	DECLARE @ProfileName SYSNAME

    SELECT @subj = FORMATMESSAGE('Assumed data (%s) audit alert - %s audit between EDW and source systems (TIRS and Openbox) contains differences.', servername, CONCAT (
                period_start,
                '-' + NULLIF(period_end, period_start)
            )),
        @header = FORMATMESSAGE('<p>The audit of Assumed data between EDW and source systems (TIRS and Openbox) for %d measures has found %d differences.', TotalCount - IgnoreCount, DiffCount) + '
' + FORMATMESSAGE('<p>There are %d measures in total, but %d measures are not currently being compared.</p><p>Please see the table below for details:</p>', TotalCount, IgnoreCount),
        @footer = FORMATMESSAGE('<br><br><span style="font-size:12px;font-style:italic;color:#827a78">This email was sent using an unmonitored mailbox from %s environment. Please do not reply to this email.<br>generated by <b>assumed.ETL_Audit_Report</b></span><br><br>Thank You,<br><b>EDW Team</b>', servername),
        @recipients = recipients
		,@ProfileName = SenderProfile
    FROM #Parameters
    CROSS JOIN #ReportStatistics

    DECLARE @body NVARCHAR(max) = CONCAT (
            '<html><head><style></style></head><body>',
            @header,
            @htmlTable,
            @footer,
            '</body></html>'
        )

    -- Send email
    EXEC msdb.dbo.sp_send_dbmail @profile_name = @ProfileName,
        @body = @body,
        @recipients = @recipients,
        @subject = @subj,
        @body_format = 'HTML',
        @file_attachments = NULL

    DECLARE @ProcessName VARCHAR(100) = OBJECT_SCHEMA_NAME(@@PROCID) + '.' + OBJECT_NAME(@@PROCID)
    DECLARE @RowsProcessed BIGINT = (
            SELECT TotalCount
            FROM #ReportStatistics
        )
    DECLARE @LastIdentity BIGINT = SCOPE_IDENTITY()
    DECLARE @ProcessingStarted DATETIME = (
            SELECT p.NewStartDate
            FROM #Parameters p
        )
    DECLARE @ProcessingEnded DATETIME = GETDATE()
    DECLARE @SourceDataDate DATETIME = (
            SELECT [sql_date]
            FROM ETL.dbo.[day]
            WHERE today = 1
        )

    EXEC ETL.dbo.update_etl_controller @ps_process_name = @ProcessName,
        @pn_rows_processed = @RowsProcessed,
        @pdt_data_datetime = @SourceDataDate,
        @pdt_process_start_datetime = @ProcessingStarted,
        @pdt_process_end_datetime = @ProcessingEnded,
        @pn_error_number = 0,
        @ps_comment = NULL,
        @pn_max_processed_event_id = @LastIdentity
END TRY

BEGIN CATCH
    IF @@TRANCOUNT > 0
    BEGIN
        ROLLBACK
    END

    DECLARE @ErrorDescription VARCHAR(8000) = CONCAT (
            'Error: ',
            ERROR_NUMBER(),
            ' - ',
            ERROR_MESSAGE(),
            '; ',
            'Occurred in procedure: ' + ERROR_PROCEDURE() + ', ',
            'Line ',
            ERROR_LINE()
        )
    DECLARE @ErrorNumber INT = ERROR_NUMBER()
    DECLARE @ErrorMessage VARCHAR(8000) = ERROR_MESSAGE()
    DECLARE @ErrorSeverity INT = ERROR_SEVERITY()
    DECLARE @ErrorState INT = ERROR_STATE()
    DECLARE @ProcessNameC VARCHAR(100) = OBJECT_SCHEMA_NAME(@@PROCID) + '.' + OBJECT_NAME(@@PROCID)
    DECLARE @ProcessingStartedC DATETIME = (
            SELECT p.NewStartDate
            FROM #Parameters p
        )
    DECLARE @ProcessingEndedC DATETIME = GETDATE()
    DECLARE @SourceDataDateC DATETIME = (
            SELECT [sql_date]
            FROM ETL.dbo.[day]
            WHERE today = 1
        )

    EXEC ETL.dbo.update_etl_controller @ps_process_name = @ProcessNameC,
        @pn_rows_processed = 0,
        @pdt_data_datetime = @SourceDataDateC,
        @pdt_process_start_datetime = @ProcessingStartedC,
        @pdt_process_end_datetime = @ProcessingEndedC,
        @pn_error_number = @ErrorNumber,
        @ps_comment = @ErrorDescription,
        @pn_max_processed_event_id = 0

    EXEC ETL.dbo.insert_error_log @process_name = @ProcessNameC,
        @object_name = 0,
        @user_message = @ErrorDescription,
        @status = 0,
        @remedy = 'Contact EDW team'

    -- do not raise error at this point
    PRINT @ErrorDescription
        --RAISERROR (
        --        @ErrorMessage,
        --        @ErrorSeverity,
        --        @ErrorState
        --    )
END CATCH

RETURN 0
