import 'package:flutter_riverpod/flutter_riverpod.dart';

/// "Hide amounts" privacy mode for using the app in public or sharing the
/// screen. Toggled from Home; lasts until the app is closed.
final hideAmountsProvider = StateProvider<bool>((ref) => false);

/// [formatted] (e.g. "₹12,000"), or a mask while amounts are hidden.
String maskAmount(bool hidden, String formatted) => hidden ? '₹ ••••' : formatted;
