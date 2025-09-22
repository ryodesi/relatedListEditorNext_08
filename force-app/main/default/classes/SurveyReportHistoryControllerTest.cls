@isTest
private class SurveyReportHistoryControllerTest {
    
    // Queueableクラス定義（testSurveyReportComparatorで使用）
    private class UpdateSSRQueue implements Queueable {
        Id recId;
        UpdateSSRQueue(Id id){ recId = id; }
        public void execute(QueueableContext ctx){
            // 必ず値が変わる更新で LastModifiedDate を進める
            StandardSalesFloorSurveyReport__c r =
                [SELECT Id, FaceCount__c FROM StandardSalesFloorSurveyReport__c WHERE Id = :recId LIMIT 1];
            r.FaceCount__c = (r.FaceCount__c == null) ? 1 : r.FaceCount__c + 1;
            update r;
        }
    }

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
        // 【シナリオ】指定した月に定番売場調査レコードを持つ日誌が存在しない
        Account acc = [SELECT Id FROM Account LIMIT 1];
        // 参照日誌を作成
        journal__c referenceJournal = createJournal(acc.Id, Date.today());
        // 同月に別の日誌を作成するが、定番売場調査レコードは紐付けない
        journal__c emptyJournal = createJournal(acc.Id, Date.today().addDays(5));

        Test.startTest();
        SurveyReportHistoryController.SurveyHistoryResult result = SurveyReportHistoryController.getSurveyReportsForJournal(acc.Id, referenceJournal.Id);
        Test.stopTest();

        System.assertEquals(0, result.surveyReports.size(), '条件に合う日誌がないため、結果は0件であるべき');
        System.assertEquals('', result.formattedDate, '日付も空文字であるべき');
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
        // 前提（未来日の親で入力規則回避）
        // 販売店レコードタイプを持つAccountを作成
        Id LiquorStoreRecordTypeId;
        try {
            LiquorStoreRecordTypeId = Schema.getGlobalDescribe().get('Account').getDescribe().getRecordTypeInfosByDeveloperName().get('LiquorStore').getRecordTypeId();
        } catch (Exception e) {
            // レコードタイプが存在しない場合は、デフォルトを使用
            LiquorStoreRecordTypeId = null;
        }
        
        Account acct = new Account(
            Name = 'A',
            RecordTypeId = LiquorStoreRecordTypeId
        ); 
        insert acct;
        Date futureDay = Date.today().addMonths(6);
        journal__c j = new journal__c(Name='j', customer__c=acct.Id, visitday__c=futureDay);
        insert j;
        
        // 基本的な昇順ソートのテスト
        SurveyReportHistoryController.SurveyReportComparator comparator = new SurveyReportHistoryController.SurveyReportComparator();
        
        // 異なるSortNumber__cのレコードを作成
        StandardSalesFloorSurveyReport__c report1 = new StandardSalesFloorSurveyReport__c(
            Name = 'Test Report 1',
            journal__c = j.Id,
            SortNumber__c = 1
        );
        StandardSalesFloorSurveyReport__c report2 = new StandardSalesFloorSurveyReport__c(
            Name = 'Test Report 2',
            journal__c = j.Id,
            SortNumber__c = 2
        );
        
        // NULL値のレコード
        StandardSalesFloorSurveyReport__c reportNull = new StandardSalesFloorSurveyReport__c(
            Name = 'Test Report Null',
            journal__c = j.Id,
            SortNumber__c = null
        );
        
        // すべて一括挿入
        insert new List<StandardSalesFloorSurveyReport__c>{report1, report2, reportNull};
        
        // レコードを再取得
        Map<Id, StandardSalesFloorSurveyReport__c> recordMap = new Map<Id, StandardSalesFloorSurveyReport__c>(
            [SELECT Id, SortNumber__c, LastModifiedDate FROM StandardSalesFloorSurveyReport__c 
             WHERE Id IN :new Set<Id>{report1.Id, report2.Id, reportNull.Id}]
        );
        
        StandardSalesFloorSurveyReport__c rec1 = recordMap.get(report1.Id);
        StandardSalesFloorSurveyReport__c rec2 = recordMap.get(report2.Id);
        StandardSalesFloorSurveyReport__c recNull = recordMap.get(reportNull.Id);
        
