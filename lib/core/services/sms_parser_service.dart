import 'package:flutter/services.dart';
import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../features/accounts/models/account_model.dart';
import 'sms_dedup.dart';

/// Prefilled transaction details extracted from SMS.
class ParsedSms {
  final double amount;
  final String merchant;
  final String account;
  final String bankName;
  final String accountSnippet;
  final AccountType accountType;
  final bool isDebit;
  final DateTime date;
  final String body;

  /// Raw sender header, e.g. "VM-HDFCBK".
  final String sender;

  /// Network "sent" timestamp of the SMS in ms (inbox `date_sent` /
  /// PDU `timestampMillis`). Falls back to [date] when unknown.
  final int? sentAtMs;

  const ParsedSms({
    required this.amount,
    required this.merchant,
    required this.account,
    this.bankName = 'Bank',
    this.accountSnippet = '',
    this.accountType = AccountType.bank_account,
    required this.isDebit,
    required this.date,
    required this.body,
    this.sender = '',
    this.sentAtMs,
  });

  /// Stable, install-independent id for this SMS. Used as the expense id.
  String get dedupKey => SmsDedup.key(
        sender: sender,
        sentAtMs: sentAtMs ?? date.millisecondsSinceEpoch,
        body: body,
      );

  /// Id that builds before the v2 key would have produced.
  String get legacyKey => SmsDedup.legacyKey(
        dateMs: date.millisecondsSinceEpoch,
        amount: amount,
        merchant: merchant,
      );

  ParsedSms withSource({required String sender, int? sentAtMs}) => ParsedSms(
        amount: amount,
        merchant: merchant,
        account: account,
        bankName: bankName,
        accountSnippet: accountSnippet,
        accountType: accountType,
        isDebit: isDebit,
        date: date,
        body: body,
        sender: sender,
        sentAtMs: sentAtMs,
      );

  Map<String, dynamic> toJson() => {
        'amount': amount,
        'merchant': merchant,
        'account': account,
        'bankName': bankName,
        'accountSnippet': accountSnippet,
        'accountType': accountType.name,
        'isDebit': isDebit,
        'date': date.toIso8601String(),
        'body': body,
        'sender': sender,
        'sentAtMs': sentAtMs,
      };
}

class SmsScanException implements Exception {
  final String message;
  SmsScanException(this.message);
  @override
  String toString() => message;
}

/// Service to handle SMS permissions, scanning local SMS inbox, and
/// listening to real-time auto-capture intents from the native BroadcastReceiver.
class SmsParserService {
  static const _channel = MethodChannel('com.surya.fiscora/sms_channel');
  final SmsQuery _query = SmsQuery();

  /// Requests SMS permission (required to scan). Notification permission is
  /// only needed for auto-capture alerts, so it is requested but not required.
  Future<bool> requestPermissions() async {
    final smsStatus = await Permission.sms.request();
    // A denied notification permission must not block scanning.
    Permission.notification.request().ignore();
    return smsStatus.isGranted;
  }

  /// Scans the last [limit] messages in the device inbox and returns parsed transactions.
  /// Useful to backfill/import old expenses without waiting for new SMS messages.
  Future<List<ParsedSms>> scanInbox({int limit = 500}) async {
    final status = await Permission.sms.status;
    if (!status.isGranted) return [];

    try {
      final messages = await _query.querySms(
        kinds: [SmsQueryKind.inbox],
        count: limit,
      );
      final List<ParsedSms> transactions = [];
      for (final msg in messages) {
        final body = msg.body;
        final date = msg.date;
        final sender = msg.address ?? '';
        if (body != null && _isLikelyTransactionalSender(sender)) {
          final parsed = parseSmsBody(body, date ?? DateTime.now(), sender: sender);
          if (parsed != null) {
            final sent = msg.dateSent?.millisecondsSinceEpoch;
            transactions.add(parsed.withSource(
              sender: sender,
              sentAtMs: (sent != null && sent > 0) ? sent : date?.millisecondsSinceEpoch,
            ));
          }
        }
      }
      return transactions;
    } catch (e) {
      throw SmsScanException('Could not read your SMS inbox: $e');
    }
  }

  Future<ParsedSms?> getPendingTransaction() async {
    try {
      final Map<dynamic, dynamic>? pending =
      await _channel.invokeMethod('getPendingTransaction');
      if (pending != null) {
        return _parsePlatformMap(pending);
      }
    } catch (_) {}
    return null;
  }

