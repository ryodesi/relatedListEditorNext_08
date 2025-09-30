import { LightningElement, wire, api, track } from 'lwc';
import { getRelatedListRecords } from 'lightning/uiRelatedListApi';
import { getRecord, updateRecord, notifyRecordUpdateAvailable, getFieldValue } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import Chilled_Case_Check from '@salesforce/schema/Account.Chilled_Case_Check__c';
import Room_temperature_standard from '@salesforce/schema/Account.Room_temperature_standard__c';
import TAPESTRY_FIELD from '@salesforce/schema/Account.tapestry__c';
import AROUND_COLD_CASE_FIELD from '@salesforce/schema/Account.Around_the_cold_case__c';
import BOARD_FIELD from '@salesforce/schema/Account.board__c';
import PRIZE_STICKER_FIELD from '@salesforce/schema/Account.PrizeSticker__c';
import POSTER_FIELD from '@salesforce/schema/Account.poster__c';
import TV_EPOP_FIELD from '@salesforce/schema/Account.TV_E_POP__c';
import POP_FIELD from '@salesforce/schema/Account.POP_precautions__c';
import JOURNAL_CUSTOMER_FIELD from '@salesforce/schema/journal__c.customer__c'; // ← これが重要
import JOURNAL_REPORTDONE_FIELD from '@salesforce/schema/journal__c.reportdone__c';
// modal を表示するクラス（親）
import ExampleModal from 'c/exampleModal';
// Apexメソッドをインポート
import getSurveyReportsForJournal from '@salesforce/apex/SurveyReportHistoryController.getSurveyReportsForJournal';
import getPreviousMonthSurveyReports from '@salesforce/apex/SurveyReportHistoryController.getPreviousMonthSurveyReports';
import { refreshApex } from '@salesforce/apex';


const ACCOUNT_FIELDS = [
    Chilled_Case_Check, Room_temperature_standard
]; // チェックボックス反映用

const PAGE_SIZE = 10; // 表示件数（設定値）

// typeを追加して、セルをクリックしただけで編集可能に
const COLUMNS = [
    { label: '製品', fieldName: 'Product__c', type: 'text', editable: false, wrapText: true },
    { label: 'SKU', fieldName: 'SKU__c', type: 'text', editable: false, wrapText: true },
    { label: 'フェイス数', fieldName: 'FaceCount__c', type: 'text', editable: true, wrapText: true, cellAttributes: { alignment: 'left' } }
];

export default class RelatedListEditor extends LightningElement {
    @api recordId; // Journal__c のレコードID
    @track accountId;
    @track chilledCaseChecked = false;
    @track roomTempStandardChecked = false;
    @api hasPagination; // ページネーション用
    // モーダル用
    @track showConfirmModal = false;
    @track pendingCheckboxField = '';
    @track pendingCheckboxValue = false;
    @track pendingCheckboxLabel = '';

    @track originalChilledCaseChecked = false;
    @track originalRoomTempStandardChecked = false;

    records = [];
    recordsType1 = [];
    recordsType2 = [];
    recordsType3 = [];
    recordsType4 = [];
    recordsType5 = [];
    recordsType6 = [];
    recordsType7 = [];
    recordsType8 = [];
    recordsType9 = [];
    recordsType10 = [];
    error;
    columns = COLUMNS;
    // draftValues = {};
    draftValues = [];//オブジェクト形式（{}）→配列形式（[]）:

    originalRecordsType3 = []; //キャンセル時に元に戻すために用意
    originalRecordsType4 = [];
    originalRecordsType5 = [];
    originalRecordsType6 = [];
    originalRecordsType7 = [];
    originalRecordsType8 = [];
    originalRecordsType9 = [];
    originalRecordsType10 = [];

    isSaveVisible = false; // 保存ボタン表示用フラグ

    recordTypeKeys = ['recordsType3', 'recordsType4', 'recordsType5', 'recordsType6', 'recordsType7', 'recordsType8', 'recordsType9', 'recordsType10'];
    dataMap = {}; // 各recordTypeの全データ
    pageMap = {}; // 各recordTypeの現在ページ
    totalPageMap = {}; // 各recordTypeの最大ページ
    paginatedMap = {}; // 各recordTypeの表示対象データ
    showPaginationMap = {}; // ページネーション表示制御
    previousPageMap = {}; // 更新時にいたページを保持
    
    connectedCallback() {
        // ページマップを初期化
        this.recordTypeKeys.forEach(type => {
            this.pageMap[type] = 1;
        });
        
        // 2025年9月3日追加：コンポーネント初期化時にキャッシュをリフレッシュ
        // これにより、リロード時に最新データが取得される
        // 2025年9月3日修正：入力タブと前月履歴タブで独立したフラグを使用
        // 両方のタブが確実にリフレッシュされるように修正
        this.isInitialRefreshCurrent = true;  // 入力タブ用フラグ
        this.isInitialRefreshPrevious = true; // 前月履歴タブ用フラグ
    }

    currentEditingRecordId = null;
    previousEditingRecordId = null;

    wiredDataResult;
    isInitialLoad = true;

    // 直近履歴表示・日誌紐付け更新用
    isLoading = false;
    isReparentButtonDisabled = true;
    showReparentClickModal = false;
    submittedDate = ''; // 提出済み直近定番売場調査日
    wiredSubmittedSurveysResult = []; // 提出済み直近定番売場調査レコード
    submittedSurveysDataMap = {}; // テーブル表示用に加工した提出済み直近定番売場調査レコード
    submittedSurveysError = null; // 提出済み直近定番売場調査レコード取得エラー情報
    submittedSurveysPageMap = {}; // 直近履歴表示タブ用の各recordTypeの現在ページ
    submittedSurveysTotalPageMap = {}; // 直近履歴表示タブ用の各recordTypeの最大ページ
    submittedSurveysPaginatedMap = {}; // 直近履歴表示タブ用の各recordTypeの表示対象データ
    submittedSurveysShowPaginationMap = {}; // 直近履歴表示タブ用のページネーション表示制御
    submittedSurveysPreviousPageMap = {}; // 直近履歴表示タブ用の更新時にいたページを保持

    submittedColdBeerRecords = [];
    submittedColdRTDRecords = [];
    submittedColdOtherAttRecords = [];
    submittedColdOtherComRecords = [];
    submittedRoomBeerRecords = [];
    submittedRoomRTDRecords = [];
    submittedRoomOtherAttRecords = [];
    submittedRoomOtherComRecords = [];
    submittedSurveysColumns = COLUMNS;
    submittedSurveysRecordTypeKeys = ['submittedColdBeerRecords', 'submittedColdRTDRecords', 'submittedColdOtherAttRecords', 'submittedColdOtherComRecords', 'submittedRoomBeerRecords', 'submittedRoomRTDRecords', 'submittedRoomOtherAttRecords', 'submittedRoomOtherComRecords'];

    lastModifiedDateThisMonth = ''; // 今月の定番売場調査レコード最終更新日
    lastModifiedDateLastMonth = ''; // 先月の定番売場調査レコード最終更新日

    @track isJournalSubmitted = false; // 日誌が提出済みかどうかを保持

