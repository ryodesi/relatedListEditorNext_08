/**
 * 処理概要：定番売場調査直近履歴取得・日誌紐付け更新
 * 処理名　：SurveyReportHistoryController
 * 作成者　：taniguchi
 * 作成日　：2025/07/10
 */
public with sharing class SurveyReportHistoryController {

    /**
     * @description LWCに返すための結果を格納するラッパークラス
     */
    public class SurveyHistoryResult {
        // LWCからアクセスできるよう @AuraEnabled を付与
        @AuraEnabled
        public List<StandardSalesFloorSurveyReport__c> surveyReports { get; set; }
        
        @AuraEnabled
        public String formattedDate { get; set; }

        // コンストラクタ: 初期化処理
        public SurveyHistoryResult() {
            this.surveyReports = new List<StandardSalesFloorSurveyReport__c>();
            this.formattedDate = '';
        }
    }

    /**
     * @description [取得用] 指定された顧客と日誌の月に基づいて、定番売場調査レコードを取得する
     * @param accountId 対象の顧客ID
     * @param journalId 基準となる月を特定するための日誌ID
     * @return 該当する定番売場調査レコードのリストと、最新の更新日を含むラッパーオブジェクト
     */
    @AuraEnabled(cacheable=true)
    public static SurveyHistoryResult getSurveyReportsForJournal(Id accountId, Id journalId) {
        // 戻り値用のラッパーオブジェクトをインスタンス化
        SurveyHistoryResult result = new SurveyHistoryResult();
        if (accountId == null || journalId == null) {
            return result;
        }

        // 1. 基準となる日誌から「訪問日」を取得する
        List<journal__c> referenceJournals = [SELECT visitday__c FROM journal__c WHERE Id = :journalId LIMIT 1];
        // 基準日誌が見つからない、または訪問日がない場合は空のリストを返す
        if (referenceJournals.isEmpty() || referenceJournals[0].visitday__c == null) {
            return result;
        }
        Date referenceDate = referenceJournals[0].visitday__c;

        // 2. 基準となる年と月を取得
        Integer targetYear = referenceDate.year();
        Integer targetMonth = referenceDate.month();

        // 3. 顧客IDと年月で定番売場調査レコードを検索
        //    LastModifiedDateも取得し、新しい順に並び替える
        List<journal__c> journalsInMonth = [
            SELECT Id, LastModifiedDate,
                   (SELECT Id, Name, Product__c, SKU__c, attribute__c, SalesFloorSelection__c, FaceCount__c, LastModifiedDate FROM journals__r ORDER BY LastModifiedDate DESC)
            FROM journal__c
            WHERE customer__c = :accountId
              AND CALENDAR_YEAR(visitday__c) = :targetYear
              AND CALENDAR_MONTH(visitday__c) = :targetMonth
              AND Id IN (SELECT journal__c FROM StandardSalesFloorSurveyReport__c)
            ORDER BY visitday__c DESC
            LIMIT 1
        ];

        // 3. 結果をラッパーオブジェクトに設定
        if (!journalsInMonth.isEmpty()) {
            List<StandardSalesFloorSurveyReport__c> foundReports = journalsInMonth[0].journals__r;
            result.surveyReports = foundReports;

            // FaceCount__cに値を持つレコードが1件でも存在するかチェック
            Boolean hasAnyFaceCount = false;
            for (StandardSalesFloorSurveyReport__c report : foundReports) {
                // FaceCount__cがnullでも空文字でもないことを確認
                if (report.FaceCount__c != null) {
                    hasAnyFaceCount = true;
                    break; // 1件でも見つかればループを抜ける
                }
            }

            // 1件でもFaceCount__cの入力があれば、最新の更新日をセット
            if (hasAnyFaceCount) {
                result.formattedDate = toDateTimeString(foundReports[0].LastModifiedDate);
            }
        }

        return result;
    }

    /**
     * @description [取得用] 指定された顧客と日誌の「前月」以前の定番売場調査レコードを取得する
     * @param accountId 対象の顧客ID
     * @param journalId 基準となる月を特定するための日誌ID
     * @return 該当する定番売場調査レコードのリストと、最新の更新日を含むラッパーオブジェクト
     */
    @AuraEnabled(cacheable=true)
    public static SurveyHistoryResult getPreviousMonthSurveyReports(Id accountId, Id journalId) {
        // 戻り値用のラッパーオブジェクトをインスタンス化
        SurveyHistoryResult result = new SurveyHistoryResult();
        if (accountId == null || journalId == null) {
            return result;
        }

        // 1. 基準となる日誌から「訪問日」を取得
        List<journal__c> referenceJournals = [SELECT visitday__c FROM journal__c WHERE Id = :journalId LIMIT 1];
        
        if (referenceJournals.isEmpty() || referenceJournals[0].visitday__c == null) {
            return result;
        }
        Date referenceDate = referenceJournals[0].visitday__c;

        // 基準日の「当月の1日」を取得 (例: 2025-02-15 -> 2025-02-01)
        Date startOfCurrentMonth = referenceDate.toStartOfMonth();

        List<journal__c> journalsInMonth = [
            SELECT Id, LastModifiedDate,
                   (SELECT Id, Name, Product__c, SKU__c, attribute__c, SalesFloorSelection__c, FaceCount__c, LastModifiedDate FROM journals__r ORDER BY LastModifiedDate DESC)
            FROM journal__c
            WHERE customer__c = :accountId
              AND visitday__c < :startOfCurrentMonth
              AND Id IN (SELECT journal__c FROM StandardSalesFloorSurveyReport__c)
            ORDER BY visitday__c DESC
            LIMIT 1
        ];

        // 3. 結果をラッパーオブジェクトに設定
        if (!journalsInMonth.isEmpty()) {
            List<StandardSalesFloorSurveyReport__c> foundReports = journalsInMonth[0].journals__r;
            result.surveyReports = foundReports;
            if(!foundReports.isEmpty()){
                result.formattedDate = toDateTimeString(foundReports[0].LastModifiedDate);
            }
        }

        return result;
    }

    /**
     * @description Datetime値をyyyy年MM月dd日の文字列に変換する
     * @param dt 変換したいDatetime値
     * @return 'yyyy年MM月dd日' 形式の文字列
     */
    @AuraEnabled
    public static String toDateTimeString(Datetime dt) {
        if (dt == null) {
            return '';
        }
        return dt.format('yyyy年MM月dd日', 'Asia/Tokyo');
    }
}