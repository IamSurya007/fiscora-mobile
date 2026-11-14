import 'package:flutter_test/flutter_test.dart';
import 'package:fiscora/core/services/sms_parser_service.dart';

ParsedSms? parse(String body) =>
    SmsParserService.parseSmsBody(body, DateTime(2026, 11, 14), sender: 'VM-HDFCBK');

void main() {
  group('non-transactions are ignored', () {
    test('OTP mentioning an amount', () {
      expect(parse('123456 is your OTP for txn of Rs 2,500 at AMAZON. Do not share.'), isNull);
    });
    test('declined transaction', () {
      expect(parse('Txn of Rs 500 at SWIGGY on card XX1234 declined due to insufficient funds.'), isNull);
    });
    test('future mandate debit', () {
      expect(parse('Rs 499 will be debited on 15-Nov from A/c XX1234 for NETFLIX mandate.'), isNull);
    });
  });

  group('direction', () {
    test('credit that also says "sent by" is a credit', () {
      final p = parse('Rs 5000 credited to A/c XX1234 on 14-Nov, sent by JOHN. Avl Bal Rs 20,000');
      expect(p?.isDebit, isFalse);
    });
    test('refund for an earlier payment is a credit', () {
      final p = parse('Refund of Rs 500 for your payment of Rs 500 at MYNTRA has been credited to A/c XX1234');
      expect(p?.isDebit, isFalse);
    });
    test('credit card bill payment received is a credit', () {
      final p = parse('Payment of Rs 10,000 received towards your credit card XX1234. Thank you.');
      expect(p?.isDebit, isFalse);
      expect(p?.amount, 10000);
    });
    test('"prepaid" does not count as "paid"', () {
      expect(SmsParserService.detectDirection('your prepaid recharge plan is active'), isNull);
    });
    test('plain debit', () {
      expect(parse('Rs.250 debited from A/c XX1234 to SWIGGY on 14-Nov. Ref 12345')?.isDebit, isTrue);
    });
  });

  group('amount', () {
    test('balance stated first is skipped', () {
      final p = parse('Avl Bal Rs 10,000.00. Rs 500 debited from A/c XX1234 at ZOMATO');
      expect(p?.amount, 500);
    });
    test('"Rs:" format and trailing balance', () {
      final p = parse('A/c XX1234 debited for Rs:500 on 14-Nov. Avl Bal Rs.12,345');
      expect(p?.amount, 500);
    });
    test('lakh format', () {
      expect(SmsParserService.extractTransactionAmount('Rs.1,23,456.78 debited'), 123456.78);
    });
  });

  test('merchant after a long "spent on your card" phrase', () {
    final p = parse('Rs.250 spent on your SBI Credit Card ending 1234 at SWIGGY on 12Nov');
    expect(p?.merchant.toLowerCase(), contains('swiggy'));
  });
}