    // チェックボックス処理
    // Journal__c のレコードから Account の ID を取得
    @wire(getRecord, {
        recordId: '$recordId',
        fields: [JOURNAL_CUSTOMER_FIELD, JOURNAL_REPORTDONE_FIELD]
    })
    wiredJournal({ error, data }) {
        if (data) {
            this.accountId = data.fields.customer__c.value;
            this.isJournalSubmitted = data.fields.reportdone__c.value;
        } else if (error) {
            console.error('Journalレコード取得エラー:', error);
        }
    }

    // Account のチェックボックス項目を取得
    @wire(getRecord, {
        recordId: '$accountId',
        fields: ACCOUNT_FIELDS
    })
    wiredAccount({ error, data }) {
        if (data) {
            this.chilledCaseChecked = data.fields.Chilled_Case_Check__c.value;
            this.originalChilledCaseChecked = this.chilledCaseChecked;

            this.roomTempStandardChecked = data.fields.Room_temperature_standard__c.value;
            this.originalRoomTempStandardChecked = this.roomTempStandardChecked;
        } else if (error) {
            console.error('Accountレコード取得エラー:', error);
        }
    }

    // handleCheckboxChange(event) {
    //     console.log('▶ handleCheckboxChange');
    //     console.log(' target.name:', event.target.name);
    //     console.log(' target.checked:', event.target.checked);
    //     this.pendingCheckboxField = event.target.name;
    //     this.pendingCheckboxValue = event.target.checked;
    //     this.pendingCheckboxLabel = event.target.label;
    //     console.log(' pendingCheckboxField:', this.pendingCheckboxField);
    //     console.log(' pendingCheckboxValue:', this.pendingCheckboxValue);
    //     console.log(' pendingCheckboxLabel:', this.pendingCheckboxLabel);
    //     this.showConfirmModal = true;
    // }

    get isReadOnly() {
        return this.isJournalSubmitted;
    }

    handleCheckboxChange(event) {
        this.pendingCheckboxField = event.target.name;
        this.pendingCheckboxValue = event.target.checked;
        this.pendingCheckboxLabel = event.target.label;

        ExampleModal.open({
            size: 'small',
            label: '確認',
            description: `「${this.pendingCheckboxLabel}」を変更してもよろしいですか？`
        }).then((result) => {
            if (result === 'ok') {
                this.handleConfirmCheckboxChange();
            } else {
                this.handleCancelCheckboxChange();
            }
        });
    }


    // handleConfirmCheckboxChange() {
    //     console.log('▶ handleConfirmCheckboxChange');
    //     console.log(' pendingCheckboxField:', this.pendingCheckboxField);
    //     console.log(' pendingCheckboxValue:', this.pendingCheckboxValue);
    //     console.log(' originalChilledCaseChecked:', this.originalChilledCaseChecked);
    //     console.log(' originalRoomTempStandardChecked:', this.originalRoomTempStandardChecked);

    //     const fields = {
    //         Id: this.accountId,
    //         [this.pendingCheckboxField]: this.pendingCheckboxValue
    //     };

    //     console.log(' calling updateRecord with fields:', fields);
    //     updateRecord({ fields })
    //         .then(() => {
    //             console.log(' updateRecord.then');
    //             this.dispatchEvent(new ShowToastEvent({
    //                 title: '保存成功',
    //                 message: '顧客情報を更新しました',
    //                 variant: 'success'
    //             }));
    //             // ✅ 保存成功後に original 値を更新
    //             if (this.pendingCheckboxField === 'Chilled_Case_Check__c') {
    //                 this.originalChilledCaseChecked = this.pendingCheckboxValue;
    //                 console.log(' updated originalChilledCaseChecked to', this.originalChilledCaseChecked);
    //                 // 「冷ケース」が ON なら recordsType3〜6 を空に
    //                 if (this.pendingCheckboxValue) {
    //                     this.recordsType3 = [];
    //                     this.recordsType4 = [];
    //                     this.recordsType5 = [];
    //                     this.recordsType6 = [];
    //                     // もしページネーションにも影響があれば
    //                     this.showPaginationMap.recordsType3 = false;
    //                     this.showPaginationMap.recordsType4 = false;
    //                     this.showPaginationMap.recordsType5 = false;
    //                     this.showPaginationMap.recordsType6 = false;
    //                 }
    //             } else if (this.pendingCheckboxField === 'Room_temperature_standard__c') {
    //                 this.originalRoomTempStandardChecked = this.pendingCheckboxValue;
    //                 console.log(' updated originalRoomTempStandardChecked to', this.originalRoomTempStandardChecked);
    //                 // 「常温定番」が ON なら recordsType7〜10 を空に
    //                 if (this.pendingCheckboxValue) {
    //                     this.recordsType7 = [];
    //                     this.recordsType8 = [];
    //                     this.recordsType9 = [];
    //                     this.recordsType10 = [];
    //                     this.showPaginationMap.recordsType7 = false;
    //                     this.showPaginationMap.recordsType8 = false;
    //                     this.showPaginationMap.recordsType9 = false;
    //                     this.showPaginationMap.recordsType10 = false;
    //                 }
    //             }
    //         })
    //         .catch(error => {
    //             console.log(' updateRecord.catch', error);
    //             this.dispatchEvent(new ShowToastEvent({
    //                 title: 'エラー',
    //                 message: error.body.message,
    //                 variant: 'error'
    //             }));
    //         });
    //     this.showConfirmModal = false;
    // }


