// Unit tests for the barcode → ISBN rules.
//
// This is the whole reason `lib/services/isbn.dart` is a separate file: the rest
// of the scan path needs a camera, and neither the iOS Simulator nor `flutter
// test` has one. These rules are arithmetic, so they can be pinned properly.

import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/services/isbn.dart';

void main() {
  // Real, check-digit-valid fixtures. Worked out by hand rather than generated,
  // because a generator that shared the implementation's arithmetic would agree
  // with a wrong implementation.
  const hanKang = '9788954699914'; // 978, Korean publisher
  const classic = '9780306406157'; // 978, the canonical ISBN-13 example
  const newRange = '9791000000008'; // 979
  const groceries = '4006381333931'; // valid EAN-13, not a book

  group('isValidEan13', () {
    test('accepts correct check digits', () {
      expect(isValidEan13(hanKang), isTrue);
      expect(isValidEan13(classic), isTrue);
      expect(isValidEan13(newRange), isTrue);
      expect(isValidEan13(groceries), isTrue);
    });

    test('rejects a wrong check digit', () {
      // Same book, last digit bumped by one. This is the case the check exists
      // for: thirteen plausible digits out of a partly occluded symbol.
      expect(isValidEan13('9788954699915'), isFalse);
    });

    test('rejects a transposition', () {
      // Weights alternate 1,3 so swapping adjacent digits shifts the sum by
      // twice their difference — caught unless the digits differ by 5.
      expect(isValidEan13('9788954699194'), isFalse);
    });

    test('rejects anything that is not thirteen digits', () {
      expect(isValidEan13(''), isFalse);
      expect(isValidEan13('978895469991'), isFalse); // 12
      expect(isValidEan13('97889546999140'), isFalse); // 14
    });

    test('rejects non-digits rather than coercing them', () {
      expect(isValidEan13('97889546999X4'), isFalse);
      expect(isValidEan13('978-89-546-99914'), isFalse);
    });
  });

  group('isbnFromBarcode', () {
    test('passes through a Bookland ISBN', () {
      expect(isbnFromBarcode(hanKang), hanKang);
      expect(isbnFromBarcode(newRange), newRange);
    });

    test('tolerates the separators a printed line carries', () {
      expect(isbnFromBarcode('978-89-546-9991-4'), hanKang);
      expect(isbnFromBarcode('978 89 546 9991 4'), hanKang);
    });

    test('rejects a valid EAN-13 that is not a book', () {
      // The reason the prefix filter exists at all: point the camera at a shelf
      // and a cereal box decodes just as cleanly as a paperback.
      expect(isValidEan13(groceries), isTrue);
      expect(isbnFromBarcode(groceries), isNull);
    });

    test('rejects the Korean add-on printed beside the ISBN', () {
      // 부가기호 — five digits, so it never reaches the prefix check. This is the
      // case that makes the ordinary two-symbol Korean frame resolve for free.
      expect(isbnFromBarcode('03810'), isNull);
    });

    test('rejects null, so a rawValue-less barcode needs no special case', () {
      expect(isbnFromBarcode(null), isNull);
    });
  });

  group('chooseIsbn', () {
    test('returns null when nothing in frame is a book', () {
      expect(chooseIsbn([groceries, '03810', null]), isNull);
      expect(chooseIsbn([]), isNull);
    });

    test('picks the ISBN out of a mixed frame', () {
      // The ordinary Korean book: ISBN plus add-on, in whatever order the
      // platform reports them.
      expect(chooseIsbn(['03810', hanKang]), hanKang);
      expect(chooseIsbn([hanKang, '03810']), hanKang);
    });

    test('de-duplicates the same symbol seen twice', () {
      expect(chooseIsbn([hanKang, hanKang]), hanKang);
    });

    test('takes the first valid candidate with no geometry to go on', () {
      expect(chooseIsbn([classic, hanKang]), classic);
    });

    test('breaks a two-book tie by nearest to centre', () {
      // The one case the prefix + check-digit filter cannot settle: two separate
      // books in shot. A user aims at the one they mean.
      expect(
        chooseIsbn(
          [classic, hanKang],
          distancesFromCentre: {classic: 180, hanKang: 20},
        ),
        hanKang,
      );
      expect(
        chooseIsbn(
          [classic, hanKang],
          distancesFromCentre: {classic: 20, hanKang: 180},
        ),
        classic,
      );
    });

    test('never lets an unmeasured candidate win the tie-break', () {
      // A candidate the platform gave no corners for sorts last rather than
      // winning by accident on a null compare.
      expect(
        chooseIsbn([classic, hanKang], distancesFromCentre: {hanKang: 400}),
        hanKang,
      );
    });

    test('ignores geometry when only one candidate is a book', () {
      expect(
        chooseIsbn(['03810', hanKang], distancesFromCentre: {hanKang: 999}),
        hanKang,
      );
    });
  });

  group('formatIsbnForDisplay', () {
    test('groups the standard ISBN-13 shape', () {
      expect(formatIsbnForDisplay(hanKang), '978 89 546 9991 4');
    });

    test('returns anything unexpected untouched rather than throwing', () {
      // Only ever fed a locked ISBN, but it is on the failure-card path too and a
      // range error there would replace a useful message with a crash.
      expect(formatIsbnForDisplay(''), '');
      expect(formatIsbnForDisplay('123'), '123');
    });
  });

  test('Bookland prefixes are exactly 978 and 979', () {
    expect(kBooklandPrefixes, {'978', '979'});
  });
}
