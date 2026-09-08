// Who gets offered `InviteCodePage`, and who must not be.
//
// **The screen was registered in `AppRoutes.routes` and pushed from nowhere.** That made
// the deferred tier a dead end: the landing page copies the token to the clipboard
// inside the tap that leaves for the App Store, and
// `InviteCodePage._prefillFromClipboard` is the only thing that reads it back. A copy
// with no landing screen goes nowhere.
//
// The rules pinned here are all about *restraint*, because the failure modes are
// asymmetric. Not showing it costs one reader a paste. Showing it too often ambushes
// every existing user with a signup step, or asks someone who just tapped a link for a
// code they have already spent.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bookworm_friends/providers/invite_code_prompt_provider.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('offering the code screen', () {
    test(
      'Given a fresh install, When the chance is taken, Then it is offered exactly '
      'once',
      () async {
        const prompt = InviteCodePrompt();

        expect(await prompt.takeChance(), isTrue);
        // The second call is the guard against two sign-in paths both pushing it.
        expect(await prompt.takeChance(), isFalse);
      },
    );

    test(
      'Given the screen was already offered, When the app relaunches, Then it is not '
      'offered again',
      () async {
        // "Once" has to survive a relaunch. Continuing past the screen with an empty
        // field *is* the skip, so re-offering it would turn a decline into nagging.
        SharedPreferences.setMockInitialValues({
          kInviteCodePromptPrefKey: true,
        });
        const prompt = InviteCodePrompt();

        expect(await prompt.wasShown, isTrue);
        expect(await prompt.takeChance(), isFalse);
      },
    );

    test(
      'Given the chance is taken, When it is persisted, Then the flag is written '
      'rather than held in memory',
      () async {
        await const InviteCodePrompt().takeChance();

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getBool(kInviteCodePromptPrefKey), isTrue);
      },
    );

    test(
      'Given a reader who arrived by tapping a link, When their consent is shown, '
      'Then the chance is consumed so they are never asked for a code as well',
      () async {
        // The link path calls `takeChance()` purely to burn it -- the reader has just
        // used a token, and following consent with "have you got a code?" asks for
        // something they have already spent.
        const prompt = InviteCodePrompt();
        await prompt.takeChance();

        expect(await prompt.wasShown, isTrue);
      },
    );
  });
}
