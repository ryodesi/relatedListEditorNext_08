@isTest
private class SurveyReportHistoryControllerTest {

    // 各テストメソッドで共通して使用する顧客レコードを作成
    @TestSetup
    static void makeData() {
        // テスト用顧客作成
        // レコードタイプの取得（開発者名を使用）
        Id LiquorStoreRecordTypeId;
        try {
            LiquorStoreRecordTypeId = Schema.getGlobalDescribe().get('Account').getDescribe().getRecordTypeInfosByDeveloperName().get('LiquorStore').getRecordTypeId();
        } catch (Exception e) {
            // レコードタイプが存在しない場合は、デフォルトを使用
            LiquorStoreRecordTypeId = null;
        }
        
        Account acc = new Account(
            Name = 'テスト顧客',
            Chian_CD__C = 'CUST001',  // 顧客コード
            RecordTypeId = LiquorStoreRecordTypeId
        );
        insert acc;
    }

    // --- getSurveyReportsForJournal メソッドのテスト ---
    @isTest
    static void testGetSurveyReports_Success_WithFaceCount() {
        // 【シナリオ】正常系：指定した月の最新日誌に紐づくレポートが取得でき、日付も返る
        // Arrange
        Account acc = [SELECT Id FROM Account LIMIT 1];
        journal__c referenceJournal = createJournal(acc.Id, Date.today());
        // 同じ月の、より新しい日誌を作成し、レポートを2件紐付ける (1件はFaceCountあり)
        journal__c targetJournal = createJournal(acc.Id, Date.today().addDays(1));
        createSurveyReport(targetJournal.Id, 1, 10); // FaceCountあり
        createSurveyReport(targetJournal.Id, 1, null); // FaceCountなし

        Test.startTest();
        // Act
        SurveyReportHistoryController.SurveyHistoryResult result = SurveyReportHistoryController.getSurveyReportsForJournal(acc.Id, referenceJournal.Id);
        Test.stopTest();

        // Assert
        System.assertEquals(2, result.surveyReports.size(), '最も新しい日誌に紐づく2件のレポートが返るべき');
        System.assert(String.isNotBlank(result.formattedDate), 'FaceCountがあるため、フォーマットされた日付が返るべき');
    }

    @isTest
    static void testGetSurveyReports_Success_NoFaceCount() {
        // 【シナリオ】正常系：レポートは取得できるが、すべてFaceCountがnullのため日付は返らない
        // Arrange
        Account acc = [SELECT Id FROM Account LIMIT 1];
        journal__c referenceJournal = createJournal(acc.Id, Date.today());
        journal__c targetJournal = createJournal(acc.Id, Date.today().addDays(1));
        createSurveyReport(targetJournal.Id, 2, null); // 2件ともFaceCountなし

        Test.startTest();
        // Act
        SurveyReportHistoryController.SurveyHistoryResult result = SurveyReportHistoryController.getSurveyReportsForJournal(acc.Id, referenceJournal.Id);
        Test.stopTest();

        // Assert
        System.assertEquals(2, result.surveyReports.size(), 'レポートは2件返るべき');
        System.assertEquals('', result.formattedDate, 'FaceCountがないため、日付は空文字であるべき');
    }

    @isTest
    static void testGetSurveyReports_NoMatchingData() {
        // 【シナリオ】指定した月に日誌が存在しない
        Account acc = [SELECT Id FROM Account LIMIT 1];
        journal__c referenceJournal = createJournal(acc.Id, Date.today());

        Test.startTest();
        SurveyReportHistoryController.SurveyHistoryResult result = SurveyReportHistoryController.getSurveyReportsForJournal(acc.Id, referenceJournal.Id);
        Test.stopTest();

        System.assertEquals(0, result.surveyReports.size(), '条件に合う日誌がないため、結果は0件であるべき');
    }

    @isTest
    static void testGetSurveyReports_AccIdNullData() {
        // 【シナリオ】顧客IDがnull
        Account acc = [SELECT Id FROM Account LIMIT 1];
        journal__c referenceJournal = createJournal(acc.Id, Date.today());

        Test.startTest();
        SurveyReportHistoryController.SurveyHistoryResult result = SurveyReportHistoryController.getSurveyReportsForJournal(null, referenceJournal.Id);
        Test.stopTest();

        System.assertEquals(0, result.surveyReports.size(), '条件に合う日誌がないため、結果は0件であるべき');
    }

