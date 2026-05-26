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
      'scan': 'Scan',
      'save': '儲存',
      'cancel': '取消',
      'confirm': '確認',
      'cash_balance': '現金餘額',
      'balance': '餘額',
      'overdraft': '透支',
      'received': '已收',
      'spent': '已用',
      'no_relation_hint': '連接僱主以追蹤可用額',
      'receipts': '收據列表',
      'no_receipts': '暫時沒有收據',
      'no_receipts_hint': '工人上傳後會在這裡顯示',
      'payments': '付款記錄',
      'loading_failed': '載入失敗',
      'period_summary': '期間摘要',
      'from_payment': '由 {date} 的付款',
      'items_count': '{count} 項消費',
      'expense_saved': '✅ 記帳已保存！',
,
      'link_employer': '連接僱主',
      'disconnect_employer': '断开僱主連接',
      'disconnect_confirm': '確定要断开與僱主的連接嗎？你的歷史記錄將會保留。',
      'invite_code': '邀請碼',
      'employer_code_hint': '請輸入僱主的6位邀請碼',,
      'delete': '刪除',
      'delete_receipt': '刪除收據',
      'delete_receipt_confirm': '確定刪除這張收據？此操作無法撤銷。',      'expense_save_failed': '❌ 保存失敗',
      'confirm_expense': '💾 確認記帳？',
      'input': '輸入',
      'category': '類別',
      'amount': '金額',
      'confidence': '信心度',
      'items': '貨品',
      'location': '地點',
      'photo_attached': '📎 附有相片',
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
      'save': 'Save',
      'cancel': 'Cancel',
      'confirm': 'Confirm',
      'cash_balance': 'Cash Balance',
      'balance': 'Balance',
      'overdraft': 'overdraft',
      'received': 'Received',
      'spent': 'Spent',
      'no_relation_hint': 'Link employer to track balance',
      'receipts': 'Receipts',
      'no_receipts': 'No receipts yet',
      'no_receipts_hint': 'Receipts from helper will appear here',
      'payments': 'Payments',
      'loading_failed': 'Loading failed',
      'period_summary': 'Period Summary',
      'from_payment': 'From payment on {date}',
      'items_count': '{count} items',
      'expense_saved': '✅ Expense saved!',
,
      'link_employer': 'Link Employer',
      'disconnect_employer': 'Disconnect Employer',
      'disconnect_confirm': 'Are you sure you want to disconnect from this employer? Your history will be kept.',
      'invite_code': 'Invite Code',
      'employer_code_hint': 'Enter employer's 6-character invite code',,
      'delete': 'Delete',
      'delete_receipt': 'Delete Receipt',
      'delete_receipt_confirm': 'Are you sure you want to delete this receipt? This cannot be undone.',      'expense_save_failed': '❌ Failed to save expense',
      'confirm_expense': '💾 Confirm expense?',
      'input': 'Input',
      'category': 'Category',
      'amount': 'Amount',
      'confidence': 'Confidence',
      'items': 'Items',
      'location': 'Location',
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
      'save': 'Simpan',
      'cancel': 'Batal',
      'confirm': 'Konfirmasi',
      'cash_balance': 'Saldo Tunai',
      'balance': 'Saldo',
      'overdraft': 'kurang',
      'received': 'Diterima',
      'spent': 'Dikeluarkan',
      'no_relation_hint': 'Tautkan majikan untuk lacak saldo',
      'receipts': 'Daftar Resibo',
      'no_receipts': 'Belum ada resibo',
      'no_receipts_hint': 'Resibo dari kasambahay akan muncul di sini',
      'payments': 'Pembayaran',
      'loading_failed': 'Gagal memuat',
      'period_summary': 'Ringkasan Periodik',
      'from_payment': 'Dari pembayaran pada {date}',
      'items_count': '{count} item',
      'expense_saved': '✅ Biaya disimpan!',
