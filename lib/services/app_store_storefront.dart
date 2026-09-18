/// The reader's **App Store storefront**, which is the only correct answer to
/// "which Apple Books catalogue can this person actually buy from".
///
/// **Why the device locale was the wrong signal, and wrong in both directions.**
/// `storesForLocale` and `storeCountryFor` used to guess the storefront from the
/// device language, which produced two distinct defects:
///
///  * A Korean-language phone signed in to a **US** Apple ID had Apple Books hidden
///    from it, even though that account can buy from the US store perfectly well.
///  * An English-language phone signed in to a **KR** Apple ID was shown Apple Books
///    rows built against `/us/`, which that account cannot buy from at all \u2014
///    `books.apple.com/us/book/id731076045` resolves, `/kr/book/id731076045` is a
///    **404**, and `itunes.apple.com/lookup?id=731076045&country=kr` returns zero.
///    That one is a dead link rather than a missing row, so it is the worse half.
///
/// The storefront follows the **Apple ID's country**, not the device's language and
/// not its physical location, so only StoreKit can answer it. `SKPaymentQueue`
/// exposes it with no purchase, no product request and no entitlement.
///
/// **This is advisory, never required.** Everything here degrades to the old
/// locale-derived guess: Android has no equivalent for Play Books, the simulator and
/// `flutter test` have no storefront at all, and StoreKit legitimately reports `nil`
/// for a short window early in launch before it has resolved one. A null answer must
/// therefore cost nothing but precision.
library;

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:flutter/services.dart';

/// Application-level channel, registered in `AppDelegate.didInitializeImplicit\
/// FlutterEngine`. Named for the app rather than for a plugin because it is neither.
@visibleForTesting
const appStoreChannel = MethodChannel('bookworm/app_store');

/// The reader's storefront as a **lowercase ISO 3166-1 alpha-2** code (`us`, `kr`),
/// or null when it cannot be had.
///
/// Alpha-2 because that is what both consumers require, and the requirement is not
/// negotiable: `itunes.apple.com/search?country=USA` returns a non-JSON error where
/// `country=us` works. StoreKit hands back **alpha-3**, so [alpha2FromAlpha3] does
/// the conversion.
///
/// Never throws. A `MissingPluginException` (Android, or an iOS build predating the
/// channel), a `PlatformException`, a null storefront and an unrecognised code all
/// resolve to null.
Future<String?> appStoreStorefrontCountry({MethodChannel? channel}) async {
  try {
    final alpha3 = await (channel ?? appStoreChannel).invokeMethod<String>(
      'storefrontCountryCode',
    );
    // TEMPORARY -- device verification of the channel, remove once confirmed.
    // Nothing has yet observed this channel returning a real country: a simulator
    // with no Apple ID signed in returns nil, which exercises the fallback and
    // proves nothing. Inside an `assert` block so it costs a release build nothing.
    assert(() {
      debugPrint(
        '[storefront] channel returned ${alpha3 ?? "<null>"} '
        '-> ${alpha3 == null ? "<null>" : alpha2FromAlpha3(alpha3) ?? "<unmapped>"}',
      );
      return true;
    }());
    if (alpha3 == null) return null;
    return alpha2FromAlpha3(alpha3);
  } catch (error) {
    // TEMPORARY, as above. The swallow is deliberate and permanent; naming what was
    // swallowed is not, and matters here because `MissingPluginException` would mean
    // the channel never registered while a `PlatformException` would mean it did.
    assert(() {
      debugPrint('[storefront] channel failed: ${error.runtimeType} $error');
      return true;
    }());
    // Includes MissingPluginException, which is the *ordinary* case on Android.
    return null;
  }
}

