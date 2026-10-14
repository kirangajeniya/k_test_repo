-- Database: EDW_PREPROD
-- Schema: assumed
-- Procedure: ETL_Audit


CREATE PROCEDURE [assumed].[ETL_Audit]
AS
/**************************************************************************************************************************************************************************************************************************
**     Name:     [assumed].[ETL_Audit] 
**     Desc:     Inserts to the Assumed.AuditResults from EDW, Source systems, and OLD table
*************************************************************************************************************************************************************************************************************************/
BEGIN TRY
    SET NOCOUNT ON

    DROP TABLE IF EXISTS #Parameters

    SELECT ClosingEndDate = DATEADD(NANOSECOND, - 100, SYSDATETIME()),
        NewStartDate = SYSDATETIME()
    INTO #Parameters

    DECLARE @start_date DATE;
    DECLARE @end_date DATE;

    /*
   Determine Date Range:
   - The procedure calculates the date range (`@start_date` to `@end_date`) for the accounting periods that require auditing based on current period data and the status of these periods in the control table.   
	   - It identifies the earliest accounting period with `etl_audit_control.STATUS = 1` to establish the starting point for the auditing interval.
	   - The @end_date is the latest date within the same sequence of accounting periods with `etl_audit_control.STATUS = 1`
       - At least one current accounting_period will be selected based on Insight.dbo.accounting_periods
*/
    WITH AUDIT_CONTROL
    AS (
        SELECT AccountingPeriodDate,
            1 [group_tag],
            1 [status]
        FROM (
            SELECT CONVERT(DATE, ap.accounting_period_date) AS AccountingPeriodDate,
                CAST(DATEADD(DAY, 1, LAG(ap.accounting_period_close_date) OVER (
                            ORDER BY ap.accounting_period_key
                        )) AS DATE) AS AccountingStartDate,
                CAST(ap.accounting_period_close_date AS DATE) AS AccountingEndDate
            FROM Insight.dbo.accounting_periods ap
        ) [Periods]
        WHERE CAST(DATEADD(DAY, - 1, GETDATE()) AS DATE) BETWEEN AccountingStartDate
                AND AccountingEndDate       
    )
    SELECT @start_date = MIN(AccountingPeriodDate),
        @end_date = MAX(AccountingPeriodDate)
    FROM AUDIT_CONTROL
    WHERE [group_tag] = 1;

    PRINT CONCAT (
            'staging audit from: ',
            @start_date,
            ' to ',
            @end_date
        );

    /*
    Prepare for Audit:
    - Any existing staging audit results for 'Underwriting' are cleared to ensure that only fresh data is considered in the audit process.
 */
    -- cleanup staging
    DELETE
    FROM assumed.StageAuditResults
    WHERE FactType = 'Underwriting';

    /*
   Collect Audit Data:
   - The procedure gathers audit data from several sources/functions for 'Underwriting' within the calculated date range.
   - This data is compiled into a staging area (`assumed.StageAuditResults`) to facilitate comparison.
 */
    INSERT INTO assumed.StageAuditResults (
        [AccountingPeriodDate],
        [TransactionDate],
        [BusinessType],
        [FactType],
        [MeasureCode],
        [RevenueCode],
        [AuditValue],
        [SourceSystemKey],
        [Environment]
    )
    SELECT [AccountingPeriodDate],
        [TransactionDate],
        [BusinessType],
        [FactType],
        [MeasureCode],
        [RevenueCode],
        [AuditValue],
        [SourceSystemKey],
        [Environment]
    FROM assumed.Get_Audit_FactUnderWriting(@start_date, @end_date)
    
    UNION ALL
    
    SELECT [AccountingPeriodDate],
        [TransactionDate],
        [BusinessType],
        [FactType],
        [MeasureCode],
        [RevenueCode],
        [AuditValue],
        [SourceSystemKey],
        [Environment]
    FROM assumed.Get_Audit_RS_TIRS_UNDERWRITING(@start_date, @end_date)
    
    UNION ALL
    
    SELECT [AccountingPeriodDate],
        [TransactionDate],
        [BusinessType],
        [FactType],
        [MeasureCode],
        [RevenueCode],
        [AuditValue],
        [SourceSystemKey],
        [Environment]
    FROM assumed.Get_Audit_OPENBOX_UW_Staging(@start_date, @end_date)
    
    UNION ALL
    
    SELECT [AccountingPeriodDate],
        [TransactionDate],
        [BusinessType],
        [FactType],
        [MeasureCode],
        [RevenueCode],
        [AuditValue],
        [SourceSystemKey],
        [Environment]
    FROM assumed.Get_Audit_TIRS_UW_Staging_UEPR_DAC(@start_date, @end_date)
    
    UNION ALL
    
    SELECT [AccountingPeriodDate],
        [TransactionDate],
        [BusinessType],
        [FactType],
        [MeasureCode],
        [RevenueCode],
        [AuditValue],
        [SourceSystemKey],
        [Environment]
    FROM assumed.Get_Audit_TIRS_UW_Staging(@start_date, @end_date);

    /*****    CLAIMS Auditing  STAGING Script START  ******/
    DELETE
    FROM assumed.StageAuditResults
    WHERE FactType = 'Claims';

    /*
   Collect Audit Data:
   - The procedure gathers audit data from several sources/functions for 'Underwriting' within the calculated date range.
   - This data is compiled into a staging area (`assumed.StageAuditResults`) to facilitate comparison.
 */
    INSERT INTO assumed.StageAuditResults (
        [AccountingPeriodDate],
        [TransactionDate],
        [BusinessType],
        [FactType],
        [MeasureCode],
        [RevenueCode],
        [AuditValue],
        [SourceSystemKey],
        [Environment]
    )
    SELECT [AccountingPeriodDate],
        [TransactionDate],
        [BusinessType],
        [FactType],
        [MeasureCode],
        [RevenueCode],
        [AuditValue],
        [SourceSystemKey],
        [Environment]
    FROM assumed.Get_Audit_FactClaim(@start_date, @end_date)
    
    UNION ALL
    
    SELECT [AccountingPeriodDate],
        [TransactionDate],
        [BusinessType],
        [FactType],
        [MeasureCode],
        [RevenueCode],
        [AuditValue],
        [SourceSystemKey],
        [Environment]
    FROM assumed.Get_Audit_TIRS_Claims_Staging(@start_date, @end_date)
    
    UNION ALL
    
    SELECT [AccountingPeriodDate],
        [TransactionDate],
        [BusinessType],
        [FactType],
        [MeasureCode],
        [RevenueCode],
        [AuditValue],
        [SourceSystemKey],
        [Environment]
    FROM assumed.Get_Audit_OPENBOX_Claims_Staging(@start_date, @end_date)
	
	UNION ALL
    
    SELECT [AccountingPeriodDate],
        [TransactionDate],
        [BusinessType],
        [FactType],
        [MeasureCode],
        [RevenueCode],
        [AuditValue],
        [SourceSystemKey],
        [Environment]
    FROM assumed.Get_Audit_RS_TIRS_Claims(@start_date, @end_date);
	

    /*****    CLAIMS Auditing STAGING Script END  ******/
    /*
   Delete Outdated Results:
   - Previous audit results for the current date and selected accounting periods are removed from the main 
   audit results table (`assumed.AuditResults`).
*/
    DELETE
    FROM [assumed].[AuditResults]
    WHERE TransactionDate = CAST(GETDATE() AS DATE)
        AND AccountingPeriodDate BETWEEN @start_date
            AND @end_date
        AND FactType = 'Underwriting'

    /*
   Mark Prior Results:
   - Past records are updated to indicate they are no longer the latest (`IsLatest = 0`), thus preparing the system to differentiate between current and historical data.
*/
    UPDATE prior_log
    SET IsLatest = 0
    FROM [assumed].[AuditResults] prior_log
    WHERE IsLatest <> 0
        AND FactType = 'Underwriting'

    /*
    Insert Latest Audit Results:
   - The final audit results for 'Underwriting' are inserted into the audit results table (`AuditResults`).
   - The results include differences between expected (EDW) and source system values, thus indicating discrepancies.
   - There are two source environments: RS_TIRS_UNDERWRITING, and SRC_UNDERWRITING
   */
    INSERT INTO assumed.AuditResults (
        [InsertDatetime],
        [TransactionDate],
        [AccountingPeriodDate],
        [BusinessType],
        [FactType],
        [MeasureCode],
        [RevenueCode],
        [SourceSystemKey],
        [EDWValue],
        [SourceValue],
        [DiffValue],
        [IsLatest],
        [Description],
        [SrcEnvironment]
    )
    SELECT [InsertDatetime],
        [TransactionDate],
        [AccountingPeriodDate],
        [BusinessType],
        [FactType],
        [MeasureCode],
        [RevenueCode],
        [SourceSystemKey],
        [EDWValue],
        [SourceValue],
        [DiffValue],
        [IsLatest],
        [Description],
        'RS_TIRS_UNDERWRITING'
    FROM assumed.Get_AuditComparison('Underwriting', 'RS_TIRS_UNDERWRITING')
    
    UNION ALL
    
    SELECT [InsertDatetime],
        [TransactionDate],
        [AccountingPeriodDate],
        [BusinessType],
        [FactType],
        [MeasureCode],
        [RevenueCode],
        [SourceSystemKey],
        [EDWValue],
        [SourceValue],
        [DiffValue],
        [IsLatest],
        [Description],
        'SRC_UNDERWRITING'
    FROM assumed.Get_AuditComparison('Underwriting', 'SRC_UNDERWRITING')

    /********  CLAIMS AUDIT FINAL START  ********/
    /*
   Delete Outdated Results:
   - Previous audit results for the current date and selected accounting periods are removed from the main 
   audit results table (`assumed.AuditResults`).
*/
    DELETE
    FROM [assumed].[AuditResults]
    WHERE TransactionDate = CAST(GETDATE() AS DATE)
        AND AccountingPeriodDate BETWEEN @start_date
            AND @end_date
        AND FactType = 'Claims'

    /*
   Mark Prior Results:
   - Past records are updated to indicate they are no longer the latest (`IsLatest = 0`), thus preparing the system to differentiate between current and historical data.
*/
    UPDATE prior_log
    SET IsLatest = 0
    FROM [assumed].[AuditResults] prior_log
    WHERE IsLatest <> 0
        AND FactType = 'Claims'

    /*
    Insert Latest Audit Results:
   - The final audit results for 'Claims' are inserted into the audit results table (`AuditResults`).
   - The results include differences between expected (EDW) and source system values, thus indicating discrepancies.
   - There are two source environments: EDW_PREPROD(FACT), and SRC_CLAIMS
   */
    INSERT INTO assumed.AuditResults (
        [InsertDatetime],
        [TransactionDate],
        [AccountingPeriodDate],
        [BusinessType],
        [FactType],
        [MeasureCode],
        [RevenueCode],
        [SourceSystemKey],
        [EDWValue],
        [SourceValue],
        [DiffValue],
        [IsLatest],
        [Description],
        [SrcEnvironment]
    )
    SELECT [InsertDatetime],
        [TransactionDate],
        [AccountingPeriodDate],
        [BusinessType],
        [FactType],
        [MeasureCode],
        [RevenueCode],
        [SourceSystemKey],
        [EDWValue],
        [SourceValue],
        [DiffValue],
        [IsLatest],
        [Description],
        'SRC_CLAIMS'
    FROM assumed.Get_AuditComparison('Claims', 'SRC_CLAIMS')

	UNION ALL

	SELECT [InsertDatetime],
        [TransactionDate],
        [AccountingPeriodDate],
        [BusinessType],
        [FactType],
        [MeasureCode],
        [RevenueCode],
        [SourceSystemKey],
        [EDWValue],
        [SourceValue],
        [DiffValue],
        [IsLatest],
        [Description],
        'RS_TIRS_CLAIMS'
    FROM assumed.Get_AuditComparison('Claims', 'RS_TIRS_CLAIMS')


    /********  CLAIMS AUDIT FINAL END  ********/
    DECLARE @ProcessName VARCHAR(100) = OBJECT_SCHEMA_NAME(@@PROCID) + '.' + OBJECT_NAME(@@PROCID)
    DECLARE @RowsProcessed BIGINT = COALESCE((
                SELECT COUNT(0)
                FROM assumed.StageAuditResults
            ), 0)
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