    handleConfirmCheckboxChange() {
        console.log('▶ handleConfirmCheckboxChange');
        console.log(' pendingCheckboxField:', this.pendingCheckboxField);
        console.log(' pendingCheckboxValue:', this.pendingCheckboxValue);
        console.log(' originalChilledCaseChecked:', this.originalChilledCaseChecked);
        console.log(' originalRoomTempStandardChecked:', this.originalRoomTempStandardChecked);

        this.currentEditingRecordId = null;
        this.nowClickRecordId = null;

        this.recordTypeKeys.forEach(key => {
            this[key] = this[key].map(rec => ({ ...rec, isEditing: false }));
        });

        this.recordTypeKeys.forEach(type => this.updatePaginatedRecords(type));


        const fields = {
            Id: this.accountId,
            [this.pendingCheckboxField]: this.pendingCheckboxValue
        };

        console.log(' calling updateRecord with fields:', fields);
        updateRecord({ fields })
            .then(() => {
                console.log(' updateRecord.then');
                this.dispatchEvent(new ShowToastEvent({
                    title: '保存成功',
                    message: '顧客情報を更新しました',
                    variant: 'success'
                }));

                // original 値の更新
                if (this.pendingCheckboxField === 'Chilled_Case_Check__c') {
                    this.originalChilledCaseChecked = this.pendingCheckboxValue;

                    if (this.pendingCheckboxValue) {
                        const affectedRecords = [
                            ...this.recordsType3,
                            ...this.recordsType4,
                            ...this.recordsType5,
                            ...this.recordsType6
                        ];
                        Promise.all(
                            affectedRecords.map(rec =>
                                updateRecord({
                                    fields: {
                                        Id: rec.Id,
                                        FaceCount__c: '',
                                        // 手動更新日時を更新
                                        LastManualUpdateDate__c: new Date().toISOString()
                                    }
                                })
                            )
                        ).then(() => {
                            this.dispatchEvent(new ShowToastEvent({
                                title: 'フェイス数クリア',
                                message: '冷ケースのフェイス数を空に更新しました',
                                variant: 'success'
                            }));

                            // 表示更新（optional: UI反映）
                            this.recordsType3 = this.recordsType3.map(rec => ({ ...rec, FaceCount__c: '' }));
                            this.recordsType4 = this.recordsType4.map(rec => ({ ...rec, FaceCount__c: '' }));
                            this.recordsType5 = this.recordsType5.map(rec => ({ ...rec, FaceCount__c: '' }));
                            this.recordsType6 = this.recordsType6.map(rec => ({ ...rec, FaceCount__c: '' }));
                            
                            // 売場なしチェックボックスOFF時に削除された値が復活しないよう、dataMapも更新
                            ['recordsType3', 'recordsType4', 'recordsType5', 'recordsType6'].forEach(type => {
                                if (this.dataMap[type]) {
                                    this.dataMap[type] = this.dataMap[type].map(rec => ({ ...rec, FaceCount__c: '' }));
                                }
                            });
                            
                            // ページネーションの再描画
                            this.recordTypeKeys.forEach(type => this.updatePaginatedRecords(type));
                        });
                    }

                } else if (this.pendingCheckboxField === 'Room_temperature_standard__c') {
                    this.originalRoomTempStandardChecked = this.pendingCheckboxValue;

                    if (this.pendingCheckboxValue) {
                        const affectedRecords = [
                            ...this.recordsType7,
                            ...this.recordsType8,
                            ...this.recordsType9,
                            ...this.recordsType10
                        ];
                        Promise.all(
                            affectedRecords.map(rec =>
                                updateRecord({
                                    fields: {
                                        Id: rec.Id,
                                        FaceCount__c: '', // コマ数も FaceCount__c フィールドで管理されている前提
                                        // 手動更新日時を更新
                                        LastManualUpdateDate__c: new Date().toISOString()
                                    }
                                })
                            )
                        ).then(() => {
                            this.dispatchEvent(new ShowToastEvent({
                                title: 'コマ数クリア',
                                message: '常温定番のコマ数を空に更新しました',
                                variant: 'success'
                            }));

                            this.recordsType7 = this.recordsType7.map(rec => ({ ...rec, FaceCount__c: '' }));
                            this.recordsType8 = this.recordsType8.map(rec => ({ ...rec, FaceCount__c: '' }));
                            this.recordsType9 = this.recordsType9.map(rec => ({ ...rec, FaceCount__c: '' }));
                            this.recordsType10 = this.recordsType10.map(rec => ({ ...rec, FaceCount__c: '' }));
                            
                            // 売場なしチェックボックスOFF時に削除された値が復活しないよう、dataMapも更新
                            ['recordsType7', 'recordsType8', 'recordsType9', 'recordsType10'].forEach(type => {
                                if (this.dataMap[type]) {
                                    this.dataMap[type] = this.dataMap[type].map(rec => ({ ...rec, FaceCount__c: '' }));
                                }
                            });
                            
                            // ページネーションの再描画
                            this.recordTypeKeys.forEach(type => this.updatePaginatedRecords(type));
                        });
                    }
                }
            })
            .catch(error => {
                console.log(' updateRecord.catch', error);
                this.dispatchEvent(new ShowToastEvent({
                    title: 'エラー',
                    message: error?.body?.message || '不明なエラーが発生しました',
                    variant: 'error'
                }));
            })
            .finally(() => {
                this.showConfirmModal = false;
            });
    }


    handleCancelCheckboxChange() {

        this.currentEditingRecordId = null;
        this.nowClickRecordId = null;

        this.recordTypeKeys.forEach(key => {
            this[key] = this[key].map(rec => ({ ...rec, isEditing: false }));
        });

        this.recordTypeKeys.forEach(type => this.updatePaginatedRecords(type));


        // JS 上のプロパティを元に戻す
        if (this.pendingCheckboxField === 'Chilled_Case_Check__c') {
            this.chilledCaseChecked = this.originalChilledCaseChecked;
        } else {
            this.roomTempStandardChecked = this.originalRoomTempStandardChecked;
        }

        // data-field 属性で要素を取得
        const selector = `lightning-input[data-field="${this.pendingCheckboxField}"]`;
        const checkboxCmp = this.template.querySelector(selector);
        if (checkboxCmp) {
            const newChecked = (this.pendingCheckboxField === 'Chilled_Case_Check__c')
                ? this.chilledCaseChecked
                : this.roomTempStandardChecked;
            checkboxCmp.checked = newChecked;
        }

        this.showConfirmModal = false;
    }


    // ページング用getter
    getCurrentPage(type) {
        return this.pageMap[type] || 1;
    }

    getTotalPages(type) {
        return this.totalPageMap[type] || 1;
    }

    get shouldShowPagination_type3() { return this.shouldShowPagination('recordsType3'); }
    get shouldShowPagination_type4() { return this.shouldShowPagination('recordsType4'); }
    get shouldShowPagination_type5() { return this.shouldShowPagination('recordsType5'); }
    get shouldShowPagination_type6() { return this.shouldShowPagination('recordsType6'); }
    get shouldShowPagination_type7() { return this.shouldShowPagination('recordsType7'); }
    get shouldShowPagination_type8() { return this.shouldShowPagination('recordsType8'); }
    get shouldShowPagination_type9() { return this.shouldShowPagination('recordsType9'); }
    get shouldShowPagination_type10() { return this.shouldShowPagination('recordsType10'); }

    get isFirstPage_type3() { return this.getCurrentPage('recordsType3') === 1; }
    get isLastPage_type3() { return this.getCurrentPage('recordsType3') === this.getTotalPages('recordsType3'); }
    get currentPage_type3() { return this.getCurrentPage('recordsType3'); }
    get totalPage_type3() { return this.getTotalPages('recordsType3'); }

    get isFirstPage_type4() { return this.getCurrentPage('recordsType4') === 1; }
    get isLastPage_type4() { return this.getCurrentPage('recordsType4') === this.getTotalPages('recordsType4'); }
    get currentPage_type4() { return this.getCurrentPage('recordsType4'); }
    get totalPage_type4() { return this.getTotalPages('recordsType4'); }

    get isFirstPage_type5() { return this.getCurrentPage('recordsType5') === 1; }
    get isLastPage_type5() { return this.getCurrentPage('recordsType5') === this.getTotalPages('recordsType5'); }
    get currentPage_type5() { return this.getCurrentPage('recordsType5'); }
    get totalPage_type5() { return this.getTotalPages('recordsType5'); }

    get isFirstPage_type6() { return this.getCurrentPage('recordsType6') === 1; }
    get isLastPage_type6() { return this.getCurrentPage('recordsType6') === this.getTotalPages('recordsType6'); }
    get currentPage_type6() { return this.getCurrentPage('recordsType6'); }
    get totalPage_type6() { return this.getTotalPages('recordsType6'); }

    get isFirstPage_type7() { return this.getCurrentPage('recordsType7') === 1; }
    get isLastPage_type7() { return this.getCurrentPage('recordsType7') === this.getTotalPages('recordsType7'); }
    get currentPage_type7() { return this.getCurrentPage('recordsType7'); }
    get totalPage_type7() { return this.getTotalPages('recordsType7'); }

    get isFirstPage_type8() { return this.getCurrentPage('recordsType8') === 1; }
    get isLastPage_type8() { return this.getCurrentPage('recordsType8') === this.getTotalPages('recordsType8'); }
    get currentPage_type8() { return this.getCurrentPage('recordsType8'); }
    get totalPage_type8() { return this.getTotalPages('recordsType8'); }

