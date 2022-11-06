import 'package:altair/domain/entity/account/wallet_account.entity.dart';
import 'package:altair/domain/entity/campaign/greeting_word.entity.dart';
import 'package:altair/interface_adapter/repository/greeting.repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retry/retry.dart';
import 'package:web3dart/json_rpc.dart';

import '../domain/entity/exception/user_activity_exception.entity.dart';
import '../logger.dart';
import 'ethereum_connector.vm.dart';

final greetingWordsProviders =
    FutureProvider.family<List<GreetingWord>, String>((ref, campaignId) async {
  final repo = ref.watch(greetingRepositoryProvider);
  final words = await repo.getGreetingWords(campaignId);
  return words;
});

final selectedGreetingWordStateNotifierProvider = StateNotifierProvider.family<
    SelectedGreetingWordStateNotifier, AsyncValue<GreetingWord>, String>(
  (ref, campaignId) {
    final repo = ref.watch(greetingRepositoryProvider);
    final sender = ref.watch(myWalletAccountProvider);

    return SelectedGreetingWordStateNotifier(
      repo: repo,
      campaignId: campaignId,
      sender: sender,
    )..init();
  },
);

class SelectedGreetingWordStateNotifier
    extends StateNotifier<AsyncValue<GreetingWord>> {
  SelectedGreetingWordStateNotifier({
    required this.repo,
    required this.campaignId,
    this.sender,
  }) : super(const AsyncValue.loading());

  final String campaignId;
  final GreetingRepository repo;
  final WalletAccount? sender;
  bool isWaitingForTransactionConfirmation = false;

  Future<void> init() async {
    if (sender == null) {
      logger.warning('sender is null. this should not happen.');
      return;
    }

    state = await AsyncValue.guard(() async {
      return _fetchSelectedGreetingWord();
    });
  }

  Future<void> select(GreetingWord word) async {
    isWaitingForTransactionConfirmation = true;
    await repo.setGreetingWordForWallet(campaignId, word.index);

    // wait for transaction to be confirmed.
    await Future<void>.delayed(const Duration(seconds: 10));

    final confirmedWord = await retry(
      () async {
        return _fetchSelectedGreetingWord();
      },
      retryIf: (e) => e is NeedToSelectGreetingWord || e is RPCError,
      delayFactor: const Duration(seconds: 1),
      onRetry: (_) => logger.info('🌀 retrying to confirm selected greeting word.'),
    );
    logger.info('🎉 confirmed selected greeting word: $confirmedWord');
    state = AsyncValue.data(confirmedWord);
    isWaitingForTransactionConfirmation = false;
  }

  Future<GreetingWord> _fetchSelectedGreetingWord() async {
    final word = await repo.getSelectedGreetingWord(campaignId, sender!.id);
    if (word == null) {
      throw NeedToSelectGreetingWord();
    }
    return word;
  }
}
