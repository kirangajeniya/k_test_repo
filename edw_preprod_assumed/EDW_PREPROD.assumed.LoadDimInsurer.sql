-- Database: EDW_PREPROD
-- Schema: assumed
-- Procedure: LoadDimInsurer

CREATE PROCEDURE [assumed].[LoadDimInsurer]
AS
BEGIN
SET NOCOUNT ON
	DROP TABLE IF EXISTS #Parameters

	SELECT ClosingValidTo = DATEADD(NANOSECOND, -100, SYSDATETIME())
		,NewValidFrom = SYSDATETIME()
	INTO #Parameters

	-- Staging logic
	
	DROP TABLE IF EXISTS #DimInsurer

	DROP TABLE IF EXISTS #accounting_periods
	
	
/* Commented as FDR team wanted more fields - comment START
SELECT P2.accounting_period_date as reg_date, isnull(P1.accounting_period_close_date+1,'') Accounting_Start_Date, P2.accounting_period_close_date as Accounting_End_Date 
		into #accounting_periods FROM Insight.dbo.accounting_periods P2 left join
		Insight.dbo.accounting_periods P1 on P2.accounting_period_key =P1.accounting_period_key+1;

		select * into #DimInsurer from(
		SELECT distinct  TIM.[InsurerCode],H.RPT_OFF_NAME FROM  #accounting_periods P 
			inner join edw_preprod.dbo.T_Code_history H on DATEADD(DAY,1,P.Accounting_End_Date) > H.START_DATE and DATEADD(DAY,1,P.Accounting_End_Date) < H.end_date
			left join edw_staging..[TIRS_InsurerCodeMapping] TIM on H.RPT_OFF_NAME= TIM.[rpt_ofc_nm]
			LEFT JOIN EDW_Staging..TIRS_ActuarialLobMapping AM ON AM.rpt_ofc_nm=H.RPT_OFF_NAME AND AM.division_nm=H.DIV_NAME AND AM.dept_nm=H.DEPT_NAME AND AM.sub_dept_nm=H.SUB_DEPT_NAME AND AM.UNDERWRITING_YEAR=RIGHT(RTRIM(h.Contract_NBR),4) COLLATE DATABASE_DEFAULT
			LEFT JOIN EDW_Staging..TIRS_ActuarialLobMapping_Exceptions AME ON AME.CONTRACT_NBR=H.Contract_NBR 
			WHERE P.reg_date < DATEADD(MONTH,1,GETDATE()) and TIM.[InsurerCode] is not null

			union

		select distinct insurercode,rpt_off_name from  edw_preprod.dbo.MAP_CONTRACT_EDW with(nolock) 
		where plcy_SRC in('OPENBOX','TIRS') and insurercode is not null
		
		union

		select 'Uncoded','Uncoded')Ins;
		--comment END
		*/



-- New code written as per FDR need
SELECT DISTINCT InsurerCode AS InsurerCode, 
	   TRIM(InsurerName) AS InsurerName ,   
	   si.LegalName AS  InsurerLegalName,  
	   si.Address AS InsurerAddress,
	   MCE.SOURCE_KEY AS SourceSysKey,
	   MCE.SourceInsurerCode AS SourceInsurerCode
	   into #DimInsurer
	
 FROM EDW_PREPROD.dbo.MAP_CONTRACT_EDW mce
LEFT JOIN DM_DataStandard.dbo.STG_INSURER si
	ON mce.SourceInsurerCode = CompanyCode COLLATE DATABASE_DEFAULT
	AND InsurerFlag ='Y' 
	AND ISNULL(CompanyCode, '') NOT IN ('$NOOID','-9999','Not classified at this level','')
WHERE END_DATE = '9999-12-31' AND InsurerName is NOT NULL AND InsurerCode IS NOT NULL AND MCE.source_key IN(1,4)
	
		-- Loading logic
	ALTER TABLE #DimInsurer ADD DataHash BINARY(20) NULL;
	--select * from #DimInsurer

	--UPDATE s
	--SET DataHash = 0x0000000000000000000000000000000000000000
	--FROM #DimInsurer s

	UPDATE s
	SET DataHash = HASHBYTES('SHA1', CONCAT('|',s.InsurerAddress,'|',s.SourceInsurerCode))
	FROM #DimInsurer s

	DROP TABLE IF EXISTS #LoadOperation

	CREATE TABLE #LoadOperation
	(InsurerCode VARCHAR(20) COLLATE DATABASE_DEFAULT NULL
	,SourceSysKey smallint NOT NULL
	,Operation CHAR(1) NOT NULL
	,UNIQUE (InsurerCode,SourceSysKey)
	)

	INSERT INTO #LoadOperation
		(InsurerCode
		,SourceSysKey
		,Operation
		)
	SELECT InsurerCode = COALESCE(t.InsurerCode COLLATE DATABASE_DEFAULT, s.InsurerCode COLLATE DATABASE_DEFAULT)
		   ,SourceSysKey = COALESCE(t.SourceSysKey, s.SourceSysKey)
		   ,Operation = CASE WHEN t.DimInsurerID IS NULL THEN 'I' WHEN s.DataHash IS NULL THEN 'D' ELSE 'U' END
	FROM (
		SELECT t.*
		FROM assumed.DimInsurer t
		WHERE t.EndDate = '31 Dec 9999'
		) t
	FULL JOIN #DimInsurer s
		ON COALESCE(s.InsurerCode, '^&*') = COALESCE(t.InsurerCode, '^&*') COLLATE DATABASE_DEFAULT
		AND COALESCE(s.SourceSysKey, -1) = COALESCE(t.SourceSysKey, -1)
	WHERE t.DataHash IS NULL
		OR s.DataHash IS NULL
		OR t.DataHash != s.DataHash

	UPDATE t
	SET EndDate = p.ClosingValidTo
	FROM assumed.DimInsurer t
	INNER JOIN #LoadOperation lo
		ON COALESCE(lo.InsurerCode, '^&*') = COALESCE(t.InsurerCode, '^&*')
		AND COALESCE(lo.SourceSysKey, -1) = COALESCE(t.SourceSysKey, -1)
		AND lo.Operation = 'U'
	CROSS JOIN #Parameters p
	WHERE t.EndDate = '31 Dec 9999'

	INSERT INTO assumed.DimInsurer
		(StartDate
		,InsurerCode
		,InsurerName
		,InsurerLegalName
		,InsurerAddress
		,SourceSysKey
		,DataHash
		,SourceInsurerCode
		)
	SELECT StartDate = p.NewValidFrom
		,s.InsurerCode
		,s.InsurerName
		,s.InsurerLegalName
		,s.InsurerAddress
		,s.SourceSysKey
		,s.DataHash
		,s.SourceInsurerCode
	FROM #DimInsurer s
	INNER JOIN #LoadOperation lo
		ON COALESCE(lo.InsurerCode, '^&*') = COALESCE(s.InsurerCode, '^&*') COLLATE DATABASE_DEFAULT
		AND COALESCE(lo.SourceSysKey, -1) = COALESCE(s.SourceSysKey, -1)
		AND lo.Operation IN ('I', 'U')
	CROSS JOIN #Parameters p
END