    get isFirstPage_type9() { return this.getCurrentPage('recordsType9') === 1; }
    get isLastPage_type9() { return this.getCurrentPage('recordsType9') === this.getTotalPages('recordsType9'); }
    get currentPage_type9() { return this.getCurrentPage('recordsType9'); }
    get totalPage_type9() { return this.getTotalPages('recordsType9'); }

    get isFirstPage_type10() { return this.getCurrentPage('recordsType10') === 1; }
    get isLastPage_type10() { return this.getCurrentPage('recordsType10') === this.getTotalPages('recordsType10'); }
    get currentPage_type10() { return this.getCurrentPage('recordsType10'); }
    get totalPage_type10() { return this.getTotalPages('recordsType10'); }

    // // 親レコードIDが変更されたときに関連リストを再取得する
    // @wire(getRelatedListRecords, {
    //     parentRecordId: '$recordId', // 動的に渡された親レコードID
    //     relatedListId: 'journals__r', // 関連リストAPI名
    //     fields: [
    //         'StandardSalesFloorSurveyReport__c.Product__c',
    //         'StandardSalesFloorSurveyReport__c.FaceCount__c',
    //         'StandardSalesFloorSurveyReport__c.SalesFloorSelection__c',
    //         'StandardSalesFloorSurveyReport__c.attribute__c'
    //     ]
    // })


    // wiredRelatedList({ error, data }) {
    //     if (data) {
    //         const records = data.records.map((record, idx) => ({
    //             Id: record.id,
    //             Product__c: record.fields.Product__c.value,
    //             FaceCount__c: record.fields.FaceCount__c.value,
    //             SalesFloorSelection__c: record.fields.SalesFloorSelection__c.value,
    //             attribute__c: record.fields.attribute__c.value, 
    //             rowIndex: idx + 1
    //         }));

    //         const filters = {
    //             recordsType3: r => r.SalesFloorSelection__c === '冷ケース' && r.attribute__c === 'ビールテイスト',
    //             recordsType4: r => r.SalesFloorSelection__c === '冷ケース' && r.attribute__c === 'RTD',
    //             recordsType5: r => r.SalesFloorSelection__c === '冷ケース' && !['他社', 'RTD', 'ビールテイスト'].includes(r.attribute__c),
    //             recordsType6: r => r.SalesFloorSelection__c === '冷ケース' && r.attribute__c === '他社',
    //             recordsType7: r => r.SalesFloorSelection__c === 'ケース常温定番' && r.attribute__c === 'ビールテイスト',
    //             recordsType8: r => r.SalesFloorSelection__c === 'ケース常温定番' && r.attribute__c === 'RTD',
    //             recordsType9: r => r.SalesFloorSelection__c === 'ケース常温定番' && !['他社', 'RTD', 'ビールテイスト'].includes(r.attribute__c),
    //             recordsType10: r => r.SalesFloorSelection__c === 'ケース常温定番' && r.attribute__c === '他社',
    //         };

    //         this.recordTypeKeys.forEach(type => {
    //             const filtered = records.filter(filters[type]);
    //             this.dataMap[type] = filtered;
    //             this.pageMap[type] = this.previousPageMap?.[type] || 1;
    //             this.totalPageMap[type] = Math.ceil(filtered.length / PAGE_SIZE);
    //             this.showPaginationMap[type] = filtered.length > PAGE_SIZE;
    //             this.updatePaginatedRecords(type);
    //         });
    //     } else if (error) {
    //         console.error('取得エラー:', error);
    //     }
    // }


    @wire(getSurveyReportsForJournal, { accountId: '$accountId', journalId: '$recordId'})
    wiredRelatedList(result) {
        this.wiredDataResult = result; // 結果を保存
        
        // accountIdがない場合は処理をスキップ
        if (!this.accountId) {
            return;
        }
        
        // 2025年9月3日追加：初回リフレッシュ処理
        // コンポーネント初期化時に一度だけキャッシュをリフレッシュ
        // 2025年9月3日修正：入力タブ専用のフラグを使用
        if (this.isInitialRefreshCurrent && result.data) {
            this.isInitialRefreshCurrent = false;
            refreshApex(this.wiredDataResult);
        }
        
        if (result.data) {

            // 2025年9月16日修正：SortNumber__cを追加
            const records = result.data.surveyReports.map((record, idx) => ({
                Id: record.Id,
                Product__c: record.Product__c,
                SKU__c: record.SKU__c ?? '',  // 実際のデータを取得
                FaceCount__c: record.FaceCount__c ?? '',
                SalesFloorSelection__c: record.SalesFloorSelection__c,
                attribute__c: record.attribute__c,
                SortNumber__c: record.SortNumber__c,  // 2025年9月16日追加
                InHouseConflict__c: record.InHouseConflict__c ?? '',  // 2025年9月30日追加
                rowIndex: idx + 1
            }));

            const filters = {
                recordsType3: r => r.SalesFloorSelection__c === '冷ケース' && r.attribute__c === 'ビールテイスト',
                recordsType4: r => r.SalesFloorSelection__c === '冷ケース' && r.attribute__c === 'RTD',
                recordsType5: r => r.SalesFloorSelection__c === '冷ケース' && !['RTD', 'ビールテイスト'].includes(r.attribute__c) && r.InHouseConflict__c !== '競合',
                recordsType6: r => r.SalesFloorSelection__c === '冷ケース' && r.InHouseConflict__c === '競合',
                recordsType7: r => r.SalesFloorSelection__c === 'ケース常温定番' && r.attribute__c === 'ビールテイスト',
                recordsType8: r => r.SalesFloorSelection__c === 'ケース常温定番' && r.attribute__c === 'RTD',
                recordsType9: r => r.SalesFloorSelection__c === 'ケース常温定番' && !['RTD', 'ビールテイスト'].includes(r.attribute__c) && r.InHouseConflict__c !== '競合',
                recordsType10: r => r.SalesFloorSelection__c === 'ケース常温定番' && r.InHouseConflict__c === '競合',
            };

            this.recordTypeKeys.forEach(type => {
                const filtered = records.filter(filters[type]);
                this.dataMap[type] = filtered;  // フィルタリング後のデータをそのまま使用
                this.pageMap[type] = this.previousPageMap?.[type] || 1;
                this.totalPageMap[type] = Math.ceil(filtered.length / PAGE_SIZE);
                this.showPaginationMap[type] = filtered.length > PAGE_SIZE;
                this.updatePaginatedRecords(type);
            });

            // 日付表示処理
            if (result.data.formattedDate) {
                this.lastModifiedDateThisMonth = result.data.formattedDate;
            } else {
                this.lastModifiedDateThisMonth = '';
            }
        } else if (result.error) {
            this.wiredDataResult = result; 
            console.error('wiredRelatedList 取得エラー:', result.error);
            console.log('wiredGetSubmitted debug error : ', result.error); // debug
        }
        
    }

