import 'package:flutter_test/flutter_test.dart';
import 'package:fiscora/core/services/account_balances.dart';
import 'package:fiscora/core/sync/collections/account_collection.dart';

AccountCollection account(String clientId, String type) => AccountCollection()
  ..clientId = clientId
  ..serverId = 'srv-$clientId'
  ..type = type;

void main() {
  final bank = account('bank', 'bank_account');
  final card = account('card', 'credit_card');

  test('a debit lowers a bank balance and raises the amount owed on a card', () {
    expect(AccountBalances.effectOn(bank, amount: 100, accountId: 'bank', transferAccountId: ''), -100);
    expect(AccountBalances.effectOn(card, amount: 100, accountId: 'card', transferAccountId: ''), 100);
  });

  test('a credit raises a bank balance', () {
    expect(AccountBalances.effectOn(bank, amount: -500, accountId: 'bank', transferAccountId: ''), 500);
  });

  test('paying the card bill from the bank lowers both balances, and is not spend', () {
    expect(AccountBalances.effectOn(bank, amount: 2000, accountId: 'bank', transferAccountId: 'card'), -2000);
    expect(AccountBalances.effectOn(card, amount: 2000, accountId: 'bank', transferAccountId: 'card'), -2000);
  });

  test('transactions recorded with the server id still count', () {
    expect(AccountBalances.effectOn(bank, amount: 50, accountId: 'srv-bank', transferAccountId: ''), -50);
  });
}
