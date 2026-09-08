// Guards for the spine's title: the type token it is set in, and the rule that
// decides where a catalogue title stops being the title.
//
// `spineTitleOf` is a small function with a large effect. Across the corpus in
// `docs/mockups/spine-type/` it accounted for **half of all truncation on a
// spine, and none of that half was about measure** — a Korean catalogue supplies
// the original title in parentheses and the subtitle after a colon as a matter of
// course, so `그로스 해킹(Growth Hacking)` overflowed where `그로스 해킹` fits whole
// with room left. The cases below are the ones that make it either a rule or a
// blunt instrument.

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/ui/widgets/book_vertical.dart';

void main() {
  group('spineTitleOf', () {
    test('Given a parenthetical original title, Then it is dropped', () {
      // The case this exists for, and the one visible in the screenshot that
      // started the work.
      expect(spineTitleOf('그로스 해킹(Growth Hacking)'), '그로스 해킹');
      expect(
        spineTitleOf('역행자(10만부 기념 페이크 에디션)'),
        '역행자',
        reason: 'a real title from migration_data/book.jsonl',
      );
    });

    test('Given a subtitle after a colon, Then it is dropped', () {
      expect(spineTitleOf('미움받을 용기: 아들러의 가르침'), '미움받을 용기');
      expect(spineTitleOf('Sapiens: A Brief History'), 'Sapiens');
    });

    test('Given a full-width bracket or colon, Then it is also cut', () {
      // A Korean IME produces these as readily as the ASCII forms, and a title
      // imported from a catalogue can carry either.
      expect(spineTitleOf('데미안（Demian）'), '데미안');
      expect(spineTitleOf('데미안：영혼의 성장'), '데미안');
    });

    test('Given no mark, Then the title is unchanged', () {
      for (final title in const [
        '세이노의 가르침',
        'Shoe Dog',
        '인공지능, 머신러닝, 딥러닝 입문',
        '세계를 바꾼 테크놀로지 10',
      ]) {
        expect(spineTitleOf(title), title);
      }
    });

    test('Given a mark at the very start, Then the title survives whole', () {
      // **The case that keeps this a rule rather than a blunt instrument.** A
      // title that opens with a bracket has nothing before it, and cutting there
      // would leave an empty spine — so whatever is inside is all the title
      // there is. `indexOf > 0` is what enforces it, not a special case.
      expect(spineTitleOf('(주)좋은생각'), '(주)좋은생각');
      expect(spineTitleOf('[개정판]'), '[개정판]');
      expect(spineTitleOf(':'), ':');
    });

    test('Given only a mark and spaces before it, Then the title survives', () {
      // `trimRight` can empty a string that `indexOf` thought had content.
      expect(spineTitleOf(' (Demian)'), ' (Demian)');
    });

    test('Given several marks, Then the earliest one wins', () {
      expect(spineTitleOf('제목: 부제(원제)'), '제목');
      expect(spineTitleOf('제목(원제): 부제'), '제목');
    });

    test('Given a hyphen inside a word, Then it is not a subtitle mark', () {
      // ` - ` is spaced on purpose. An unspaced hyphen is part of the word, and
      // cutting at it would turn `e-book` into `e`.
      expect(spineTitleOf('e-book 만들기'), 'e-book 만들기');
      expect(spineTitleOf('제목 - 부제'), '제목');
    });

    test('Given an empty title, Then it is returned unchanged', () {
      expect(spineTitleOf(''), '');
    });

    test('Given the same title twice, Then the answer is identical', () {
      // Stability, for the same reason `spineToneFor` is pinned: a spine's title
      // is a book's identity in the pile.
      const title = '이더리움과 솔리디티 입문(Mastering Ethereum)';
      expect(spineTitleOf(title), spineTitleOf(title));
    });
  });

  group('AppTextStyles.spine', () {
    test('Given the spine token, Then it is the serif with a sans fallback', () {
      // The point of the whole change: a book title is set in the app's literary
      // face rather than in the one its tab bar uses. The fallback matters more here
      // than on the app's own strings — the face is cut to KS X 1001's 2,350
      // syllables and a title is catalogue text, so this is the backstop for a
      // syllable outside that set, and for hanja, which it lacks entirely.
      expect(AppTextStyles.spine.fontFamily, AppFonts.serif);
      expect(
        AppTextStyles.spine.fontFamilyFallback,
        contains(AppFonts.sans),
        reason: 'a title can contain hanja, which the serif does not carry',
      );
    });

    test('Given the spine token, Then it does not ask for tabular figures', () {
      // It used to, by borrowing `label`. Tabular figures are right for a count
      // and wrong for a title: `세계를 바꾼 테크놀로지 10` paid monospaced digit
      // advances out of a measure with none to spare.
      expect(
        AppTextStyles.spine.fontFeatures ?? const <FontFeature>[],
        isNot(contains(const FontFeature.tabularFigures())),
      );
    });

    test('Given the spine token, Then it is not label', () {
      // A regression guard with a name: the spine borrowed `label` — "tab labels,
      // shelf tabs, badges, capsules, buttons" — so a book title was the same
      // family and weight as the tab bar 40pt below it.
      expect(
        AppTextStyles.spine.fontFamily,
        isNot(AppTextStyles.label.fontFamily),
      );
    });

    test('Given two lines of spine type, Then they fit the thickness that '
        'allows them', () {
      // `BookVertical` sets two lines from `kSpineTwoLineMinThickness`, and the
      // token's `height` is what decides whether they fit across the spine. If
      // either is retuned without the other, the second line is clipped.
      final twoLines =
          2 * AppTextStyles.spine.fontSize! * AppTextStyles.spine.height!;
      expect(
        twoLines,
        lessThan(kSpineTwoLineMinThickness),
        reason:
            'two lines measure ${twoLines.toStringAsFixed(1)}pt, which does not '
            'fit the ${kSpineTwoLineMinThickness}pt spine that is allowed them',
      );
    });
  });

  group('the spine measure', () {
    test('Given the head and tail padding, Then it costs far less than the 30pt '
        'it replaced', () {
      // The change is worth about one Hangul syllable on every spine in the pile,
      // and it is the cheapest of the lot. Asserted so a future retune has to
      // notice that it is spending measure.
      expect(kSpinePadHead + kSpinePadTail, lessThan(20));
      expect(
        kSpinePadHead,
        greaterThanOrEqualTo(5),
        reason: 'the arched head in bookSpinePath is 5pt deep',
      );
    });
  });
}