    // ページング処理
    updatePaginatedRecords(type) {
        const start = (this.pageMap[type] - 1) * PAGE_SIZE;
        const end = start + PAGE_SIZE;
        const paginatedData = this.dataMap[type] ? this.dataMap[type].slice(start, end) : [];
        const pageRecords = this[type]; // 追加

        this[type] = paginatedData.map((rec, idx) => ({
            ...rec,
            /* ページング時も連番を維持するよう修正 */
            rowIndex: start + idx + 1,  /* ページ番号を考慮した連番 */
            isEditing: rec.Id === this.currentEditingRecordId // 追加することで保存後にフォーカスが合う
        }));

        // ページ内に編集中のレコードがあれば、すぐにフォーカス
        if (this.currentEditingRecordId &&
            pageRecords.some(rec => rec.Id === this.currentEditingRecordId)
        ) {
            // 非同期にせず setTimeout(0) だけ入れれば iOS でもユーザー・ジェスチャー扱い
            setTimeout(() => {
                const inputEl = this.template.querySelector(
                    `input[data-id="${this.currentEditingRecordId}"]`
                );
                if (inputEl) {
                    inputEl.focus();
                    try {
                        inputEl.setSelectionRange(
                            inputEl.value.length,
                            inputEl.value.length
                        );
                    } catch (e) {
                        console.warn('カーソル位置設定失敗', e);
                    }
                }
            }, 0);
        }
    }

    // 2025年9月17日修正：前月履歴タブのページング機能を修正
    // 前月履歴タブ（submittedで始まるtype）の場合は専用のマップとメソッドを使用
    handleFirstPage(event) {
        const type = event.target.dataset.type;
        // 前月履歴タブの判定
        if (type.startsWith('submitted')) {
            this.submittedSurveysPageMap[type] = 1;
            this.updateSubmittedSurveysPaginatedRecords(type);
        } else {
            this.pageMap[type] = 1;
            this.updatePaginatedRecords(type);
        }
    }

    handlePrevPage(event) {
        const type = event.target.dataset.type;
        // 前月履歴タブの判定
        if (type.startsWith('submitted')) {
            if (this.submittedSurveysPageMap[type] > 1) {
                this.submittedSurveysPageMap[type]--;
                this.updateSubmittedSurveysPaginatedRecords(type);
            }
        } else {
            if (this.pageMap[type] > 1) {
                this.pageMap[type]--;
                this.updatePaginatedRecords(type);
            }
        }
    }

    handleNextPage(event) {
        const type = event.target.dataset.type;
        // 前月履歴タブの判定
        if (type.startsWith('submitted')) {
            if (this.submittedSurveysPageMap[type] < this.submittedSurveysTotalPageMap[type]) {
                this.submittedSurveysPageMap[type]++;
                this.updateSubmittedSurveysPaginatedRecords(type);
            }
        } else {
            if (this.pageMap[type] < this.totalPageMap[type]) {
                this.pageMap[type]++;
                this.updatePaginatedRecords(type);
            }
        }
    }

    handleLastPage(event) {
        const type = event.target.dataset.type;
        // 前月履歴タブの判定
        if (type.startsWith('submitted')) {
            this.submittedSurveysPageMap[type] = this.submittedSurveysTotalPageMap[type];
            this.updateSubmittedSurveysPaginatedRecords(type);
        } else {
            this.pageMap[type] = this.totalPageMap[type];
            this.updatePaginatedRecords(type);
        }
    }

    getPaginated(type) {
        return this.paginatedMap[type] || [];
    }

    // 2025年9月17日修正：前月履歴タブのページング機能を修正
    // 前月履歴タブの場合は専用のマップを参照
    getCurrentPage(type) {
        if (type.startsWith('submitted')) {
            return this.submittedSurveysPageMap[type] || 1;
        }
        return this.pageMap[type] || 1;
    }

    getTotalPages(type) {
        if (type.startsWith('submitted')) {
            return this.submittedSurveysTotalPageMap[type] || 1;
        }
        return this.totalPageMap[type] || 1;
    }

    shouldShowPagination(type) {
        if (type.startsWith('submitted')) {
            return this.submittedSurveysShowPaginationMap[type] || false;
        }
        return this.showPaginationMap[type] || false;
    }


    renderedCallback() {
        // 保存後＆wire再描画後の1回だけフォーカス復元
        if (this.nowClickRecordId) {

            const idToFocus = this.nowClickRecordId;

            // 1) 行オブジェクトの再付与
            this.recordTypeKeys.forEach(key => {
                this[key] = this[key].map(rec => ({
                    ...rec,
                    isEditing: rec.Id === this.nowClickRecordId
                }));
            });

            // 2) input にフォーカス
            // （lightning-input の内包 input 要素を querySelector で探す）
            const inputEl = this.template.querySelector(
                `input[data-id="${this.nowClickRecordId}"]`
            );
            if (inputEl) {
                // 軽微な遅延を入れて確実に当てる
                setTimeout(() => {
                    inputEl.focus();
                    inputEl.setSelectionRange(inputEl.value.length, inputEl.value.length);
                }, 10);
            }

            // 3) 一度だけ動かすようクリア
            this.nowClickRecordId = null;

            // カーソルセット
            // → Promise.resolve().then で微妙に再描画後を狙う
            setTimeout(() => {
                const inputCmp = this.template.querySelector(`input[data-id="${idToFocus}"]`);
                if (!inputCmp) {

                    // まずフォーカス
                    inputCmp.focus();

                    try {
                        inputCmp.setSelectionRange(inputCmp.value.length, inputCmp.value.length);
                    } catch (e) {
                        console.warn('setSelectionRange failed', e);
                    }
                }
            }, 50);


            // カーソルセット
            // → Promise.resolve().then で微妙に再描画後を狙う
            Promise.resolve().then(() => {
                const inputCmp = this.template.querySelector(`input[data-id="${idToFocus}"]`);
                if (!inputCmp) {
                    console.warn('input not found yet');
                    return;
                }
                // まずフォーカス
                inputCmp.focus();

                // 少しだけ遅らせてモバイルキーボードを確実に呼び出しつつカーソル移動
                setTimeout(() => {
                    try {
                        inputCmp.setSelectionRange(inputCmp.value.length, inputCmp.value.length);
                    } catch (e) {
                        console.warn('setSelectionRange failed', e);
                    }
                }, 50);
            });
        }
    }


