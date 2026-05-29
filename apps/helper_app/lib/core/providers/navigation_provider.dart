import 'package:flutter_riverpod/flutter_riverpod.dart';

class ActiveTabNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void set(int value) => state = value;
}

final activeTabProvider = NotifierProvider<ActiveTabNotifier, int>(
  ActiveTabNotifier.new,
);