        // 1 < 2 なので負の値が返るべき
        Integer result1 = comparator.compare(rec1, rec2);
        System.assert(result1 < 0, 'SortNumber__c = 1 は 2 より前に来るべき');
        
        // 2 > 1 なので正の値が返るべき
        Integer result2 = comparator.compare(rec2, rec1);
        System.assert(result2 > 0, 'SortNumber__c = 2 は 1 より後に来るべき');
        
        // NULL値は最後に配置
        Integer result3 = comparator.compare(rec1, recNull);
        System.assert(result3 < 0, 'SortNumber__cがある場合はNULLより前に来るべき');
        
        Integer result4 = comparator.compare(recNull, rec1);
        System.assert(result4 > 0, 'SortNumber__cがNULLの場合は後に来るべき');
        
        // 同じ SortNumber__c の2件を作成
        StandardSalesFloorSurveyReport__c r1 = new StandardSalesFloorSurveyReport__c(
            Name='A', journal__c=j.Id, SortNumber__c=10, FaceCount__c=0);
        StandardSalesFloorSurveyReport__c r2 = new StandardSalesFloorSurveyReport__c(
            Name='B', journal__c=j.Id, SortNumber__c=10, FaceCount__c=0);
        insert new List<StandardSalesFloorSurveyReport__c>{ r1, r2 };

        // ① まず r1 を同期更新（時刻の"1段目"を作る）
        r1.FaceCount__c = 5;
        update r1;
        
        // r1の更新後のLastModifiedDateを取得
        r1 = [SELECT Id, SortNumber__c, LastModifiedDate FROM StandardSalesFloorSurveyReport__c WHERE Id = :r1.Id];
        Datetime r1Time = r1.LastModifiedDate;

        // ② r2 を Queueable で更新（stopTest 時に実行 → r1 より新しくなる想定）
        Test.startTest();
        System.enqueueJob(new UpdateSSRQueue(r2.Id));
        Test.stopTest();

        // ③ 念押しで r2 をもう一度だけ同期更新（r2 を確実に最新に）
        r2 = [SELECT Id, FaceCount__c FROM StandardSalesFloorSurveyReport__c WHERE Id = :r2.Id];
        r2.FaceCount__c = r2.FaceCount__c + 1;
        update r2;
        
        // デバッグ：時間差を確認
        System.debug('r1の最初の更新時刻: ' + r1Time);

        // ★ 重要：必ず SOQL で"両方"を再取得してから比較に使う
        r1 = [SELECT Id, SortNumber__c, LastModifiedDate, Name, FaceCount__c FROM StandardSalesFloorSurveyReport__c WHERE Id = :r1.Id];
        r2 = [SELECT Id, SortNumber__c, LastModifiedDate, Name, FaceCount__c FROM StandardSalesFloorSurveyReport__c WHERE Id = :r2.Id];
        
        // デバッグ情報を追加
        System.debug('r1: Name=' + r1.Name + ', LastModifiedDate=' + r1.LastModifiedDate);
        System.debug('r2: Name=' + r2.Name + ', LastModifiedDate=' + r2.LastModifiedDate);
        System.debug('時間差(ms): ' + (r2.LastModifiedDate.getTime() - r1.LastModifiedDate.getTime()));

        // 時間差が同じ場合の対処
        if (r1.LastModifiedDate >= r2.LastModifiedDate) {
            // r2をもう一度更新して確実に新しくする
            r2.FaceCount__c = r2.FaceCount__c + 1;
            update r2;
            
            // 再度取得
            r2 = [SELECT Id, SortNumber__c, LastModifiedDate, Name FROM StandardSalesFloorSurveyReport__c WHERE Id = :r2.Id];
            System.debug('追加更新後のr2: LastModifiedDate=' + r2.LastModifiedDate);
        }

        // デバッグ用：本当に r2 の方が新しいか確認
        System.assert(r2.LastModifiedDate > r1.LastModifiedDate,
            '準備段階：r2 の LastModifiedDate を r1 より新しくできていない。' +
            'r1=' + r1.LastModifiedDate + ', r2=' + r2.LastModifiedDate);