    // 保存時処理
    handleSave(recordIdToRemainEditing) {
        const draftValues = Object.values(this.draftValues);
        this.previousPageMap = { ...this.pageMap };
        console.log('handleSave HIT'); // debug


        if (draftValues.length === 0) {
            this.switchToEditMode(recordIdToRemainEditing);
            return Promise.resolve();
        }

        const savePromises = draftValues.map(draft => {
            const isZeroLike = /^0+$/.test(draft.FaceCount__c);
            if (isZeroLike) draft.FaceCount__c = null;

            // 2025年8月29日修正
            // before: updateRecordの戻り値を使用せず
            // after: updateRecordの戻り値を利用して部分更新を実現
            return updateRecord({
                fields: {
                    Id: draft.Id,
                    FaceCount__c: draft.FaceCount__c,
                    // 手動更新日時を更新
                    LastManualUpdateDate__c: new Date().toISOString()
                }
            }).then(updatedRecord => ({
                updatedRecord,
                draftId: draft.Id,
                newValue: draft.FaceCount__c
            }));
        });

        return Promise.all(savePromises)
            .then((results) => {
                this.dispatchEvent(new ShowToastEvent({
                    title: '成功',
                    message: '定番売場調査を更新しました。',
                    variant: 'success'
                }));
                console.log('保存成功 HIT'); // debug
                let newEditingRecordId = null; // debug

                // 2025年8月29日修正
                // before: refreshApexで全データを再取得（ソートが発生）
                // after: 更新したレコードのみをローカルで部分更新（並び順を維持）
                // 修正理由: フェイス数/コマ数入力時に、更新したレコードが最上部に移動してしまう問題を解決
                results.forEach(result => {
                    // 各recordTypeのデータを更新
                    this.recordTypeKeys.forEach(key => {
                        this[key] = this[key].map(rec => {
                            if (rec.Id === result.draftId) {
                                return {
                                    ...rec,
                                    FaceCount__c: result.newValue,
                                    // updateRecordの戻り値から最新のLastModifiedDateを取得
                                    LastModifiedDate: result.updatedRecord.fields.LastModifiedDate?.value
                                };
                            }
                            return rec;
                        });
                        
                        // dataMapも同様に更新（ページネーション用）
                        if (this.dataMap[key]) {
                            this.dataMap[key] = this.dataMap[key].map(rec => {
                                if (rec.Id === result.draftId) {
                                    return {
                                        ...rec,
                                        FaceCount__c: result.newValue,
                                        LastModifiedDate: result.updatedRecord.fields.LastModifiedDate?.value
                                    };
                                }
                                return rec;
                            });
                        }
                    });
                });
                
                // 表示を更新
                this.recordTypeKeys.forEach(type => this.updatePaginatedRecords(type));
                
                this.draftValues = [];

                // 代入
                // this.previousEditingRecordId = this.currentEditingRecordId;
                // this.currentEditingRecordId = recordIdToRemainEditing;
                this.nowClickRecordId = recordIdToRemainEditing;

                this.isSaveEnd = true;

                // this.recordTypeKeys.forEach(key => {
                //     this[key] = this[key].map(rec => {
                //         const isDrafted = draftValues.find(d => d.Id === rec.Id);
                //         const isRemainEditing = rec.Id === recordIdToRemainEditing;
                //         if (isDrafted && !isRemainEditing) {
                //             newEditingRecordId = "isDrafted && !isRemainEditing"; // debug
                //             return { ...rec, isEditing: false };
                //         } else if (isRemainEditing) {
                //             newEditingRecordId = "isRemainEditing"; // debug
                //             return { ...rec, isEditing: true };
                //         } else {
                //             newEditingRecordId = "else"; // debug
                //             return rec;
                //         }
                //     });
                // });
                // console.log('newEditingRecordId: ' + newEditingRecordId); // debug

                // requestAnimationFrame(() => {
                //     setTimeout(() => {
                //         const inputCmp = this.template.querySelector(`lightning-input[data-id="${recordIdToRemainEditing}"]`);
                //         if (inputCmp) {
                //             inputCmp.focus();
                //             inputCmp.setSelectionRange?.(inputCmp.value.length, inputCmp.value.length);
                //         }
                //     }, 10);
                //     console.log('switchToEditMode: カーソルセット'); // debug
                // });

                // 2025年9月3日追加：保存成功後にdraftValuesをクリア
                // これにより、次回の保存時に古いデータが送信されることを防ぐ
                this.draftValues = [];
                
                if (recordIdToRemainEditing) {
                    this.switchToEditMode(recordIdToRemainEditing);
                }

                // 2025年8月29日修正
                // before: refreshApexで全データを再取得していた
                // after: コメントアウトして部分更新のみに変更
                // 注意: 他ユーザーの更新は画面リロードまで反映されない
                // refreshApex(this.wiredDataResult);
                // refreshApex(this.wiredSubmittedSurveysResult);

            })
            .catch(error => {
                console.error('error: ', JSON.stringify(error));
                this.dispatchEvent(new ShowToastEvent({
                    title: 'エラー',
                    message: error?.body?.message || '不明なエラー',
                    variant: 'error'
                }));
            });
    }


    currentEditingRecordId = null; // インラインが完了したら閉じる処理用
    previousEditingRecordId = null;
    nowClickRecordId = null;
    isSaveEnd = false;

    // セルを選択した時
    // async handleCellClick(event) {
    //     console.log('handleCellClick HIT'); // debug
    //     const recordId = event.currentTarget.dataset.id;
    //     const recordType = event.currentTarget.dataset.recordType;

    //     // ──────────────────────────────
    //     // チェックボックスON時に編集不可ガード
    //     // 冷ケースON時：recordsType3〜6
    //     const isColdType = ['recordsType3','recordsType4','recordsType5','recordsType6']
    //         .includes(recordType);
    //     // 常温定番ON時：recordsType7〜10
    //     const isRoomTempType = ['recordsType7','recordsType8','recordsType9','recordsType10']
    //         .includes(recordType);

    //     if ((isColdType && this.chilledCaseChecked) ||
    //         (isRoomTempType && this.roomTempStandardChecked)) {
    //         return; 
    //     }
    //     // ──────────────────────────────

    //     // 編集中のセルが存在する場合、保存処理を実行
    //     if (this.currentEditingRecordId) {
    //         console.log('handleCellClick handleSave呼出'); // debug
    //         await this.handleSave(recordId);
    //     }

    //     // 新しいセルの編集モードに切り替え
    //     this.switchToEditMode(recordId);

    // }


    async handleCellClick(event) {
        console.log('handleCellClick HIT');
        if(this.isReadOnly) {
            return;
        }
        const recordId = event.currentTarget.dataset.id;
        const recordType = event.currentTarget.dataset.recordType;

        // ──────────────────────────────
        // チェックボックスON時に編集不可ガード
        const isColdType = ['recordsType3', 'recordsType4', 'recordsType5', 'recordsType6']
            .includes(recordType);
        const isRoomTempType = ['recordsType7', 'recordsType8', 'recordsType9', 'recordsType10']
            .includes(recordType);

        if ((isColdType && this.chilledCaseChecked) ||
            (isRoomTempType && this.roomTempStandardChecked)) {
            return;
        }
        // ──────────────────────────────

        // 編集中のセルが存在する場合、保存処理を実行
        if (this.currentEditingRecordId) {
            console.log('handleCellClick handleSave呼出');
            await this.handleSave(recordId);
        }
        // 新しいセルの編集モードに切り替え
        this.switchToEditMode(recordId);
    }

    // セルの値変更時
    handleInputChange(event) {
        console.log('handleInputChange HIT'); // debug
        const recordId = event.target.dataset.id;
        const field = event.target.dataset.field || 'FaceCount__c';
        let newValue = event.target.value;

        // draftValues に追加・更新
        const existingDraft = this.draftValues.find(d => d.Id === recordId);
        if (existingDraft) {
            existingDraft[field] = newValue;
        } else {
            this.draftValues.push({ Id: recordId, [field]: newValue });
        }

        // 一時的に表示にも反映（オプション）
        this.recordTypeKeys.forEach(key => {
            this[key] = this[key].map(rec =>
                rec.Id === recordId ? { ...rec, [field]: newValue } : rec
            );
        });
    }

    // セルの選択が外れた時
    // disableEdit(event) {
    //     const recordId = event.target.dataset.id;
    //     console.log('disableEdit HIT: '); // debug
    //     console.log('recordId: ' + recordId); // debug
    //     const targetId = this.nowClickRecordId || this.currentEditingRecordId;
    //     console.log('targetId: ' + targetId); // debug