  Future<List<ParsedSms>> getPendingTransactions() async {
    try {
      final List<dynamic>? pendingList =
          await _channel.invokeListMethod('getPendingTransactions');
      if (pendingList != null && pendingList.isNotEmpty) {
        final List<ParsedSms> results = [];
        for (final item in pendingList) {
          if (item is Map) {
            final id = item['id'];
            if (id is String) _fetchedPendingIds.add(id);
            final parsed = _parsePlatformMap(item);
            if (parsed != null) {
              results.add(parsed);
            }
          }
        }
        return results;
      }
    } catch (_) {}

    final single = await getPendingTransaction();
    if (single != null) {
      return [single];
    }
    return [];
  }

  /// Ids of queued items returned by [getPendingTransactions] and not yet acknowledged.
  final Set<String> _fetchedPendingIds = {};

  /// Removes only the queued items this service has already fetched, so an SMS
  /// captured while the batch was being saved stays queued for the next run.
  Future<void> clearPendingTransactions() async {
    if (_fetchedPendingIds.isEmpty) return;
    final ids = _fetchedPendingIds.toList();
    try {
      await _channel.invokeMethod('removePendingTransactions', {'ids': ids});
      _fetchedPendingIds.removeAll(ids);
    } catch (_) {}
  }

  /// Listens to real-time platform channel transactions captured while app is open.
  void setIncomingTransactionListener(void Function(ParsedSms) onCaptured) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onTransactionCaptured') {
        final args = call.arguments;
        if (args is Map) {
          final parsed = _parsePlatformMap(args);
          if (parsed != null) {
            onCaptured(parsed);
          }
        }
      }
    });
  }

  ParsedSms? _parsePlatformMap(Map<dynamic, dynamic> map) {
    final amountVal = map['amount'];
    final amount = amountVal is num ? amountVal.toDouble() : 0.0;
    if (amount <= 0) return null;

    int? asInt(dynamic v) =>
        v is num ? v.toInt() : (v is String ? int.tryParse(v) : null);
    final sentAtMs = asInt(map['sentAtMs']);
    final receivedAtMs = asInt(map['receivedAtMs']);

    final dateStr = map['date'] as String? ?? '';
    final date = receivedAtMs != null
        ? DateTime.fromMillisecondsSinceEpoch(receivedAtMs)
        : (DateTime.tryParse(dateStr) ?? DateTime.now());
    final body = map['body'] as String? ?? '';
    final sender = map['sender'] as String? ?? '';

    // The Dart parser is the source of truth: if it rejects the body (OTP, declined,
    // promo), the native receiver's looser guess is not saved either.
    final parsed = parseSmsBody(body, date, sender: sender);
    return parsed?.withSource(sender: sender, sentAtMs: sentAtMs);
  }

  static String detectBankName(String sender, String body) {
    final upperSender = sender.toUpperCase();
    final lowerBody = body.toLowerCase();

    if (upperSender.contains('HDFC') || lowerBody.contains('hdfc')) return 'HDFC Bank';
    if (upperSender.contains('ICICI') || lowerBody.contains('icici')) return 'ICICI Bank';
    if (upperSender.contains('SBI') || lowerBody.contains('sbi')) return 'SBI';
    if (upperSender.contains('AXIS') || lowerBody.contains('axis')) return 'Axis Bank';
    if (upperSender.contains('KOTAK') || lowerBody.contains('kotak')) return 'Kotak Bank';
    if (upperSender.contains('PYTM') || upperSender.contains('PAYTM') || lowerBody.contains('paytm')) return 'Paytm';
    if (upperSender.contains('GPAY') || lowerBody.contains('gpay') || lowerBody.contains('google pay')) return 'Google Pay';
    if (upperSender.contains('PHONPE') || lowerBody.contains('phonepe')) return 'PhonePe';
    if (upperSender.contains('AMAZON') || lowerBody.contains('amazon pay')) return 'Amazon Pay';
    if (upperSender.contains('YES') || lowerBody.contains('yes bank')) return 'Yes Bank';
    if (upperSender.contains('IDFC') || lowerBody.contains('idfc')) return 'IDFC First Bank';
    if (upperSender.contains('PNB') || lowerBody.contains('pnb')) return 'PNB';
    if (upperSender.contains('BOI') || lowerBody.contains('bank of india')) return 'Bank of India';
    if (upperSender.contains('UNION') || lowerBody.contains('union bank')) return 'Union Bank';
    if (upperSender.contains('CANBNK') || lowerBody.contains('canara bank')) return 'Canara Bank';
    if (upperSender.contains('CENTBK') || lowerBody.contains('central bank')) return 'Central Bank';
    if (upperSender.contains('INDUS') || lowerBody.contains('indusind')) return 'IndusInd Bank';
    if (upperSender.contains('RBL') || lowerBody.contains('rbl')) return 'RBL Bank';
    if (upperSender.contains('BOB') || lowerBody.contains('bank of baroda')) return 'Bank of Baroda';
    if (upperSender.contains('HSBC') || lowerBody.contains('hsbc')) return 'HSBC Bank';
    if (upperSender.contains('FED') || lowerBody.contains('federal bank')) return 'Federal Bank';
    if (upperSender.contains('AUBNK') || lowerBody.contains('au bank')) return 'AU Small Finance Bank';

    return 'Bank';
  }

  static AccountType detectAccountType(String body) {
    final lower = body.toLowerCase();
    if (lower.contains('credit card') ||
        lower.contains('card ending') ||
        lower.contains('cc ending') ||
        lower.contains('cc no') ||
        lower.contains('card xx') ||
        lower.contains('card ending in') ||
        lower.contains('charged to card')) {
      return AccountType.credit_card;
    }
    if (lower.contains('wallet') ||
        lower.contains('paytm wallet') ||
        lower.contains('amazon balance') ||
        lower.contains('wallet balance')) {
      return AccountType.wallet;
    }
    return AccountType.bank_account;
  }

  static const _nonTransactionPhrases = [
    'declined', 'has failed', 'transaction failed', 'unsuccessful',
    'could not be processed', 'will be debited', 'will be deducted', 'is due on',
    'payment due', 'minimum amount due', 'total amount due', 'has requested',
    'collect request', 'is scheduled',
  ];
  static final _otp = RegExp(r'\b(?:otp|one[ -]time password|verification code)\b');

  /// OTPs, declined/failed payments and reminders about future debits.
  static bool isNonTransaction(String lower) =>
      _otp.hasMatch(lower) || _nonTransactionPhrases.any(lower.contains);

  static RegExp _words(List<String> w) => RegExp('\\b(?:${w.map(RegExp.escape).join('|')})\\b');
  static final _strongDebit = _words(['debited', 'debit of']);
  static final _strongCredit = _words(['credited', 'credit of']);
  static final _creditHints = _words(['refund', 'refunded', 'reversed', 'reversal', 'cashback', 'received', 'deposited']);
  static final _debitHints = _words([
    'sent', 'paid', 'spent', 'charged', 'withdrawn', 'withdrawal', 'transferred', 'txnd',
    'txn of', 'purchase of', 'payment of', 'transfer to', 'used at',
  ]);

  /// true = debit, false = credit, null = no transaction verb.
  /// "debited"/"credited" decide first (earliest wins when both appear, e.g.
  /// "debited from A/c X and credited to Y"). Otherwise refunds and receipts win
  /// over weaker debit words, so "refund for your payment of" and a card bill's
  /// "payment of Rs X received" are credits. Words match whole, so "prepaid" ≠ "paid".
  static bool? detectDirection(String lower) {
    final d = _strongDebit.firstMatch(lower);
    final c = _strongCredit.firstMatch(lower);
    if (d != null && c != null) return d.start < c.start;
    if (d != null) return true;
    if (c != null) return false;
    if (_creditHints.hasMatch(lower)) return false;
    if (_debitHints.hasMatch(lower)) return true;
    return null;
  }

  static final _amount = RegExp(
    r'(?:rs|inr|rupees?|₹)\.?\s*:?\s*([0-9][0-9,]*(?:\.[0-9]+)?)|([0-9][0-9,]*(?:\.[0-9]+)?)\s*(?:rs\.?|inr|rupees?|₹|/-)',
    caseSensitive: false,
  );
  static final _balanceLabel = RegExp(r'(?:bal(?:ance)?|limit|lmt)[^0-9]{0,12}$', caseSensitive: false);

  /// First amount not labelled as a balance or limit ("Avl Bal Rs 10,000").
  static double? extractTransactionAmount(String body) {
    for (final m in _amount.allMatches(body)) {
      final before = body.substring(m.start < 20 ? 0 : m.start - 20, m.start);
      if (_balanceLabel.hasMatch(before)) continue;
      final value = double.tryParse((m.group(1) ?? m.group(2) ?? '').replaceAll(',', ''));
      if (value != null && value > 0) return value;
    }
    return null;
  }

  static ParsedSms? parseSmsBody(String body, DateTime smsTime, {String sender = ''}) {
    final cleanBody = body.toLowerCase();

    // 1. Exclude explicit marketing / promotional spam (refined to avoid dropping real receipts)
    const promoSpamKeywords = [
      'pre-approved', 'preapproved', 'pre approved',
      'instant loan', 'apply now', 'apply for card', 'loan offer',
      'credit limit enhance', 'win up to', 'congratulations! you have won',
      'you have won', 'claim your reward', 'click to apply',
      'download the app to claim', 'buy now pay later', 'flat % off',
    ];
    if (promoSpamKeywords.any((k) => cleanBody.contains(k))) return null;
    if (isNonTransaction(cleanBody)) return null;

    // 2. Debit / Credit Direction Check
    final debit = detectDirection(cleanBody);
    if (debit == null) return null;

    // 3. Amount Extraction, skipping balances and limits
    final amount = extractTransactionAmount(body);
    if (amount == null) return null;

    // 4. Extract Merchant Name: try every "to/at/..." keyword, not just the first
    String merchant = 'Unknown Merchant';
    final merchantKeyword = RegExp(r'\b(?:to|at|towards|via|spent on|paid to)\s+', caseSensitive: false);
    final merchantTail = RegExp(
      r'([a-zA-Z0-9\s\.\-\*@]+?)(?:\s+on\b|\s+ref|\s+via\b|\s+from\b|\s+bal|\s+avl|\.|$)',
      caseSensitive: false,
    );
    final infoPattern = RegExp(
      r'\b(?:info:?|vpa:?|merchant:?)\s*([a-zA-Z0-9\s\.\-\*@]+?)(?:\s+on\b|\s+ref|\.|$)',
      caseSensitive: false,
    );
    final candidates = <String?>[
      for (final k in merchantKeyword.allMatches(body)) merchantTail.matchAsPrefix(body, k.end)?.group(1),
      for (final m in infoPattern.allMatches(body)) m.group(1),
    ];
    for (final raw in candidates) {
      final name = raw?.trim();
      if (name != null && name.isNotEmpty && name.length < 30) {
        merchant = _cleanMerchantName(name);
        break;
      }
    }

    // 5. Extract Bank & Account Snippet
    final bankName = detectBankName(sender, body);
    final accType = detectAccountType(body);
    String snippet = '';

    final snippetPatterns = [
      RegExp(r'(?:a/c|acct|account|card|ending(?:\s+in)?)\s*(?:no\.?|num\.?|number)?\s*[:\s]*\*?[x*]*([0-9]{3,4})', caseSensitive: false),
      RegExp(r'[x*]{2,}([0-9]{3,4})', caseSensitive: false),
      RegExp(r'(?:a/c|acct|account|card)\s*(?:no\.?|num\.?|number)?\s*[:\s]*([0-9]{3,4})', caseSensitive: false),
    ];

    for (final pat in snippetPatterns) {
      final match = pat.firstMatch(body);
      if (match != null) {
        final digits = match.group(1);
        if (digits != null && digits.isNotEmpty) {
          snippet = 'xx$digits';
          break;
        }
      }
    }

    final accountTitle = snippet.isNotEmpty
        ? '$bankName ($snippet)'
        : (bankName != 'Bank' ? bankName : 'Bank Account');

    return ParsedSms(
      amount: amount,
      merchant: merchant,
      account: accountTitle,
      bankName: bankName,
      accountSnippet: snippet,
      accountType: accType,
      isDebit: debit,
      date: smsTime,
      body: body,
    );
  }

  static String _cleanMerchantName(String name) {
    var cleaned = name.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.contains('@')) {
      cleaned = cleaned.split('@').first;
    }

    // Capitalize each word
    if (cleaned.isNotEmpty) {
      cleaned = cleaned.split(' ').map((word) {
        if (word.isEmpty) return '';
        return word[0].toUpperCase() + word.substring(1).toLowerCase();
      }).join(' ');
    }

    return cleaned.isNotEmpty ? cleaned : 'Unknown Merchant';
  }

  static bool _isLikelyTransactionalSender(String sender) {
    final upper = sender.toUpperCase().trim();
    if (upper.isEmpty) return true;

    // Long plain phone numbers are usually not bank DLT headers
    if (RegExp(r'^\+?\d{10,}$').hasMatch(upper)) return false;

    return true;
  }
}
