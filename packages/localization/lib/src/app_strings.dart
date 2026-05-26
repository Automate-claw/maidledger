import 'package:flutter/material.dart';
import 'locale_provider.dart';

/// Localized strings keyed by AppLocale
class AppStrings {
  static const Map<AppLocale, Map<String, String>> _strings = {
    AppLocale.tradChinese: {
      'settings': '設定',
      'language': '語言',
      'logout': '登出',
      'version': '版本',
      'worker': '工人',
      'employer': '僱主',
      'camera': '相機',
      'album': '相片簿',
      'chat': 'Chat',
      'history': 'History',
      'scan': '掃描',
      'upload_success': '✅ 上傳成功！',
      'upload_success_desc': '1-2分鐘後會有結果',
      'upload_failed': '上傳失敗',
      'upload_failed_retry': '請重新拍攝',
      'save': '儲存',
      'cancel': '取消',
      'confirm': '確認',
      'expense_saved': '✅ 記帳已保存！',
      'expense_save_failed': '❌ 保存失敗',
      'confirm_expense': '💾 確認記帳？',
      'input': '輸入',
      'category': '類別',
      'amount': '金額',
      'date': '日期',
      'note': '備註',
      'note_hint': '例如：6月零用 / 補貼 / 其他',
      'save_payment': '儲存收款記錄',
      'record_payment': '記錄收款',
      'enter_valid_amount': '請輸入有效金額',
      'payment_saved': '✅ 收款記錄已儲存',
      'payment_failed': '儲存失敗',
      'confidence': '信心度',
      'items': '貨品',
      'location': '地點',
      'confirm_location': '確認位置',
      'no_network': '無網絡連接',
      'no_receipt_photo': '沒有收據相片',
      'align_receipt': '請將收據置於框內',
      'cannot_display_photo': '無法顯示相片',
      'photo_attached': '📎 附有相片',
      'history_title': '記帳歷史',
      'error': '錯誤',
      'cash_balance': '現金結餘',
      'recent_records': '最近記錄',
      'overdraft': '透支',
      'item_saved': '✅ 項目已儲存',
      'save_failed': '儲存失敗',
      'update_failed': '更新失敗',
      'delete_failed': '刪除失敗',
      'receipt_detail': '收據詳情',
      'saving': '儲存中...',
      'supermarket': '超市',
      'wet_market': '街市',
      'pharmacy': '藥房',
      'convenience': '便利店',
      'online': '網購',
      'restaurant': '餐廳',
      'cafe': '茶餐廳',
      'takeaway': '外賣',
      'other_store': '其他',
      'no_items': '尚無項目',
      'edit_item': '編輯項目',
      'fish': '魚',
      'pork': '豬肉',
      'beef': '牛肉',
      'chicken': '雞肉',
      'vegetables': '蔬菜',
      'rice': '米',
      'oil': '油',
      'seasoning': '調味料',
      'snack': '零食',
      'drink': '飲品',
      'daily': '日用品',
      'delete_item': '刪除項目',
      'confirm_delete': '確認刪除',
      'delete': '刪除',
      'store_info': '商戶資料',
      'store_name': '商戶名稱',
      'store_category': '商戶類別',
      'item_name': '項目名稱',
      'quantity': '數量',
      'unit_price': '單價 (HK\$)',
      'select_date': '請選擇日期',
      'amount_date': '金額與日期',
      'item_details': '項目明細',
      'need_link_employer': '🔗 需要先連接僱主',
      'enter_invite_code': '請先輸入僱主的邀請碼來連接。',
      'ok': '確定',
      'low_confidence_warning': '（較低，請確認）',
      'photo_expense': '(相片記帳)',
      'ai_thinking': 'AI 正在思考...',
      'type_expense_hint': '輸入記帳內容...',
      'take_photo': '拍照',
      'pick_photo': '相片簿',
      'tap_to_change': '點擊更改',
      'select_language': '選擇語言',
      'greeting': '👋 你好！用任何語言告訴我你想記帳的內容。\n\n'
          '例如：\n'
          '• "買咗菜 45 蚊"\n'
          '• "超市 50"\n'
          '• "街市買魚 80"\n\n'
          '你也可以夾相片作為記帳憑證 📎',
      'rate_limited': '⏱️ 操作太頻繁，請稍後再試。',
      'timeout': '⏱️ AI 回應超時，請再試一次',
      'sorry_error': '⚠️ 抱歉，我遇到問題了。請再試一次。',
      'ask_expense': '請告訴我你想記帳的內容，例如：魚 30蚊',
      'insufficient_data': '📋 資料不足，請提供更多詳細\n\n'
          '請輸入開支格式，例如：\n'
          '• 魚 30蚊\n'
          '• 紅衫魚 1斤 40元\n'
          '• 超市 買餸 \$120',
      'expense_confirm_needed': '📝 已記帳（請確認）：\n'
          '項目：{items}\n'
          '金額：{amount}\n'
          '信心度：{conf}%（較低，請確認）\n\n'
          '確認儲存？ ✅ / ❌',
      'expense_analyzed': '📋 已分析：\n'
          '項目：{items}\n'
          '金額：{amount}\n'
          '類別：{category}\n'
          '信心度：{conf}%\n\n'
          '確認儲存？ ✅ / ❌',
    },
    AppLocale.english: {
      'settings': 'Settings',
      'language': 'Language',
      'logout': 'Log out',
      'version': 'Version',
      'worker': 'Worker',
      'employer': 'Employer',
      'camera': 'Camera',
      'album': 'Album',
      'chat': 'Chat',
      'history': 'History',
      'scan': 'Scan',
      'upload_success': '✅ Upload successful!',
      'upload_success_desc': 'Results in 1-2 minutes',
      'upload_failed': 'Upload failed',
      'upload_failed_retry': 'Please try again',
      'save': 'Save',
      'cancel': 'Cancel',
      'confirm': 'Confirm',
      'expense_saved': '✅ Expense saved!',
      'expense_save_failed': '❌ Failed to save expense',
      'confirm_expense': '💾 Confirm expense?',
      'input': 'Input',
      'category': 'Category',
      'amount': 'Amount',
      'date': 'Date',
      'note': 'Note',
      'note_hint': 'e.g. June allowance / allowance / other',
      'save_payment': 'Save Payment Record',
      'record_payment': 'Record Payment',
      'enter_valid_amount': 'Please enter a valid amount',
      'payment_saved': '✅ Payment record saved',
      'payment_failed': 'Save failed',
      'confidence': 'Confidence',
      'items': 'Items',
      'location': 'Location',
      'confirm_location': 'Confirm location',
      'no_network': 'No network connection',
      'no_receipt_photo': 'No receipt photo',
      'align_receipt': 'Align receipt within frame',
      'cannot_display_photo': 'Cannot display photo',
      'photo_attached': '📎 Photo attached',
      'need_link_employer': '🔗 Link to employer first',
      'enter_invite_code': 'Please enter your employer\'s invite code to link.',
      'ok': 'OK',
      'low_confidence_warning': '(low, please confirm)',
      'photo_expense': '(photo expense)',
      'ai_thinking': 'AI is thinking...',
      'type_expense_hint': 'Enter expense details...',
      'take_photo': 'Take photo',
      'pick_photo': 'Album',
      'tap_to_change': 'Tap to change',
      'select_language': 'Select language',
      'greeting': '👋 Hi! Tell me what you spent in any language.\n\n'
          'Examples:\n'
          '• "fish 30"\n'
          '• "supermarket 50"\n'
          '• "wet market fish 80"\n\n'
          'You can also attach a photo as receipt 📎',
      'rate_limited': '⏱️ Too many requests, please try again later.',
      'timeout': '⏱️ AI response timed out, please try again',
      'sorry_error': '⚠️ Sorry, something went wrong. Please try again.',
      'ask_expense': 'Please tell me what you want to record, e.g.: fish 30',
      'insufficient_data': '📋 Not enough info, please provide more details\n\n'
          'Use expense format, e.g.:\n'
          '• fish 30\n'
          '• red snapper 1lb 40\n'
          '• supermarket groceries \$120',
      'expense_confirm_needed': '📝 Recorded (please confirm):\n'
          'Items：{items}\n'
          'Amount：{amount}\n'
          'Confidence：{conf}% (low)\n\n'
          'Confirm save? ✅ / ❌',
      'expense_analyzed': '📋 Analyzed:\n'
          'Items：{items}\n'
          'Amount：{amount}\n'
          'Category：{category}\n'
          'Confidence：{conf}%\n\n'
          'Confirm save? ✅ / ❌',
      'history_title': 'Expense History',
      'error': 'Error',
      'cash_balance': 'Cash Balance',
      'recent_records': 'Recent Records',
      'overdraft': 'Overdraft',
      'item_saved': '✅ Item saved',
      'save_failed': 'Save failed',
      'update_failed': 'Update failed',
      'delete_failed': 'Delete failed',
      'receipt_detail': 'Receipt Detail',
      'saving': 'Saving...',
      'supermarket': 'Supermarket',
      'wet_market': 'Wet Market',
      'pharmacy': 'Pharmacy',
      'convenience': 'Convenience',
      'online': 'Online',
      'restaurant': 'Restaurant',
      'cafe': 'Cafe',
      'takeaway': 'Takeaway',
      'other_store': 'Other',
      'no_items': 'No items',
      'edit_item': 'Edit Item',
      'fish': 'Fish',
      'pork': 'Pork',
      'beef': 'Beef',
      'chicken': 'Chicken',
      'vegetables': 'Vegetables',
      'rice': 'Rice',
      'oil': 'Oil',
      'seasoning': 'Seasoning',
      'snack': 'Snack',
      'drink': 'Drink',
      'daily': 'Daily',
      'delete_item': 'Delete Item',
      'confirm_delete': 'Confirm delete',
      'delete': 'Delete',
      'store_info': 'Store Info',
      'store_name': 'Store Name',
      'store_category': 'Store Category',
      'item_name': 'Item Name',
      'quantity': 'Quantity',
      'unit_price': 'Unit Price (HK\$)',
      'select_date': 'Select Date',
      'amount_date': 'Amount & Date',
      'item_details': 'Item Details',
    },
    AppLocale.indonesian: {
      'settings': 'Pengaturan',
      'language': 'Bahasa',
      'logout': 'Keluar',
      'version': 'Versi',
      'worker': 'Pekerja',
      'employer': 'Majikan',
      'camera': 'Kamera',
      'album': 'Album',
      'chat': 'Chat',
      'history': 'Riwayat',
      'scan': 'Pindai',
      'upload_success': '✅ Berhasil diunggah!',
      'upload_success_desc': 'Hasil dalam 1-2 menit',
      'upload_failed': 'Unggah gagal',
      'upload_failed_retry': 'Silakan coba lagi',
      'save': 'Simpan',
      'cancel': 'Batal',
      'confirm': 'Konfirmasi',
      'expense_saved': '✅ Biaya disimpan!',
      'expense_save_failed': '❌ Gagal menyimpan biaya',
      'confirm_expense': '💾 Konfirmasi biaya?',
      'input': 'Input',
      'category': 'Kategori',
      'amount': 'Jumlah',
      'date': 'Tanggal',
      'note': 'Catatan',
      'note_hint': 'contoh: uang bulanan / tunjangan / lain',
      'save_payment': 'Simpan Catatan Pembayaran',
      'record_payment': 'Catat Pembayaran',
      'enter_valid_amount': 'Silakan masukkan jumlah yang valid',
      'payment_saved': '✅ Catatan pembayaran tersimpan',
      'payment_failed': 'Gagal menyimpan',
      'confidence': 'Kepercayaan',
      'items': 'Barang',
      'location': 'Lokasi',
      'confirm_location': 'Konfirmasi lokasi',
      'no_network': 'Tidak ada koneksi jaringan',
      'no_receipt_photo': 'Tidak ada foto kuitansi',
      'align_receipt': 'Sejajarkan kuitansi dalam bingkai',
      'cannot_display_photo': 'Tidak dapat menampilkan foto',
      'photo_attached': '📎 Foto dilampirkan',
      'need_link_employer': '🔗 Tautkan ke majikan dulu',
      'enter_invite_code': 'Silakan masukkan kode undangan majikan untuk menautkan.',
      'ok': 'OK',
      'low_confidence_warning': '(rendah, mohon konfirmasi)',
      'photo_expense': '(biaya foto)',
      'ai_thinking': 'AI sedang berpikir...',
      'type_expense_hint': 'Masukkan detail biaya...',
      'take_photo': 'Ambil foto',
      'pick_photo': 'Album',
      'tap_to_change': 'Ketuk untuk mengubah',
      'select_language': 'Pilih bahasa',
      'greeting': '👋 Halo! Beritahu saya pengeluaran Anda dalam bahasa apapun.\n\n'
          'Contoh:\n'
          '• "ikan 30"\n'
          '• "supermarket 50"\n'
          '• "pasar basah ikan 80"\n\n'
          'Anda juga bisa melampirkan foto sebagai kuitansi 📎',
      'rate_limited': '⏱️ Terlalu banyak permintaan, silakan coba lagi nanti.',
      'timeout': '⏱️ Respons AI waktu habis, silakan coba lagi',
      'sorry_error': '⚠️ Maaf, ada yang salah. Silakan coba lagi.',
      'ask_expense': 'Silakan beritahu saya apa yang ingin Anda catat, contoh: ikan 30',
      'insufficient_data': '📋 Info tidak cukup, silakan berikan detail lebih\n\n'
          'Gunakan format biaya, contoh:\n'
          '• ikan 30\n'
          '• ikan merah 1kg 40\n'
          '• supermarket belanja \$120',
      'expense_confirm_needed': '📝 Tercatat (mohon konfirmasi):\n'
          'Barang：{items}\n'
          'Jumlah：{amount}\n'
          'Kepercayaan：{conf}% (rendah)\n\n'
          'Konfirmasi simpan? ✅ / ❌',
      'expense_analyzed': '📋 Dianalisis:\n'
          'Barang：{items}\n'
          'Jumlah：{amount}\n'
          'Kategori：{category}\n'
          'Kepercayaan：{conf}%\n\n'
          'Konfirmasi simpan? ✅ / ❌',
      'history_title': 'Riwayat Pengeluaran',
      'error': 'Kesalahan',
      'cash_balance': 'Saldo Tunai',
      'recent_records': 'Catatan Terbaru',
      'overdraft': 'Kelebihan tarik',
      'item_saved': '✅ Item disimpan',
      'save_failed': 'Gagal menyimpan',
      'update_failed': 'Gagal memperbarui',
      'delete_failed': 'Gagal menghapus',
      'receipt_detail': 'Detail Kuitansi',
      'saving': 'Menyimpan...',
      'supermarket': 'Supermarket',
      'wet_market': 'Pasar Basah',
      'pharmacy': 'Apotek',
      'convenience': 'Convenience',
      'online': 'Online',
      'restaurant': 'Restoran',
      'cafe': 'Kafe',
      'takeaway': 'Bawa Pulang',
      'other_store': 'Lainnya',
      'no_items': 'Tidak ada item',
      'edit_item': 'Edit Item',
      'fish': 'Ikan',
      'pork': 'Daging Babi',
      'beef': 'Daging Sapi',
      'chicken': 'Ayam',
      'vegetables': 'Sayuran',
      'rice': 'Nasi',
      'oil': 'Minyak',
      'seasoning': 'Bumbu',
      'snack': 'Camilan',
      'drink': 'Minuman',
      'daily': 'Barang Sehari-hari',
      'delete_item': 'Hapus Item',
      'confirm_delete': 'Konfirmasi hapus',
      'delete': 'Hapus',
      'store_info': 'Info Toko',
      'store_name': 'Nama Toko',
      'store_category': 'Kategori Toko',
      'item_name': 'Nama Item',
      'quantity': 'Jumlah',
      'unit_price': 'Harga Satuan',
      'select_date': 'Pilih Tanggal',
      'amount_date': 'Jumlah & Tanggal',
      'item_details': 'Detail Item',
    },
    AppLocale.filipino: {
      'settings': 'Mga Setting',
      'language': 'Wika',
      'logout': 'Mag-log out',
      'version': 'Bersyon',
      'worker': 'Kasambahay',
      'employer': 'Employer',
      'camera': 'Kamera',
      'album': 'Album',
      'chat': 'Chat',
      'history': 'Kasaysayan',
      'scan': 'Scan',
      'upload_success': '✅ Matagumpay na na-upload!',
      'upload_success_desc': 'Mga resulta sa 1-2 minuto',
      'upload_failed': 'Nabigo ang pag-upload',
      'upload_failed_retry': 'Mangyaring subuking muli',
      'save': 'I-save',
      'cancel': 'Kanselahin',
      'confirm': 'Kumpirmahin',
      'expense_saved': '✅ Na-save ang gastusin!',
      'expense_save_failed': '❌ Hindi nagtagumpay ang pag-save ng gastusin',
      'confirm_expense': '💾 Kumpirmahin ang gastusin?',
      'input': 'Input',
      'category': 'Kategorya',
      'amount': 'Halaga',
      'date': 'Petsa',
      'note': 'Talaan',
      'note_hint': 'hal. buwanang allowance / subsidy / iba pa',
      'save_payment': 'I-save ang Record ng Pagbabayad',
      'record_payment': 'Mag-record ng Pagbabayad',
      'enter_valid_amount': 'Mangyaring magpasok ng wastong halaga',
      'payment_saved': '✅ Na-save ang record ng pagbabayad',
      'payment_failed': 'Nabigo ang pag-save',
      'confidence': 'Kumpyansa',
      'items': 'Mga bagay',
      'location': 'Lokasyon',
      'confirm_location': 'Kumpirmahin ang lokasyon',
      'no_network': 'Walang koneksyon sa network',
      'no_receipt_photo': 'Walang resibo ng larawan',
      'align_receipt': 'I-align ang resibo sa loob ng frame',
      'cannot_display_photo': 'Hindi ma-display ang larawan',
      'photo_attached': '📎 May larawan na nakakabit',
      'need_link_employer': '🔗 I-link muna sa employer',
      'enter_invite_code': 'Pakilarawan ang invite code ng employer para i-link.',
      'ok': 'OK',
      'low_confidence_warning': '(mababa, pakumpirma)',
      'photo_expense': '(gastusin sa larawan)',
      'ai_thinking': 'Nag-iisip ang AI...',
      'type_expense_hint': 'Ilagay ang details ng gastusin...',
      'take_photo': 'Kumuha ng larawan',
      'pick_photo': 'Album',
      'tap_to_change': 'I-tap para baguhin',
      'select_language': 'Pumili ng wika',
      'greeting': '👋 Kamusta! Sabihin mo sa akin ang gastusin mo sa anumang wika.\n\n'
          'Halimbawa:\n'
          '• "isda 30"\n'
          '• "supermarket 50"\n'
          '• "palengke isda 80"\n\n'
          'Maaari ka rin maglakip ng larawan bilang resibo 📎',
      'rate_limited': '⏱️ Maraming kahilingan, subukan muli sa ibang pagkakataon.',
      'timeout': '⏱️ Nag-time out ang AI, subukan muli',
      'sorry_error': '⚠️ Pasensya, may problema. Subukan muli.',
      'ask_expense': 'Pakiusap sabihin mo kung ano ang gusto mong i-record, hal.: isda 30',
      'insufficient_data': '📋 Hindi sapat ang info, pakibigay ang more details\n\n'
          'Gamitin ang format ng gastusin, hal.:\n'
          '• isda 30\n'
          '• red snapper 1kg 40\n'
          '• supermarket groceries \$120',
      'expense_confirm_needed': '📝 Na-record (pakumpirma):\n'
          'Mga bagay：{items}\n'
          'Halaga：{amount}\n'
          'Kumpyansa：{conf}% (mababa)\n\n'
          'Kumpirmahin ang pag-save? ✅ / ❌',
      'expense_analyzed': '📋 Nai-analize:\n'
          'Mga bagay：{items}\n'
          'Halaga：{amount}\n'
          'Kategorya：{category}\n'
          'Kumpyansa：{conf}%\n\n'
          'Kumpirmahin ang pag-save? ✅ / ❌',
      'history_title': 'Kasaysayan ng Gastos',
      'error': 'Pagkakamali',
      'cash_balance': 'Kuwenta ng Pera',
      'recent_records': 'Kamakailang mga Tala',
      'overdraft': 'Overdraft',
      'item_saved': '✅ Na-save ang item',
      'save_failed': 'Hindi nagtagumpay ang pag-save',
      'update_failed': 'Hindi nagtagumpay ang pag-update',
      'delete_failed': 'Hindi nagtagumpay ang pag-delete',
      'receipt_detail': 'Detalye ng Resibo',
      'saving': 'Nagse-save...',
      'supermarket': 'Supermarket',
      'wet_market': 'Palengke',
      'pharmacy': 'Botika',
      'convenience': 'Convenience',
      'online': 'Online',
      'restaurant': 'Restoran',
      'cafe': 'Kapehan',
      'takeaway': 'Kumuha ng labis',
      'other_store': 'Iba pa',
      'no_items': 'Walang items',
      'edit_item': 'I-edit ang Item',
      'fish': 'Isda',
      'pork': 'Karneng Baboy',
      'beef': 'Karneng Baka',
      'chicken': 'Manok',
      'vegetables': 'Gulay',
      'rice': 'Kanis',
      'oil': 'Langis',
      'seasoning': 'Pampalasa',
      'snack': 'Meryenda',
      'drink': 'Inumin',
      'daily': 'Araw-araw',
      'delete_item': 'Burahin ang Item',
      'confirm_delete': 'Kumpirmahin ang pagbura',
      'delete': 'Burahin',
      'store_info': 'Info ng Store',
      'store_name': 'Pangalan ng Store',
      'store_category': 'Kategorya ng Store',
      'item_name': 'Pangalan ng Item',
      'quantity': 'Dami',
      'unit_price': 'Presyo sa Unit',
      'select_date': 'Pumili ng Petsa',
      'amount_date': 'Halaga at Petsa',
      'item_details': 'Detalye ng Item',
    },
  };