    //     // 編集中のセルが存在する場合、または初回のセル選択時（recordIdが存在する場合）は保存処理を実行
    //     if (this.currentEditingRecordId || recordId) {
    //         this.handleSave(null); // 保存処理を実行（編集モードは継続しない）
    //         this.isSaveEnd = false;
    //     }
    // }

    // 修正版 disableEdit
    // disableEdit(event) {
    //     // 1) relatedTarget（次にフォーカスが移る要素）が同じ input なら何もしない
    //     const nextEl = event.relatedTarget;
    //     if (nextEl && nextEl.dataset && nextEl.dataset.id === this.currentEditingRecordId) {
    //         return;
    //     }

    //     // 2) それ以外（別セルに移動、あるいは画面外にフォーカス移動）は保存処理
    //     const recordIdToRemain = null; // blur の場合は閉じるので null のまま
    //     this.handleSave(recordIdToRemain);
    //     this.isSaveEnd = false;

    //     this.currentEditingRecordId = null;
    //     this.nowClickRecordId = null;

    //     this.recordTypeKeys.forEach(type => this.updatePaginatedRecords(type));
    // }

    disableEdit(event) {
        // 1) relatedTarget（次にフォーカスが移る要素）が同じ input なら何もしない
        const nextEl = event.relatedTarget;
        if (nextEl && nextEl.dataset && nextEl.dataset.id === this.currentEditingRecordId) {
            return;
        }

        // 一時的に元のセルIDをキープ
        const prevId = this.currentEditingRecordId;

        // 編集モードをいったんリセット
        this.currentEditingRecordId = null;
        this.nowClickRecordId = null;

        // 保存処理（編集モードは閉じたまま）
        this.handleSave(null);
        this.isSaveEnd = false;

        // 再描画をマイクロタスク末尾にずらして、セル移動を安定化
        setTimeout(() => {
            this.recordTypeKeys.forEach(key => {
                this[key] = this[key].map(rec => {
                    if (rec.Id === prevId) {
                        // 前セルは編集モード解除
                        return { ...rec, isEditing: false };
                    }
                    // クリック先のセルは編集モードON
                    if (nextEl && rec.Id === nextEl.dataset.id) {
                        return { ...rec, isEditing: true };
                    }
                    return rec;
                });
            });
        }, 0);
    }

    // 編集モードかつカーソルを設定
    switchToEditMode(recordId) {

        if (!recordId) {
            return;
        }

        console.log('switchToEditMode HIT'); // debug

        this.previousEditingRecordId = this.currentEditingRecordId;
        this.currentEditingRecordId = recordId;

        console.log('前回編集中セル' + this.previousEditingRecordId); // debug
        console.log('現在編集中のセル' + this.currentEditingRecordId); // debug

        // 編集モードに切り替え
        this.recordTypeKeys.forEach(key => {
            this[key] = this[key].map(rec => {
                if (rec.Id === recordId) return { ...rec, isEditing: true };
                if (rec.Id === this.previousEditingRecordId) return { ...rec, isEditing: false };
                return rec;
            });
        });

        // カーソルセット
        // → Promise.resolve().then で微妙に再描画後を狙う
        Promise.resolve().then(() => {
            const inputCmp = this.template.querySelector(`input[data-id="${recordId}"]`);
            if (!inputCmp) {
                console.warn('input not found yet');
                return;
            }
            // まずフォーカス
            inputCmp.focus();

            // 少しだけ遅らせてモバイルキーボードを確実に呼び出しつつカーソル移動
            setTimeout(() => {
                try {
                    inputCmp.setSelectionRange(inputCmp.value.length, inputCmp.value.length);
                } catch (e) {
                    console.warn('setSelectionRange failed', e);
                }
            }, 50);
        });
    }

    // 前月履歴取得
    @wire(getPreviousMonthSurveyReports, { accountId: '$accountId', journalId: '$recordId'})
    wiredGetSubmitted(result) {
        // 2025年9月3日修正：結果を最初に保存（入力タブと同じ処理順序に統一）
        this.wiredSubmittedSurveysResult = result;
        
        // 2025年9月3日追加：前月履歴も初回リフレッシュ処理
        // 2025年9月3日修正：前月履歴タブ専用のフラグを使用し、フラグをfalseに設定
        // 保存した結果を使用してrefreshApexを呼び出す
        if (this.isInitialRefreshPrevious && result.data) {
            this.isInitialRefreshPrevious = false;
            refreshApex(this.wiredSubmittedSurveysResult);
        }
        
        if (result.data) {
            this.submittedError = null;
            // 2025年9月16日修正：SortNumber__cを追加
            const records = result.data.surveyReports.map((record, idx) => ({
                Id: record.Id,
                Product__c: record.Product__c,
                SKU__c: record.SKU__c ?? '',  // 実際のデータを取得
                FaceCount__c: record.FaceCount__c,
                SalesFloorSelection__c: record.SalesFloorSelection__c,
                attribute__c: record.attribute__c,
                SortNumber__c: record.SortNumber__c,  // 2025年9月16日追加
                InHouseConflict__c: record.InHouseConflict__c ?? '',  // 2025年9月30日追加
                LastModifiedDate: record.LastModifiedDate,
                rowIndex: idx + 1
            }));

            const filters = {
                submittedColdBeerRecords: r => r.SalesFloorSelection__c === '冷ケース' && r.attribute__c === 'ビールテイスト',
                submittedColdRTDRecords: r => r.SalesFloorSelection__c === '冷ケース' && r.attribute__c === 'RTD',
                submittedColdOtherAttRecords: r => r.SalesFloorSelection__c === '冷ケース' && !['RTD', 'ビールテイスト'].includes(r.attribute__c) && r.InHouseConflict__c !== '競合',
                submittedColdOtherComRecords: r => r.SalesFloorSelection__c === '冷ケース' && r.InHouseConflict__c === '競合',
                submittedRoomBeerRecords: r => r.SalesFloorSelection__c === 'ケース常温定番' && r.attribute__c === 'ビールテイスト',
                submittedRoomRTDRecords: r => r.SalesFloorSelection__c === 'ケース常温定番' && r.attribute__c === 'RTD',
                submittedRoomOtherAttRecords: r => r.SalesFloorSelection__c === 'ケース常温定番' && !['RTD', 'ビールテイスト'].includes(r.attribute__c) && r.InHouseConflict__c !== '競合',
                submittedRoomOtherComRecords: r => r.SalesFloorSelection__c === 'ケース常温定番' && r.InHouseConflict__c === '競合',
            };

            this.submittedSurveysRecordTypeKeys.forEach(type => {
                const filtered = records.filter(filters[type]);
                this.submittedSurveysDataMap[type] = filtered;  // フィルタリング後のデータをそのまま使用
                this.submittedSurveysPageMap[type] = this.submittedSurveysPreviousPageMap?.[type] || 1;
                this.submittedSurveysTotalPageMap[type] = Math.ceil(filtered.length / PAGE_SIZE);
                this.submittedSurveysShowPaginationMap[type] = filtered.length > PAGE_SIZE;
                this.updateSubmittedSurveysPaginatedRecords(type);
            });

            // 日付表示処理
            if (result.data.formattedDate) {
                this.lastModifiedDateLastMonth = result.data.formattedDate;
            } else {
                this.lastModifiedDateLastMonth = '';
            }
        } else if (result.error) {
            console.log('wiredGetSubmitted debug error : ', result.error); // debug
            this.submittedError = result.error;
            this.submittedSurveys = null;
            // 2025年9月3日修正：結果の保存は既に実行済みのため削除
        }
    }

