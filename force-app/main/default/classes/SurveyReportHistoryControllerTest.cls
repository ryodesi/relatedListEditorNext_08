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
        journal__c referenceJournal = createJournal(acc.Id, Date.today());
        // 前々月の日誌を作成し、レポートを3件紐付ける
        journal__c prevMonthJournal = createJournal(acc.Id, Date.today().addMonths(-1));
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
        journal__c referenceJournal = createJournal(acc.Id, Date.today());
        // 前々月の日誌を作成し、レポートを3件紐付ける
        journal__c prevMonthJournal = createJournal(acc.Id, Date.today().addMonths(-2));
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
            reports.add(new StandardSalesFloorSurveyReport__c(
                Name = 'テスト調査レポート ' + i,
                journal__c = journalId,
                FaceCount__c = faceCount
            ));
        }
        insert reports;
        return reports;
    }
}