  /// Get a localized string for the given locale
  static String get(AppLocale locale, String key) {
    return _strings[locale]?[key] ?? _strings[AppLocale.tradChinese]![key] ?? key;
  }

  /// Get a localized string with interpolation support for {placeholders}
  static String getWith(AppLocale locale, String key, Map<String, String> vals) {
    String result = get(locale, key);
    for (final entry in vals.entries) {
      result = result.replaceAll('{$entry.key}', entry.value);
    }
    return result;
  }

  /// Get localized greeting for chat screen
  static String greeting(AppLocale locale) => get(locale, 'greeting');
  static String askExpense(AppLocale locale) => get(locale, 'ask_expense');
  static String insufficientData(AppLocale locale) => get(locale, 'insufficient_data');
  static String rateLimited(AppLocale locale) => get(locale, 'rate_limited');
  static String timeout(AppLocale locale) => get(locale, 'timeout');
  static String sorryError(AppLocale locale) => get(locale, 'sorry_error');
  static String expenseSaved(AppLocale locale) => get(locale, 'expense_saved');
  static String expenseSaveFailed(AppLocale locale) => get(locale, 'expense_save_failed');
  static String confirmExpense(AppLocale locale) => get(locale, 'confirm_expense');
  static String lowConfidenceWarning(AppLocale locale) => get(locale, 'low_confidence_warning');
  static String aiThinking(AppLocale locale) => get(locale, 'ai_thinking');
  static String typeExpenseHint(AppLocale locale) => get(locale, 'type_expense_hint');
  static String takePhoto(AppLocale locale) => get(locale, 'take_photo');
  static String pickPhoto(AppLocale locale) => get(locale, 'pick_photo');
  static String selectLanguage(AppLocale locale) => get(locale, 'select_language');
  static String tapToChange(AppLocale locale) => get(locale, 'tap_to_change');
  static String settings(AppLocale locale) => get(locale, 'settings');
  static String language(AppLocale locale) => get(locale, 'language');
  static String logout(AppLocale locale) => get(locale, 'logout');
  static String version(AppLocale locale) => get(locale, 'version');
  static String cancel(AppLocale locale) => get(locale, 'cancel');
  static String confirm(AppLocale locale) => get(locale, 'confirm');
  static String ok(AppLocale locale) => get(locale, 'ok');
  static String save(AppLocale locale) => get(locale, 'save');
  static String needLinkEmployer(AppLocale locale) => get(locale, 'need_link_employer');
  static String enterInviteCode(AppLocale locale) => get(locale, 'enter_invite_code');
  static String input(AppLocale locale) => get(locale, 'input');
  static String category(AppLocale locale) => get(locale, 'category');
  static String amount(AppLocale locale) => get(locale, 'amount');
  static String date(AppLocale locale) => get(locale, 'date');
  static String note(AppLocale locale) => get(locale, 'note');
  static String noteHint(AppLocale locale) => get(locale, 'note_hint');
  static String savePayment(AppLocale locale) => get(locale, 'save_payment');
  static String recordPayment(AppLocale locale) => get(locale, 'record_payment');
  static String enterValidAmount(AppLocale locale) => get(locale, 'enter_valid_amount');
  static String paymentSaved(AppLocale locale) => get(locale, 'payment_saved');
  static String paymentFailed(AppLocale locale) => get(locale, 'payment_failed');
  static String confidence(AppLocale locale) => get(locale, 'confidence');
  static String items(AppLocale locale) => get(locale, 'items');
  static String location(AppLocale locale) => get(locale, 'location');
  static String confirmLocation(AppLocale locale) => get(locale, 'confirm_location');
  static String noNetwork(AppLocale locale) => get(locale, 'no_network');
  static String photoAttached(AppLocale locale) => get(locale, 'photo_attached');
  static String lowConfidence(AppLocale locale) => get(locale, 'low_confidence_warning');
  static String photoExpense(AppLocale locale) => get(locale, 'photo_expense');
  static String chat(AppLocale locale) => get(locale, 'chat');
  static String history(AppLocale locale) => get(locale, 'history');
  static String scan(AppLocale locale) => get(locale, 'scan');
  static String historyTitle(AppLocale locale) => get(locale, 'history_title');
  static String error(AppLocale locale) => get(locale, 'error');
  static String cashBalance(AppLocale locale) => get(locale, 'cash_balance');
  static String recentRecords(AppLocale locale) => get(locale, 'recent_records');
  static String overdraft(AppLocale locale) => get(locale, 'overdraft');
  static String itemSaved(AppLocale locale) => get(locale, 'item_saved');
  static String saveFailed(AppLocale locale) => get(locale, 'save_failed');
  static String updateFailed(AppLocale locale) => get(locale, 'update_failed');
  static String deleteFailed(AppLocale locale) => get(locale, 'delete_failed');
  static String receiptDetail(AppLocale locale) => get(locale, 'receipt_detail');
  static String saving(AppLocale locale) => get(locale, 'saving');
  static String supermarket(AppLocale locale) => get(locale, 'supermarket');
  static String wetMarket(AppLocale locale) => get(locale, 'wet_market');
  static String pharmacy(AppLocale locale) => get(locale, 'pharmacy');
  static String convenience(AppLocale locale) => get(locale, 'convenience');
  static String online(AppLocale locale) => get(locale, 'online');
  static String restaurant(AppLocale locale) => get(locale, 'restaurant');
  static String cafe(AppLocale locale) => get(locale, 'cafe');
  static String takeaway(AppLocale locale) => get(locale, 'takeaway');
  static String otherStore(AppLocale locale) => get(locale, 'other_store');
  static String noItems(AppLocale locale) => get(locale, 'no_items');
  static String noReceiptPhoto(AppLocale locale) => get(locale, 'no_receipt_photo');
  static String cannotDisplayPhoto(AppLocale locale) => get(locale, 'cannot_display_photo');
  static String alignReceipt(AppLocale locale) => get(locale, 'align_receipt');
  static String editItem(AppLocale locale) => get(locale, 'edit_item');
  static String fish(AppLocale locale) => get(locale, 'fish');
  static String pork(AppLocale locale) => get(locale, 'pork');
  static String beef(AppLocale locale) => get(locale, 'beef');
  static String chicken(AppLocale locale) => get(locale, 'chicken');
  static String vegetables(AppLocale locale) => get(locale, 'vegetables');
  static String rice(AppLocale locale) => get(locale, 'rice');
  static String oil(AppLocale locale) => get(locale, 'oil');
  static String seasoning(AppLocale locale) => get(locale, 'seasoning');
  static String snack(AppLocale locale) => get(locale, 'snack');
  static String drink(AppLocale locale) => get(locale, 'drink');
  static String daily(AppLocale locale) => get(locale, 'daily');
  static String deleteItem(AppLocale locale) => get(locale, 'delete_item');
  static String confirmDelete(AppLocale locale) => get(locale, 'confirm_delete');
  static String delete(AppLocale locale) => get(locale, 'delete');
  static String storeInfo(AppLocale locale) => get(locale, 'store_info');
  static String storeName(AppLocale locale) => get(locale, 'store_name');
  static String storeCategory(AppLocale locale) => get(locale, 'store_category');
  static String itemName(AppLocale locale) => get(locale, 'item_name');
  static String quantity(AppLocale locale) => get(locale, 'quantity');
  static String unitPrice(AppLocale locale) => get(locale, 'unit_price');
  static String selectDate(AppLocale locale) => get(locale, 'select_date');
  static String amountDate(AppLocale locale) => get(locale, 'amount_date');
  static String itemDetails(AppLocale locale) => get(locale, 'item_details');
  static String productCategory(AppLocale locale, String cate) => get(locale, 'product_$cate');
  static String uploadSuccess(AppLocale locale) => get(locale, 'upload_success');
  static String uploadSuccessDesc(AppLocale locale) => get(locale, 'upload_success_desc');
  static String uploadFailed(AppLocale locale) => get(locale, 'upload_failed');
  static String uploadFailedRetry(AppLocale locale) => get(locale, 'upload_failed_retry');
}