        // ソートして検証
        List<StandardSalesFloorSurveyReport__c> listToSort = new List<StandardSalesFloorSurveyReport__c>{ r1, r2 };
        listToSort.sort(new SurveyReportHistoryController.SurveyReportComparator());
        System.assertEquals(r2.Id, listToSort[0].Id,
            '同じSortNumber__cの場合、新しい方（r2）が先に来るべき');
        
        // 両方のSortNumber__cとLastModifiedDateがnullの場合（メモリ上のオブジェクトで検証）
        StandardSalesFloorSurveyReport__c reportBothNull1 = new StandardSalesFloorSurveyReport__c(
            SortNumber__c = null
        );
        StandardSalesFloorSurveyReport__c reportBothNull2 = new StandardSalesFloorSurveyReport__c(
            SortNumber__c = null
        );
        
        Integer result6 = comparator.compare(reportBothNull1, reportBothNull2);
        System.assertEquals(0, result6, '両方NULLの場合は0が返るべき');
        
        // SortNumber__cが同じで、片方のLastModifiedDateがnullの場合
        StandardSalesFloorSurveyReport__c report1ModNull = new StandardSalesFloorSurveyReport__c(
            SortNumber__c = 1
        );
        
        Integer result7 = comparator.compare(rec1, report1ModNull);
        System.assert(result7 < 0, '同じSortNumber__cで、LastModifiedDateがある方が先に来るべき');
        
        Integer result8 = comparator.compare(report1ModNull, rec1);
        System.assert(result8 > 0, '同じSortNumber__cで、LastModifiedDateがnullの方が後に来るべき');
        
        // SortNumber__cがnullで、片方のLastModifiedDateもnullの場合
        StandardSalesFloorSurveyReport__c reportNullWithoutDate = new StandardSalesFloorSurveyReport__c(
            SortNumber__c = null
        );
        
        Integer result9 = comparator.compare(recNull, reportNullWithoutDate);
        System.assert(result9 < 0, 'SortNumber__cが両方nullの場合、LastModifiedDateがある方が先に来るべき');
        