,
      'link_employer': 'Tautkan Majikan',
      'disconnect_employer': 'Putuskan Hubungan Majikan',
      'disconnect_confirm': 'Apakah Anda yakin ingin memutuskan hubungan dengan majikan ini? Riwayat Anda akan disimpan.',
      'invite_code': 'Kode Undangan',
      'employer_code_hint': 'Masukkan kode undangan 6 karakter majikan',,
      'delete': 'Hapus',
      'delete_receipt': 'Hapus Resibo',
      'delete_receipt_confirm': 'Apakah Anda yakin ingin menghapus resibo ini? Tindakan ini tidak dapat dibatalkan.',      'expense_save_failed': '❌ Gagal menyimpan biaya',
      'confirm_expense': '💾 Konfirmasi biaya?',
      'input': 'Input',
      'category': 'Kategori',
      'amount': 'Jumlah',
      'confidence': 'Kepercayaan',
      'items': 'Barang',
      'location': 'Lokasi',
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
      'save': 'I-save',
      'cancel': 'Kanselahin',
      'confirm': 'Kumpirmahin',
      'cash_balance': 'Cash Balance',
      'balance': 'Balance',
      'overdraft': 'overdraft',
      'received': 'Natanggap',
      'spent': 'Ginasta',
      'no_relation_hint': 'I-link ang employer para subaybayan ang balance',
      'receipts': 'Listahan ng Resibo',
      'no_receipts': 'Wala pang resibo',
      'no_receipts_hint': 'Ang resibo mula sa kasambahay ay lalabas dito',
      'payments': 'Mga Pagbabayad',
      'loading_failed': 'Nabigo ang pag-load',
      'period_summary': 'Buod ng Periodiko',
      'from_payment': 'Mula sa pagbabayad noong {date}',
      'items_count': '{count} na item',
      'expense_saved': '✅ Na-save ang gastusin!',
,
      'link_employer': 'I-link ang Employer',
      'disconnect_employer': 'Alisin ang Koneksyon sa Employer',
      'disconnect_confirm': 'Sigurado ka bang gusto mong alisin ang koneksyon sa employer na ito? Itatago ang iyong kasaysayan.',
      'invite_code': 'Invite Code',
      'employer_code_hint': 'Ilagay ang 6-character invite code ng employer',,
      'delete': 'Burahin',
      'delete_receipt': 'Burahin ang Resibo',
      'delete_receipt_confirm': 'Sigurado ka bang gusto mong burahin ang resibong ito? Hindi ito mababawi.',      'expense_save_failed': '❌ Hindi nagtagumpay ang pag-save ng gastusin',
      'confirm_expense': '💾 Kumpirmahin ang gastusin?',
      'input': 'Input',
      'category': 'Kategorya',
      'amount': 'Halaga',
      'confidence': 'Kumpyansa',
      'items': 'Mga bagay',
      'location': 'Lokasyon',
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
  static String confidence(AppLocale locale) => get(locale, 'confidence');
  static String items(AppLocale locale) => get(locale, 'items');
  static String location(AppLocale locale) => get(locale, 'location');
  static String photoAttached(AppLocale locale) => get(locale, 'photo_attached');
  static String lowConfidence(AppLocale locale) => get(locale, 'low_confidence_warning');
  static String photoExpense(AppLocale locale) => get(locale, 'photo_expense');
  static String chat(AppLocale locale) => get(locale, 'chat');
  static String history(AppLocale locale) => get(locale, 'history');
  static String scan(AppLocale locale) => get(locale, 'scan');
  static String cashBalance(AppLocale locale) => get(locale, 'cash_balance');
  static String balance(AppLocale locale) => get(locale, 'balance');
  static String overdraft(AppLocale locale) => get(locale, 'overdraft');
  static String received(AppLocale locale) => get(locale, 'received');
  static String spent(AppLocale locale) => get(locale, 'spent');
  static String noRelationHint(AppLocale locale) => get(locale, 'no_relation_hint');
  static String receipts(AppLocale locale) => get(locale, 'receipts');
  static String noReceipts(AppLocale locale) => get(locale, 'no_receipts');
  static String noReceiptsHint(AppLocale locale) => get(locale, 'no_receipts_hint');
  static String payments(AppLocale locale) => get(locale, 'payments');
  static String loadingFailed(AppLocale locale) => get(locale, 'loading_failed');
  static String periodSummary(AppLocale locale) => get(locale, 'period_summary');
  static String fromPayment(AppLocale locale, String date) => getWith(locale, 'from_payment', {'{date}': date});
  static String itemsCount(AppLocale locale, String count) => getWith(locale, 'items_count', {'{count}': count});
  static String delete(AppLocale locale) => get(locale, 'delete');
  static String deleteReceipt(AppLocale locale) => get(locale, 'delete_receipt');
  static String deleteReceiptConfirm(AppLocale locale) => get(locale, 'delete_receipt_confirm');
  static String linkEmployer(AppLocale locale) => get(locale, 'link_employer');
  static String disconnectEmployer(AppLocale locale) => get(locale, 'disconnect_employer');
  static String disconnectConfirm(AppLocale locale) => get(locale, 'disconnect_confirm');
  static String inviteCode(AppLocale locale) => get(locale, 'invite_code');
  static String employerCodeHint(AppLocale locale) => get(locale, 'employer_code_hint');
}