/// Converts StoreKit's alpha-3 country code to the lowercase alpha-2 form Apple's
/// own URLs and search API use. Null for anything unrecognised.
///
/// Returning null rather than a guess is deliberate: the caller falls back to the
/// locale-derived country, which is exactly the previous behaviour, whereas a
/// mangled code would build a URL for a storefront that does not exist.
String? alpha2FromAlpha3(String alpha3) {
  if (alpha3.length != 3) return null;
  final wanted = alpha3.toUpperCase();
  final at = _table.indexOf(wanted);
  // Must land on a token boundary: every entry is exactly five characters
  // (`USAus`) separated by single spaces, so a match at any other offset would be
  // a coincidental hit spanning two entries.
  if (at < 0 || at % 6 != 0) return null;
  return _table.substring(at + 3, at + 5);
}

/// Every ISO 3166-1 alpha-3 code paired with its alpha-2, as `AAAaa` tokens.
///
/// **A string rather than a `Map` literal on purpose.** 249 map entries is 249 lines
/// of noise around three lines of logic; this is the same data in twenty-one, still
/// greppable (searching `KOR` finds `KORkr`), and `const`. The full ISO list is kept
/// rather than trimmed to the storefronts Apple happens to operate today, because a
/// trimmed list is one that silently rots when Apple adds a country.
const _table =
    'ABWaw AFGaf AGOao AIAai ALAax ALBal ANDad AREae ARGar ARMam ASMas ATAaq '
    'ATFtf ATGag AUSau AUTat AZEaz BDIbi BELbe BENbj BESbq BFAbf BGDbd BGRbg '
    'BHRbh BHSbs BIHba BLMbl BLRby BLZbz BMUbm BOLbo BRAbr BRBbb BRNbn BTNbt '
    'BVTbv BWAbw CAFcf CANca CCKcc CHEch CHLcl CHNcn CIVci CMRcm CODcd COGcg '
    'COKck COLco COMkm CPVcv CRIcr CUBcu CUWcw CXRcx CYMky CYPcy CZEcz DEUde '
    'DJIdj DMAdm DNKdk DOMdo DZAdz ECUec EGYeg ERIer ESHeh ESPes ESTee ETHet '
    'FINfi FJIfj FLKfk FRAfr FROfo FSMfm GABga GBRgb GEOge GGYgg GHAgh GIBgi '
    'GINgn GLPgp GMBgm GNBgw GNQgq GRCgr GRDgd GRLgl GTMgt GUFgf GUMgu GUYgy '
    'HKGhk HMDhm HNDhn HRVhr HTIht HUNhu IDNid IMNim INDin IOTio IRLie IRNir '
    'IRQiq ISLis ISRil ITAit JAMjm JEYje JORjo JPNjp KAZkz KENke KGZkg KHMkh '
    'KIRki KNAkn KORkr KWTkw LAOla LBNlb LBRlr LBYly LCAlc LIEli LKAlk LSOls '
    'LTUlt LUXlu LVAlv MACmo MAFmf MARma MCOmc MDAmd MDGmg MDVmv MEXmx MHLmh '
    'MKDmk MLIml MLTmt MMRmm MNEme MNGmn MNPmp MOZmz MRTmr MSRms MTQmq MUSmu '
    'MWImw MYSmy MYTyt NAMna NCLnc NERne NFKnf NGAng NICni NIUnu NLDnl NORno '
    'NPLnp NRUnr NZLnz OMNom PAKpk PANpa PCNpn PERpe PHLph PLWpw PNGpg POLpl '
    'PRIpr PRKkp PRTpt PRYpy PSEps PYFpf QATqa REUre ROUro RUSru RWArw SAUsa '
    'SDNsd SENsn SGPsg SGSgs SHNsh SJMsj SLBsb SLEsl SLVsv SMRsm SOMso SPMpm '
    'SRBrs SSDss STPst SURsr SVKsk SVNsi SWEse SWZsz SXMsx SYCsc SYRsy TCAtc '
    'TCDtd TGOtg THAth TJKtj TKLtk TKMtm TLStl TONto TTOtt TUNtn TURtr TUVtv '
    'TWNtw TZAtz UGAug UKRua UMIum URYuy USAus UZBuz VATva VCTvc VENve VGBvg '
    'VIRvi VNMvn VUTvu WLFwf WSMws YEMye ZAFza ZMBzm ZWEzw ';