    @isTest
    static void testGetSurveyReports_visitdayNullData() {
        // 【シナリオ】訪問日がnull
        Account acc = [SELECT Id FROM Account LIMIT 1];
        journal__c referenceJournal = createJournal(acc.Id, null);

        Test.startTest();
        SurveyReportHistoryController.SurveyHistoryResult result = SurveyReportHistoryController.getSurveyReportsForJournal(acc.Id, referenceJournal.Id);
        Test.stopTest();

        System.assertEquals(0, result.surveyReports.size(), '条件に合う日誌がないため、結果は0件であるべき');
    }

    // --- getPreviousMonthSurveyReports メソッドのテスト ---
    @isTest
    static void testGetPreviousMonthReports_Success() {
        // 【シナリオ】前月の最新日誌に紐づくレポートが取得できる
        // Arrange
        Account acc = [SELECT Id FROM Account LIMIT 1];
        
        // テスト用に現在の日付を基準とする
        Date currentDate = Date.today();
        Date prevMonthDate = currentDate.addMonths(-1);
        
        // まず現在の日誌を作成
        journal__c referenceJournal = createJournal(acc.Id, currentDate);
        
        // 前月の日誌を作成（訪問日は現在日にして、後でテスト用に更新）
        journal__c prevMonthJournal = new journal__c(
            customer__c = acc.Id,
            visitday__c = currentDate  // 一旦現在日で作成
        );
        insert prevMonthJournal;
        
        // テストコンテキストで過去日付に更新
        Test.setCreatedDate(prevMonthJournal.Id, prevMonthDate);
        prevMonthJournal.visitday__c = prevMonthDate;
        update prevMonthJournal;
        
        createSurveyReport(prevMonthJournal.Id, 3, 5);

        Test.startTest();
        SurveyReportHistoryController.SurveyHistoryResult result = SurveyReportHistoryController.getPreviousMonthSurveyReports(acc.Id, referenceJournal.Id);
        Test.stopTest();

        // Assert
        System.assertEquals(3, result.surveyReports.size(), '前月の日誌に紐づく3件のレポートが返るべき');
        System.assert(String.isNotBlank(result.formattedDate), 'フォーマットされた日付が返るべき');
    }

    @isTest
    static void testGetPreviousMonthReports_Success2() {
        // 【シナリオ】前々月の最新日誌に紐づくレポートが取得できる
        Account acc = [SELECT Id FROM Account LIMIT 1];
        
        // テスト用に現在の日付を基準とする
        Date currentDate = Date.today();
        Date prevPrevMonthDate = currentDate.addMonths(-2);
        
        // まず現在の日誌を作成
        journal__c referenceJournal = createJournal(acc.Id, currentDate);
        
        // 前々月の日誌を作成（訪問日は現在日にして、後でテスト用に更新）
        journal__c prevMonthJournal = new journal__c(
            customer__c = acc.Id,
            visitday__c = currentDate  // 一旦現在日で作成
        );
        insert prevMonthJournal;
        
        // テストコンテキストで過去日付に更新
        Test.setCreatedDate(prevMonthJournal.Id, prevPrevMonthDate);
        prevMonthJournal.visitday__c = prevPrevMonthDate;
        update prevMonthJournal;
        
        createSurveyReport(prevMonthJournal.Id, 3, 5);

        Test.startTest();
        SurveyReportHistoryController.SurveyHistoryResult result = SurveyReportHistoryController.getPreviousMonthSurveyReports(acc.Id, referenceJournal.Id);
        Test.stopTest();

        // Assert
        System.assertEquals(3, result.surveyReports.size(), '前々月の日誌に紐づく3件のレポートが返るべき');
        System.assert(String.isNotBlank(result.formattedDate), 'フォーマットされた日付が返るべき');
    }

    @isTest
    static void testGetPreviousMonthReports_NoMatchingData() {
        // 【シナリオ】前月に日誌が存在しない
        Account acc = [SELECT Id FROM Account LIMIT 1];
        journal__c referenceJournal = createJournal(acc.Id, Date.today());

        Test.startTest();
        SurveyReportHistoryController.SurveyHistoryResult result = SurveyReportHistoryController.getPreviousMonthSurveyReports(acc.Id, referenceJournal.Id);
        Test.stopTest();

        System.assertEquals(0, result.surveyReports.size(), '前月に日誌がないため、結果は0件であるべき');
    }