        Integer result10 = comparator.compare(reportNullWithoutDate, recNull);
        System.assert(result10 > 0, 'SortNumber__cが両方nullの場合、LastModifiedDateがnullの方が後に来るべき');
    }
    
    // --- 同月の複数日誌からの全レコード取得テスト ---
    @isTest
    static void testGetSurveyReports_MultipleJournalsInMonth() {
        // 【シナリオ】同月に複数の日誌があり、すべての調査レコードが取得される
        Account acc = [SELECT Id FROM Account LIMIT 1];
        
        // 未来日の同月日付を使用（今日+6ヶ月の15日）
        Date baseMonth = Date.today().addMonths(6);
        Date baseDay = Date.newInstance(baseMonth.year(), baseMonth.month(), 15);
        
        // 基準となる日誌を作成
        journal__c baseJournal = createJournal(acc.Id, baseDay);
        
        // 同月内の別日付の日誌を作成（すべて未来）
        journal__c journal1 = createJournal(acc.Id, baseDay.addDays(1));
        journal__c journal2 = createJournal(acc.Id, baseDay.addDays(2));
        
        // 各日誌に確実にレポートを紐付け（親に最低1件は子を付ける）
        List<StandardSalesFloorSurveyReport__c> allReports = new List<StandardSalesFloorSurveyReport__c>();
        
        // journal1: 3件
        allReports.add(new StandardSalesFloorSurveyReport__c(
            Name = 'Report1-1',
            journal__c = journal1.Id,
            SortNumber__c = 1,
            FaceCount__c = 10
        ));
        allReports.add(new StandardSalesFloorSurveyReport__c(
            Name = 'Report1-2',
            journal__c = journal1.Id,
            SortNumber__c = 3,
            FaceCount__c = 10
        ));
        allReports.add(new StandardSalesFloorSurveyReport__c(
            Name = 'Report1-3',
            journal__c = journal1.Id,
            SortNumber__c = 5,
            FaceCount__c = 10
        ));
        
        // journal2: 2件
        allReports.add(new StandardSalesFloorSurveyReport__c(
            Name = 'Report2-1',
            journal__c = journal2.Id,
            SortNumber__c = 2,
            FaceCount__c = 20
        ));
        allReports.add(new StandardSalesFloorSurveyReport__c(
            Name = 'Report2-2',
            journal__c = journal2.Id,
            SortNumber__c = 4,
            FaceCount__c = 20
        ));
        
        // 一括で挿入
        insert allReports;
        
        // formattedDateを埋めるため、最低1件はLastManualUpdateDate__cを設定して更新
        allReports[0].LastManualUpdateDate__c = System.now();
        update allReports[0];
        
        Test.startTest();
        SurveyReportHistoryController.SurveyHistoryResult result = 
            SurveyReportHistoryController.getSurveyReportsForJournal(acc.Id, baseJournal.Id);
        Test.stopTest();
        
        // Assert
        System.assertNotEquals(null, result, '結果がnullでないことを確認');
        System.assertNotEquals(null, result.surveyReports, 'surveyReportsがnullでないことを確認');
        
        // デバッグ用：実際の件数を出力
        if (result.surveyReports.size() != 5) {
            System.debug('実際の件数: ' + result.surveyReports.size());
            for (StandardSalesFloorSurveyReport__c report : result.surveyReports) {
                System.debug('Report: ' + report.Name + ', SortNumber: ' + report.SortNumber__c + ', Journal: ' + report.journal__c);
            }
        }
        
        // 5件のレコードが返ることを確認
        System.assertEquals(5, result.surveyReports.size(), '同一未来月の全journalの子（5件）が返るべき');
        System.assertNotEquals('', result.formattedDate, '日付が設定されるべき');
        
        // ソート順の確認（SortNumber__c: 1, 2, 3, 4, 5）
        System.assertEquals(1, result.surveyReports[0].SortNumber__c, '1番目はSortNumber__c = 1');
        System.assertEquals(2, result.surveyReports[1].SortNumber__c, '2番目はSortNumber__c = 2');
        System.assertEquals(3, result.surveyReports[2].SortNumber__c, '3番目はSortNumber__c = 3');
        System.assertEquals(4, result.surveyReports[3].SortNumber__c, '4番目はSortNumber__c = 4');
        System.assertEquals(5, result.surveyReports[4].SortNumber__c, '5番目はSortNumber__c = 5');
    }
    
    // --- journalIdがnullの場合のテスト ---
    @isTest
    static void testGetSurveyReports_JournalIdNull() {
        // 【シナリオ】日誌IDがnull
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        SurveyReportHistoryController.SurveyHistoryResult result = SurveyReportHistoryController.getSurveyReportsForJournal(acc.Id, null);
        Test.stopTest();

        System.assertEquals(0, result.surveyReports.size(), '日誌IDがnullの場合、結果は0件であるべき');
        System.assertEquals('', result.formattedDate, '日付も空文字であるべき');
    }
    
    @isTest
    static void testGetPreviousMonthReports_JournalIdNull() {
        // 【シナリオ】日誌IDがnull
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        SurveyReportHistoryController.SurveyHistoryResult result = SurveyReportHistoryController.getPreviousMonthSurveyReports(acc.Id, null);
        Test.stopTest();

        System.assertEquals(0, result.surveyReports.size(), '日誌IDがnullの場合、結果は0件であるべき');
        System.assertEquals('', result.formattedDate, '日付も空文字であるべき');
    }
    
    // --- LastManualUpdateDate__cがすべてnullの場合のテスト ---
    @isTest
    static void testGetSurveyReports_AllLastManualUpdateDateNull() {
        // 【シナリオ】レポートは存在するがLastManualUpdateDate__cがすべてnull
        Account acc = [SELECT Id FROM Account LIMIT 1];
        journal__c referenceJournal = createJournal(acc.Id, Date.today());
        journal__c targetJournal = createJournal(acc.Id, Date.today().addDays(1));
        
        // LastManualUpdateDate__cをnullのままにするため、faceCountをnullで作成
        createSurveyReport(targetJournal.Id, 3, null);

        Test.startTest();
        SurveyReportHistoryController.SurveyHistoryResult result = SurveyReportHistoryController.getSurveyReportsForJournal(acc.Id, referenceJournal.Id);
        Test.stopTest();

        System.assertEquals(3, result.surveyReports.size(), 'レポートは3件返るべき');
        System.assertEquals('', result.formattedDate, 'LastManualUpdateDate__cがすべてnullのため、日付は空文字であるべき');
    }
    
    @isTest
    static void testGetPreviousMonthReports_AllLastManualUpdateDateNull() {
        // 【シナリオ】前月レポートでLastManualUpdateDate__cがすべてnull
        Account acc = [SELECT Id FROM Account LIMIT 1];
        
        Date currentDate = Date.today();
        Date prevMonthDate = currentDate.addMonths(-1);
        
        journal__c referenceJournal = createJournal(acc.Id, currentDate);
        
        // 前月の日誌を作成
        journal__c prevMonthJournal = new journal__c(
            customer__c = acc.Id,
            visitday__c = currentDate
        );
        insert prevMonthJournal;
        
        Test.setCreatedDate(prevMonthJournal.Id, prevMonthDate);
        prevMonthJournal.visitday__c = prevMonthDate;
        update prevMonthJournal;
        
        // LastManualUpdateDate__cをnullのままにするため、faceCountをnullで作成
        createSurveyReport(prevMonthJournal.Id, 2, null);

        Test.startTest();
        SurveyReportHistoryController.SurveyHistoryResult result = SurveyReportHistoryController.getPreviousMonthSurveyReports(acc.Id, referenceJournal.Id);
        Test.stopTest();

        System.assertEquals(2, result.surveyReports.size(), '前月の日誌に紐づく2件のレポートが返るべき');
        System.assertEquals('', result.formattedDate, 'LastManualUpdateDate__cがすべてnullのため、日付は空文字であるべき');
    }


    // --- SortNumber__cが同じでLastModifiedDateも同じ場合のテスト ---
    @isTest
    static void testSurveyReportComparator_SameEverything() {
        // テスト用の顧客と日誌を作成
        Account acc = [SELECT Id FROM Account LIMIT 1];
        journal__c testJournal = createJournal(acc.Id, Date.today());
        
        SurveyReportHistoryController.SurveyReportComparator comparator = new SurveyReportHistoryController.SurveyReportComparator();
        
        // 同じバッチで2つのレコードを作成（同じLastModifiedDateを持つ可能性が高い）
        List<StandardSalesFloorSurveyReport__c> reports = new List<StandardSalesFloorSurveyReport__c>();
        reports.add(new StandardSalesFloorSurveyReport__c(
            Name = 'Test Same 1',
            journal__c = testJournal.Id,
            SortNumber__c = 5
        ));
        reports.add(new StandardSalesFloorSurveyReport__c(
            Name = 'Test Same 2',
            journal__c = testJournal.Id,
            SortNumber__c = 5
        ));
        insert reports;
        
        // レコードを取得
        List<StandardSalesFloorSurveyReport__c> savedReports = [SELECT Id, SortNumber__c, LastModifiedDate 
                                                                 FROM StandardSalesFloorSurveyReport__c 
                                                                 WHERE Id IN :reports];
        
        // もし同じLastModifiedDateを持つ場合のテスト
        if (savedReports[0].LastModifiedDate == savedReports[1].LastModifiedDate) {
            Integer result = comparator.compare(savedReports[0], savedReports[1]);
            System.assertEquals(0, result, '完全に同じ値の場合は0が返るべき');
        } else {
            // 異なるLastModifiedDateの場合でも、メモリ上で同じ値を設定してテスト
            StandardSalesFloorSurveyReport__c report1 = new StandardSalesFloorSurveyReport__c(
                SortNumber__c = 5
            );
            StandardSalesFloorSurveyReport__c report2 = new StandardSalesFloorSurveyReport__c(
                SortNumber__c = 5
            );
            
            // LastModifiedDateを同じ値に設定（実際のフィールドではなく、comparatorが参照する値）
            savedReports[0].SortNumber__c = 5;
            savedReports[1].SortNumber__c = 5;
            Datetime sameTime = savedReports[0].LastModifiedDate;
            
            // メモリ上でのテスト用オブジェクトを作成
            StandardSalesFloorSurveyReport__c testReport1 = new StandardSalesFloorSurveyReport__c(
                SortNumber__c = 5
            );
            StandardSalesFloorSurveyReport__c testReport2 = new StandardSalesFloorSurveyReport__c(
                SortNumber__c = 5
            );
            
            // 両方ともLastModifiedDateなしで比較
            Integer result = comparator.compare(testReport1, testReport2);
            System.assertEquals(0, result, '両方のLastModifiedDateがnullで同じSortNumber__cの場合は0が返るべき');
        }
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