    // トースト通知ヘルパー
    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    // 前月履歴レコードの有無を判定（日付表示とレコード表示を分離）
    get hasSubmittedRecords() {
        return this.submittedColdBeerRecords.length > 0 ||
               this.submittedColdRTDRecords.length > 0 ||
               this.submittedColdOtherAttRecords.length > 0 ||
               this.submittedColdOtherComRecords.length > 0 ||
               this.submittedRoomBeerRecords.length > 0 ||
               this.submittedRoomRTDRecords.length > 0 ||
               this.submittedRoomOtherAttRecords.length > 0 ||
               this.submittedRoomOtherComRecords.length > 0;
    }

    // 入力タブのレコードの有無を判定（日付表示とレコード表示を分離）
    get hasCurrentRecords() {
        return this.recordsType3.length > 0 ||
               this.recordsType4.length > 0 ||
               this.recordsType5.length > 0 ||
               this.recordsType6.length > 0 ||
               this.recordsType7.length > 0 ||
               this.recordsType8.length > 0 ||
               this.recordsType9.length > 0 ||
               this.recordsType10.length > 0;
    }

    // 直近履歴タブ用
    get shouldShowPagination_submittedColdBeer() { return this.shouldShowPagination('submittedColdBeerRecords'); }
    get shouldShowPagination_submittedColdRTD() { return this.shouldShowPagination('submittedColdRTDRecords'); }
    get shouldShowPagination_submittedColdOtherAtt() { return this.shouldShowPagination('submittedColdOtherAttRecords'); }
    get shouldShowPagination_submittedColdOtherCom() { return this.shouldShowPagination('submittedColdOtherComRecords'); }
    get shouldShowPagination_submittedRoomBeer() { return this.shouldShowPagination('submittedRoomBeerRecords'); }
    get shouldShowPagination_submittedRoomRTD() { return this.shouldShowPagination('submittedRoomRTDRecords'); }
    get shouldShowPagination_submittedRoomOtherAtt() { return this.shouldShowPagination('submittedRoomOtherAttRecords'); }
    get shouldShowPagination_submittedRoomOtherCom() { return this.shouldShowPagination('submittedRoomOtherComRecords'); }

    get isFirstPage_submittedColdBeer() { return this.getCurrentPage('submittedColdBeerRecords') === 1; }
    get isLastPage_submittedColdBeer() { return this.getCurrentPage('submittedColdBeerRecords') === this.getTotalPages('submittedColdBeerRecords'); }
    get currentPage_submittedColdBeer() { return this.getCurrentPage('submittedColdBeerRecords'); }
    get totalPage_submittedColdBeer() { return this.getTotalPages('submittedColdBeerRecords'); }

    get isFirstPage_submittedColdRTD() { return this.getCurrentPage('submittedColdRTDRecords') === 1; }
    get isLastPage_submittedColdRTD() { return this.getCurrentPage('submittedColdRTDRecords') === this.getTotalPages('submittedColdRTDRecords'); }
    get currentPage_submittedColdRTD() { return this.getCurrentPage('submittedColdRTDRecords'); }
    get totalPage_submittedColdRTD() { return this.getTotalPages('submittedColdRTDRecords'); }

    get isFirstPage_submittedColdOtherAtt() { return this.getCurrentPage('submittedColdOtherAttRecords') === 1; }
    get isLastPage_submittedColdOtherAtt() { return this.getCurrentPage('submittedColdOtherAttRecords') === this.getTotalPages('submittedColdOtherAttRecords'); }
    get currentPage_submittedColdOtherAtt() { return this.getCurrentPage('submittedColdOtherAttRecords'); }
    get totalPage_submittedColdOtherAtt() { return this.getTotalPages('submittedColdOtherAttRecords'); }

    get isFirstPage_submittedColdOtherCom() { return this.getCurrentPage('submittedColdOtherComRecords') === 1; }
    get isLastPage_submittedColdOtherCom() { return this.getCurrentPage('submittedColdOtherComRecords') === this.getTotalPages('submittedColdOtherComRecords'); }
    get currentPage_submittedColdOtherCom() { return this.getCurrentPage('submittedColdOtherComRecords'); }
    get totalPage_submittedColdOtherCom() { return this.getTotalPages('submittedColdOtherComRecords'); }

    get isFirstPage_submittedRoomBeer() { return this.getCurrentPage('submittedRoomBeerRecords') === 1; }
    get isLastPage_submittedRoomBeer() { return this.getCurrentPage('submittedRoomBeerRecords') === this.getTotalPages('submittedRoomBeerRecords'); }
    get currentPage_submittedRoomBeer() { return this.getCurrentPage('submittedRoomBeerRecords'); }
    get totalPage_submittedRoomBeer() { return this.getTotalPages('submittedRoomBeerRecords'); }

    get isFirstPage_submittedRoomRTD() { return this.getCurrentPage('submittedRoomRTDRecords') === 1; }
    get isLastPage_submittedRoomRTD() { return this.getCurrentPage('submittedRoomRTDRecords') === this.getTotalPages('submittedRoomRTDRecords'); }
    get currentPage_submittedRoomRTD() { return this.getCurrentPage('submittedRoomRTDRecords'); }
    get totalPage_submittedRoomRTD() { return this.getTotalPages('submittedRoomRTDRecords'); }

    get isFirstPage_submittedRoomOtherAtt() { return this.getCurrentPage('submittedRoomOtherAttRecords') === 1; }
    get isLastPage_submittedRoomOtherAtt() { return this.getCurrentPage('submittedRoomOtherAttRecords') === this.getTotalPages('submittedRoomOtherAttRecords'); }
    get currentPage_submittedRoomOtherAtt() { return this.getCurrentPage('submittedRoomOtherAttRecords'); }
    get totalPage_submittedRoomOtherAtt() { return this.getTotalPages('submittedRoomOtherAttRecords'); }

    get isFirstPage_submittedRoomOtherCom() { return this.getCurrentPage('submittedRoomOtherComRecords') === 1; }
    get isLastPage_submittedRoomOtherCom() { return this.getCurrentPage('submittedRoomOtherComRecords') === this.getTotalPages('submittedRoomOtherComRecords'); }
    get currentPage_submittedRoomOtherCom() { return this.getCurrentPage('submittedRoomOtherComRecords'); }
    get totalPage_submittedRoomOtherCom() { return this.getTotalPages('submittedRoomOtherComRecords'); }

    updateSubmittedSurveysPaginatedRecords(type) {
        const start = (this.submittedSurveysPageMap[type] - 1) * PAGE_SIZE;
        const end = start + PAGE_SIZE;
        const paginatedData = this.submittedSurveysDataMap[type].slice(start, end);
        const pageRecords = this[type]; // 追加

        this[type] = paginatedData.map((rec, idx) => ({
            ...rec,
            /* ページング時も連番を維持するよう修正 */
            rowIndex: start + idx + 1,  /* ページ番号を考慮した連番 */
        }));
    }
}