    @isTest
    static void testGetPreviousMonthReports_AccIdNullData() {
        // 【シナリオ】顧客IDがnull
        Account acc = [SELECT Id FROM Account LIMIT 1];
        journal__c referenceJournal = createJournal(acc.Id, Date.today());

        Test.startTest();
        SurveyReportHistoryController.SurveyHistoryResult result = SurveyReportHistoryController.getPreviousMonthSurveyReports(null, referenceJournal.Id);
        Test.stopTest();

        System.assertEquals(0, result.surveyReports.size(), '前月に日誌がないため、結果は0件であるべき');
    }

    @isTest
    static void testGetPreviousMonthReports_visitdayNullData() {
        // 【シナリオ】訪問日がnull
        Account acc = [SELECT Id FROM Account LIMIT 1];
        journal__c referenceJournal = createJournal(acc.Id, null);

        Test.startTest();
        SurveyReportHistoryController.SurveyHistoryResult result = SurveyReportHistoryController.getPreviousMonthSurveyReports(acc.Id, referenceJournal.Id);
        Test.stopTest();

        System.assertEquals(0, result.surveyReports.size(), '条件に合う日誌がないため、結果は0件であるべき');
    }

    // --- toDateTimeString メソッドのテスト ---
    @isTest
    static void testToDateTimeString() {
        // 正常系
        Datetime dt = Datetime.newInstance(2025, 7, 14, 10, 30, 0);
        String result = SurveyReportHistoryController.toDateTimeString(dt);
        System.assertEquals('2025年07月14日', result, '期待した書式で文字列が返るべき');

        // nullを渡した場合
        String nullResult = SurveyReportHistoryController.toDateTimeString(null);
        System.assertEquals('', nullResult, 'nullを渡した場合は空文字が返るべき');
    }
    
    // --- SurveyReportComparator クラスのテスト ---
    @isTest
    static void testSurveyReportComparator() {
        // 基本的な昇順ソートのテスト
        SurveyReportHistoryController.SurveyReportComparator comparator = new SurveyReportHistoryController.SurveyReportComparator();
        
        StandardSalesFloorSurveyReport__c report1 = new StandardSalesFloorSurveyReport__c(
            SortNumber__c = 1,
            LastModifiedDate = Datetime.now()
        );
        StandardSalesFloorSurveyReport__c report2 = new StandardSalesFloorSurveyReport__c(
            SortNumber__c = 2,
            LastModifiedDate = Datetime.now()
        );
        
        // 1 < 2 なので負の値が返るべき
        Integer result1 = comparator.compare(report1, report2);
        System.assert(result1 < 0, 'SortNumber__c = 1 は 2 より前に来るべき');
        
        // 2 > 1 なので正の値が返るべき
        Integer result2 = comparator.compare(report2, report1);
        System.assert(result2 > 0, 'SortNumber__c = 2 は 1 より後に来るべき');
        
        // NULL値は最後に配置
        StandardSalesFloorSurveyReport__c reportNull = new StandardSalesFloorSurveyReport__c(
            SortNumber__c = null,
            LastModifiedDate = Datetime.now()
        );
        
        Integer result3 = comparator.compare(report1, reportNull);
        System.assert(result3 < 0, 'SortNumber__cがある場合はNULLより前に来るべき');
        
        Integer result4 = comparator.compare(reportNull, report1);
        System.assert(result4 > 0, 'SortNumber__cがNULLの場合は後に来るべき');
        
        // 同じSortNumber__cの場合はLastModifiedDateで降順
        StandardSalesFloorSurveyReport__c report1Old = new StandardSalesFloorSurveyReport__c(
            SortNumber__c = 1,
            LastModifiedDate = Datetime.now().addDays(-1)
        );
        
        Integer result5 = comparator.compare(report1, report1Old);
        System.assert(result5 < 0, '同じSortNumber__cの場合、新しい方が先に来るべき');
    }
    
    // --- 複数月にまたがるデータのテスト ---
    @isTest
    static void testGetSurveyReports_MultipleJournalsInMonth() {
        // 【シナリオ】同月に複数の日誌があり、すべての調査レコードが取得される
        Account acc = [SELECT Id FROM Account LIMIT 1];
        
        // 同月の複数日誌を作成
        journal__c journal1 = createJournal(acc.Id, Date.today());
        journal__c journal2 = createJournal(acc.Id, Date.today().addDays(7));
        journal__c journal3 = createJournal(acc.Id, Date.today().addDays(14));
        
        // 各日誌にレポートを紐付け（SortNumber__c付き）
        createSurveyReportWithSort(journal1.Id, 2, 5, new List<Decimal>{3, 1});
        createSurveyReportWithSort(journal2.Id, 2, 10, new List<Decimal>{2, null});
        createSurveyReportWithSort(journal3.Id, 1, 15, new List<Decimal>{4});
        
        Test.startTest();
        SurveyReportHistoryController.SurveyHistoryResult result = 
            SurveyReportHistoryController.getSurveyReportsForJournal(acc.Id, journal1.Id);
        Test.stopTest();
        
        // Assert
        System.assertEquals(5, result.surveyReports.size(), '全日誌から5件のレポートが返るべき');
        System.assert(String.isNotBlank(result.formattedDate), '日付が設定されるべき');
        
        // ソート順の確認（SortNumber__c: 1, 2, 3, 4, null）
        System.assertEquals(1, result.surveyReports[0].SortNumber__c, '1番目はSortNumber__c = 1');
        System.assertEquals(2, result.surveyReports[1].SortNumber__c, '2番目はSortNumber__c = 2');
        System.assertEquals(3, result.surveyReports[2].SortNumber__c, '3番目はSortNumber__c = 3');
        System.assertEquals(4, result.surveyReports[3].SortNumber__c, '4番目はSortNumber__c = 4');
        System.assertEquals(null, result.surveyReports[4].SortNumber__c, '5番目はSortNumber__c = null');
    }


    // --- テストデータ作成用のヘルパーメソッド ---
    private static journal__c createJournal(Id accountId, Date visitDay) {
        journal__c j = new journal__c(
            customer__c = accountId,
            visitday__c = visitDay
        );
        insert j;
        return j;
    }

    private static List<StandardSalesFloorSurveyReport__c> createSurveyReport(Id journalId, Integer count, Decimal faceCount) {
        List<StandardSalesFloorSurveyReport__c> reports = new List<StandardSalesFloorSurveyReport__c>();
        for (Integer i = 0; i < count; i++) {
            StandardSalesFloorSurveyReport__c report = new StandardSalesFloorSurveyReport__c(
                Name = 'テスト調査レポート ' + i,
                journal__c = journalId,
                FaceCount__c = faceCount
            );
            reports.add(report);
        }
        insert reports;
        
        // FaceCountがある場合、LastManualUpdateDate__cを設定
        if (faceCount != null) {
            for (StandardSalesFloorSurveyReport__c report : reports) {
                report.LastManualUpdateDate__c = Datetime.now();
            }
            update reports;
        }
        
        return reports;
    }
    
    // SortNumber__c付きでレポートを作成するヘルパーメソッド
    private static List<StandardSalesFloorSurveyReport__c> createSurveyReportWithSort(Id journalId, Integer count, Decimal faceCount, List<Decimal> sortNumbers) {
        List<StandardSalesFloorSurveyReport__c> reports = new List<StandardSalesFloorSurveyReport__c>();
        for (Integer i = 0; i < count; i++) {
            StandardSalesFloorSurveyReport__c report = new StandardSalesFloorSurveyReport__c(
                Name = 'テスト調査レポート ' + i,
                journal__c = journalId,
                FaceCount__c = faceCount,
                SortNumber__c = (sortNumbers != null && i < sortNumbers.size()) ? sortNumbers[i] : null
            );
            reports.add(report);
        }
        insert reports;
        
        // FaceCountがある場合、LastManualUpdateDate__cを設定
        if (faceCount != null) {
            for (StandardSalesFloorSurveyReport__c report : reports) {
                report.LastManualUpdateDate__c = Datetime.now();
            }
            update reports;
        }
        
        return reports;
    }
}