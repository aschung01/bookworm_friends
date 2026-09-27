import SwiftUI
import WidgetKit

// The app's tokens, by hand, because an extension cannot import `app_theme.dart`.
//
// Guarded by `test/streak_widget_palette_test.dart`, which reads the hexes back out of this
// file and asserts they still equal the Dart constants. That test is the only thing standing
// between this and the drift that a second copy of a palette always produces.
//
// **Most of these are no longer what the tiles draw with, and the ladder is why.** Every
// unrecorded tile now sits on a coloured ground that supplies its own ink, dim and divider by
// the hour (`StreakGround`), so a fixed theme neutral on top of it would be a coin flip per
// hour rather than per theme. They are kept, not deleted, for the reason `AppColors.flame` is
// kept in Dart with no reader left: this is the record of what the theme-correct answer was,
// and it is where anything that ever needs a neutral again should start.
private enum Palette {
  /// `kCandleFlame` #F2A93F — one value in both themes, on purpose. See `card_lighting.dart`.
  /// Still drawn: the recorded tile's lit flame and its sticker outline.
  static let flame = Color(hex: 0xF2A93F)
  static let surface = Color(light: 0xFFFFFF, dark: 0x1E1E1E)
  static let primaryText = Color(light: 0x212529, dark: 0xF1F3F5)
  static let secondaryText = Color(light: 0x626A72, dark: 0x949599)
  static let divider = Color(light: 0xE9ECEF, dark: 0x3A3A3C)
}

extension Color {
  init(hex: UInt32) {
    self.init(
      .sRGB,
      red: Double((hex >> 16) & 0xFF) / 255,
      green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255,
      opacity: 1
    )
  }

  /// A dynamic colour, so the widget follows the system appearance the way the app does.
  init(light: UInt32, dark: UInt32) {
    self.init(
      UIColor { traits in
        let value = traits.userInterfaceStyle == .dark ? dark : light
        return UIColor(
          red: CGFloat((value >> 16) & 0xFF) / 255,
          green: CGFloat((value >> 8) & 0xFF) / 255,
          blue: CGFloat(value & 0xFF) / 255,
          alpha: 1
        )
      }
    )
  }

  /// A jacket colour out of the snapshot, or nil for a book that has none on record.
  init?(coverHex: String?) {
    guard var raw = coverHex else { return nil }
    if raw.hasPrefix("#") { raw.removeFirst() }
    guard raw.count == 6, let value = UInt32(raw, radix: 16) else { return nil }
    self.init(hex: value)
  }
}

// MARK: - The ground

/// An 8-bit sRGB triple, which is the unit the mockup's recipe is written in.
///
/// **Every mix rounds back to whole channels, and that is deliberate.** `groundVars()` in
/// `docs/mockups/streak-widget/index.html` round-trips through hex at every step, so keeping the
/// rounding keeps this port's output equal to the hexes the sheet recorded — and those hexes are
/// what the contrast figures in the design record were measured on. Mixing in floating point
/// would be imperceptibly smoother and would quietly make the record unverifiable.
struct StreakRGB {
  let r: Double
  let g: Double
  let b: Double

  init(_ hex: UInt32) {
    r = Double((hex >> 16) & 0xFF)
    g = Double((hex >> 8) & 0xFF)
    b = Double(hex & 0xFF)
  }

  private init(r: Double, g: Double, b: Double) {
    func channel(_ v: Double) -> Double { min(255, max(0, v.rounded())) }
    self.r = channel(r)
    self.g = channel(g)
    self.b = channel(b)
  }

  var color: Color {
    Color(.sRGB, red: r / 255, green: g / 255, blue: b / 255, opacity: 1)
  }

  func opacity(_ alpha: Double) -> Color {
    Color(.sRGB, red: r / 255, green: g / 255, blue: b / 255, opacity: alpha)
  }

  /// Linear interpolation in sRGB, `t` of the way from self toward [other].
  ///
  /// Not perceptual, and left that way on purpose: the mockup's note records that smoothing the
  /// crossings in a perceptual space would hide the actual cost of walking the hue wheel across
  /// a day. The anchors here are close enough in hue for it not to matter.
  func mixed(toward other: StreakRGB, _ t: Double) -> StreakRGB {
    StreakRGB(
      r: r + (other.r - r) * t,
      g: g + (other.g - g) * t,
      b: b + (other.b - b) * t
    )
  }

  /// WCAG relative luminance, so the ink on a ground is chosen by measurement rather than by a
  /// hand-kept per-hour flag.
  var luminance: Double {
    func f(_ raw: Double) -> Double {
      let v = raw / 255
      return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b)
  }

  /// WCAG contrast ratio against [other].
  func contrast(_ other: StreakRGB) -> Double {
    let a = luminance
    let b = other.luminance
    let hi = max(a, b)
    let lo = min(a, b)
    return (hi + 0.05) / (lo + 0.05)
  }
}

/// The hour ladder the unrecorded ground walks, as `(hour, top, bottom)`.
///
/// Slate blue, indigo, violet, plum, deep rose, deep red. **Every hour is dark, and that is the
/// one measured decision in the whole ramp.** The first version was a saturated purple-to-red arc
/// at mid lightness, drawn so a *green* cat could sit opposite it; against the grey cat that
/// shipped, the four fur candidates scored 2.0–3.9:1, because saturated magenta and pink occupy
/// the same value band a grey cat does. Being colourful was never the problem — being colourful at
/// the cat's own lightness was. Dark at every hour, the same four furs score 5.9–8.3:1.
///
/// **The hues are invented and off-palette, which is the feature's one un-traded cost.** The app's
/// surface is cream and these are jewel tones; nothing in `card_lighting.dart` contains them. Two
/// alternatives that stay inside the codebase — `dusk` (darker, more restrained) and `ember`
/// (warming into the candle darks instead of into red) — were built and both pass their contrast
/// checks, so swapping is one edit to this array.
enum StreakGroundRamp {
  static let anchors: [(hour: Double, top: StreakRGB, bottom: StreakRGB)] = [
    (7, StreakRGB(0x55688A), StreakRGB(0x3A4760)),
    (11, StreakRGB(0x525DA0), StreakRGB(0x363E6E)),
    (14, StreakRGB(0x6A4FA0), StreakRGB(0x46356E)),
    (18, StreakRGB(0x83438A), StreakRGB(0x572C5C)),
    (21, StreakRGB(0x9C3459), StreakRGB(0x68203A)),
    (23, StreakRGB(0xA02128), StreakRGB(0x5E0F14)),
  ]

  /// The ramp read at one hour. Outside the first and last anchor it clamps to them, so the
  /// small hours after the rollover hold the dawn slate rather than wrapping back through red.
  static func sample(atHour hour: Double) -> (top: StreakRGB, bottom: StreakRGB) {
    guard let first = anchors.first, let last = anchors.last else {
      return (StreakRGB(0x000000), StreakRGB(0x000000))
    }
    if hour <= first.hour { return (first.top, first.bottom) }
    if hour >= last.hour { return (last.top, last.bottom) }
    for i in 0..<(anchors.count - 1) {
      let lo = anchors[i]
      let hi = anchors[i + 1]
      guard hour >= lo.hour, hour <= hi.hour else { continue }
      let t = hi.hour == lo.hour ? 0 : (hour - lo.hour) / (hi.hour - lo.hour)
      return (lo.top.mixed(toward: hi.top, t), lo.bottom.mixed(toward: hi.bottom, t))
    }
    return (last.top, last.bottom)
  }
}

/// One tile's ground: the two ends of its gradient, the three mesh blobs derived from them, and
/// the ink the copy on top of it is drawn in.
///
/// A faithful port of `groundVars()`. Read that function's comments alongside this one — the
/// choices here are algorithmic on purpose, and a hardcoded ink or a fixed fade is exactly what
/// each of them replaced.
struct StreakGround {
  /// The gradient's top end. Also **what a knocked-out flame core shows through to**, which is
  /// why it is the top end and not `mid`: the flame sits at the top of the tile.
  let top: StreakRGB
  let bottom: StreakRGB
  let mid: StreakRGB
  let ink: StreakRGB
  /// What the line is drawn in — held above 3.2:1 against `mid` rather than a fixed fade.
  let dim: StreakRGB
  /// Hairlines and the progress track.
  let div: StreakRGB
  let lift: StreakRGB
  let accent: StreakRGB
  let deep: StreakRGB
  /// Recorded keeps a single bottom-up radial instead of the mesh. See `recorded`.
  let isRecorded: Bool

  private static let inkLight = StreakRGB(0xFFF7EA)  // paper under a flame
  private static let inkDark = StreakRGB(0x212529)  // AppColors.primaryText, light theme

  init(top: StreakRGB, bottom: StreakRGB, accent: StreakRGB? = nil, recorded: Bool = false) {
    self.top = top
    self.bottom = bottom
    self.isRecorded = recorded

    let mid = top.mixed(toward: bottom, 0.5)
    self.mid = mid

    // Whichever of the two inks actually wins, **compared rather than thresholded**. A fixed
    // cutoff of 0.179 luminance was wrong and the mockup's verifier caught it: 0.179 is where
    // *pure white and pure black* contrast equally, and neither ink is pure — #FFF7EA against
    // #212529 crosses over at about 0.205 instead. The 0.026 between those was one real hour on
    // one real ramp getting the worse of the two inks. Comparing has no such gap to be wrong in.
    let ink =
      StreakGround.inkLight.contrast(mid) >= StreakGround.inkDark.contrast(mid)
      ? StreakGround.inkLight
      : StreakGround.inkDark
    self.ink = ink

    // `dim` is what the line is drawn in — which is *the copy being read*, so it cannot be a
    // fixed fade. At a flat 0.42 toward the ground, the mid-grey hours rendered the line at
    // about 3.1:1, and a voice read at 3.1:1 is judged on its legibility instead of its words.
    // Back the fade off in steps until it clears 3.2:1; at the light and dark ends that leaves
    // it at the full 0.42 and only pulls it in through the middle. Keep the loop.
    var dim = ink.mixed(toward: mid, 0.42)
    var factor = 0.42
    while factor > 0, dim.contrast(mid) < 3.2 {
      factor -= 0.06
      dim = ink.mixed(toward: mid, max(0, factor))
    }
    self.dim = dim

    self.div = mid.mixed(toward: ink, 0.16)
    self.lift = top.mixed(toward: StreakRGB(0xFFFFFF), 0.2)
    self.deep = bottom.mixed(toward: StreakRGB(0x000000), 0.18)
    self.accent = accent ?? top
  }

  /// The ground at an hour of the reading day.
  ///
  /// **The accent is the ramp read three hours LATER**, which is where the mesh's third colour
  /// comes from. An anchor pair cannot supply one: measured across the ramp the hue delta between
  /// an hour's two stops is 0–13°, because the pair encodes lightness rather than hue. Reading
  /// ahead means the upper right of the tile carries the colour the day is heading toward — 18:00
  /// has the first blush of the red that arrives at 21:00 — so the mesh is never arbitrary, it is
  /// the ramp's own future.
  static func ramp(atHour hour: Double) -> StreakGround {
    let stops = StreakGroundRamp.sample(atHour: hour)
    return StreakGround(
      top: stops.top,
      bottom: stops.bottom,
      accent: StreakGroundRamp.sample(atHour: hour + 3).top
    )
  }

  /// The first anchor, held at every hour.
  ///
  /// **The states that use this never escalate, and this is the sharpest rule in the design.**
  /// The escalation is a function of an unrecorded day *inside a live run*, not of the absence of
  /// a run — and of 137 profiles in production exactly one has a reading day at all. A deep red
  /// tile shouting at somebody who has not started is the one first impression nothing recovers
  /// from, so `none`, `broken` and the no-snapshot invitation are pinned here.
  static let dawn = StreakGround.ramp(atHour: StreakGroundRamp.anchors[0].hour)

  /// `kCandleGlow`, the Library Card's light-from-below, and it means something specific.
  ///
  /// Not on the ramp at all and not a pale hour of it: the inversion between "the day is in" and
  /// "the day is not" is the whole ladder, so recorded is a ground no hour can reach. It also
  /// costs no new colour — the app already owns this pair.
  static let recorded = StreakGround(
    top: StreakRGB(0xFFFDF8),
    bottom: StreakRGB(0xFFE8C4),
    recorded: true
  )
}

/// One CSS `radial-gradient(<rx>% <ry>% at <cx>% <cy>%, …)` layer.
///
/// **SwiftUI's `RadialGradient` is a circle, so the ellipse is a circle of the horizontal radius
/// squashed vertically.** That approximation is exact for the stops (every one is a fraction of
/// the same radius, and the squash scales them all alike) and inexact only in that CSS would
/// resolve an ellipse's stops along each axis independently.
private struct MeshEllipse: View {
  let stops: [Gradient.Stop]
  /// Centre, as fractions of the tile. CSS `at 50% 112%` is `(0.5, 1.12)` — below the bottom edge.
  let centre: CGPoint
  /// Radii, as fractions of the tile's width and height respectively.
  let radii: CGSize
  let size: CGSize

  var body: some View {
    let rx = max(radii.width * size.width, 0.01)
    let ry = max(radii.height * size.height, 0.01)
    RadialGradient(
      gradient: Gradient(stops: stops),
      center: .center,
      startRadius: 0,
      endRadius: rx
    )
    .frame(width: rx * 2, height: rx * 2)
    .scaleEffect(x: 1, y: ry / rx)
    .position(x: centre.x * size.width, y: centre.y * size.height)
  }
}

/// The layered mesh, back to front.
///
/// **A single radial glow was what this was, and it reads as cheap for a specific reason**: one
/// hue, lightened in the middle and darkened at the edge, with the light source dead centre.
/// Nothing in the reference sheet looks like that — every tile there runs two or three related
/// hues into each other, puts the light upper-left, and vignettes the corners.
///
/// The sheet's last layer is a few percent of `feTurbulence` grain. **It is skipped here**: there
/// is no SwiftUI equivalent worth adding, and faking it means shipping a noise PNG in the
/// extension bundle to carry an effect nobody can see from arm's length on a home screen.
private struct GroundView: View {
  let ground: StreakGround

  /// Where the mesh blobs sit over the base. Chosen by looking, at seven strengths: at 1 the
  /// accent is a separate blob on a differently coloured tile, below about 0.2 the six layers have
  /// been paid for and a plain diagonal is what comes back. 0.3 is where it stops being blobs and
  /// becomes one lit surface while the accent keeps its own hue.
  private let meshAlpha: Double = 0.3

  var body: some View {
    GeometryReader { geometry in
      let size = geometry.size
      ZStack {
        // The base colour under every layer, and the reason it is needed rather than tidy: a
        // radial gradient in SwiftUI paints nothing outside its own frame, where CSS carries the
        // last stop's colour to the edges of the box.
        ground.top.color

        if ground.isRecorded {
          MeshEllipse(
            stops: [
              .init(color: ground.bottom.color, location: 0),
              .init(color: ground.mid.color, location: 0.52),
              .init(color: ground.top.color, location: 1),
            ],
            centre: CGPoint(x: 0.5, y: 1.12),
            radii: CGSize(width: 1.30, height: 1.05),
            size: size
          )
        } else {
          diagonal(size)
          blob(
            ground.deep,
            centre: CGPoint(x: 0.5, y: 1.12),
            radii: CGSize(width: 0.95, height: 0.80),
            stop: 0.70,
            size: size
          )
          blob(
            ground.accent,
            centre: CGPoint(x: 0.88, y: 0.22),
            radii: CGSize(width: 0.70, height: 0.58),
            stop: 0.60,
            size: size
          )
          blob(
            ground.lift,
            centre: CGPoint(x: 0.16, y: 0.10),
            radii: CGSize(width: 0.75, height: 0.60),
            stop: 0.62,
            size: size
          )
          MeshEllipse(
            stops: [
              .init(color: .black.opacity(0), location: 0.40),
              .init(color: .black.opacity(0.16), location: 0.78),
              .init(color: .black.opacity(0.36), location: 1),
            ],
            centre: CGPoint(x: 0.5, y: 0.40),
            radii: CGSize(width: 1.15, height: 0.95),
            size: size
          )
        }
      }
      .frame(width: size.width, height: size.height)
      .clipped()
    }
  }

  /// CSS `linear-gradient(158deg, top 0%, mid 52%, bottom 100%)`.
  ///
  /// 0deg points to the top and CSS angles run clockwise, so the axis is `(sin A, -cos A)` in
  /// screen coordinates. The ends are pushed out to where the perpendiculars through the corners
  /// meet that axis — `(w·|sin A| + h·|cos A|) / 2` from the centre — which is what lands the 0%
  /// and 100% stops in the corners rather than at the edge midpoints. Computed from the size
  /// rather than written as two fixed `UnitPoint`s so that the medium tile, which is nothing like
  /// square, gets the same *visual* angle as the small one.
  private func diagonal(_ size: CGSize) -> some View {
    let radians = 158.0 * .pi / 180
    let dx = sin(radians)
    let dy = -cos(radians)
    let half = (size.width * abs(dx) + size.height * abs(dy)) / 2
    let width = max(size.width, 0.01)
    let height = max(size.height, 0.01)
    return LinearGradient(
      gradient: Gradient(stops: [
        .init(color: ground.top.color, location: 0),
        .init(color: ground.mid.color, location: 0.52),
        .init(color: ground.bottom.color, location: 1),
      ]),
      startPoint: UnitPoint(
        x: 0.5 - half * dx / width,
        y: 0.5 - half * dy / height
      ),
      endPoint: UnitPoint(
        x: 0.5 + half * dx / width,
        y: 0.5 + half * dy / height
      )
    )
  }

  private func blob(
    _ colour: StreakRGB,
    centre: CGPoint,
    radii: CGSize,
    stop: Double,
    size: CGSize
  ) -> some View {
    // Alpha rather than a mix toward the base, for a reason worth recording: the accent is
    // derived (the ramp three hours ahead), so an alpha is ramp-relative for free and needs no
    // per-hour picking. Mixing lands somewhere similar but turns the violet into a rose-tinted
    // violet, so it has slightly less life for the same cost.
    MeshEllipse(
      stops: [
        .init(color: colour.opacity(meshAlpha), location: 0),
        .init(color: colour.opacity(0), location: stop),
      ],
      centre: centre,
      radii: radii,
      size: size
    )
  }
}

// MARK: - The character

/// The eight cut-outs, by name, in one place.
///
/// A pose is named by string on both sides of this feature — here and in the asset catalog — and
/// a typo renders nothing rather than failing loudly, which is why the mapping lives in exactly
/// one place instead of being spelled at each call site.
///
/// `m15-smug` ships with the set and is drawn by nothing: it was a candidate for the recorded
/// tile and `m13-blush` won. Listed rather than dropped, because "the eight poses" is the shape
/// the asset catalog is built to.
enum StreakCatPose {
  static let all = [
    "m01-flex", "m03-reading", "m05-puddle", "m06-snooze",
    "m07-drowsy", "m12-panic", "m13-blush", "m15-smug",
  ]

  static func forTier(_ tier: StreakTier) -> String {
    switch tier {
    case .dawn: return "m01-flex"
    case .morning: return "m03-reading"
    case .afternoon: return "m05-puddle"
    case .evening: return "m06-snooze"
    case .late: return "m07-drowsy"
    case .`final`: return "m12-panic"
    }
  }

  /// The day is in. The only pose with no hour attached.
  static let recorded = "m13-blush"

  /// No live run, at any hour — asleep, because there is nothing to be anxious about yet.
  static let noRun = "m06-snooze"
}

/// The cut-out, seated on the tile's bottom edge and cropped.
private struct StreakCat: View {
  let pose: String
  /// A tile with a line puts the cat at the right so the copy keeps the left half.
  let nudgedRight: Bool
  /// Share of the tile's height the cut-out is drawn at. 70% everywhere but the medium tile,
  /// which comes down to 62% to stay out of the copy's corner — see `medium(_:_:)`.
  var heightFraction: CGFloat = 0.70
  /// Share of the tile's width the cut-out extends **past** the trailing edge. The review page
  /// spells the same number as `right`, with the sign inverted: `right: -6%` there is `0.06`
  /// here, and `right: 2%` — the medium tile, held 2% inside the edge — is `-0.02`.
  var trailingOverhang: CGFloat = 0.06

  var body: some View {
    GeometryReader { geometry in
      // `UIImage(named:)` rather than `Image(_:)` so a pose the catalog has not been given yet
      // degrades to *no cat* and an otherwise untouched tile, instead of a placeholder box.
      if let image = UIImage(named: pose) {
        let height = geometry.size.height * heightFraction
        // **Bounded by height, never by width.** Aspect ratios across the set run 0.74 to 1.31,
        // so a width rule produces a different height per expression — and a 76%-wide cat is
        // 143pt tall in a 158pt tile, reaching the figure however far down it is pushed. The
        // width is derived from the image's own pixels for the same reason: asking SwiftUI to
        // `.fit` would silently re-introduce the width bound on the widest cut-out.
        let aspect = image.size.height > 0 ? image.size.width / image.size.height : 1
        Image(uiImage: image)
          .resizable()
          .frame(width: height * aspect, height: height)
          .frame(
            width: geometry.size.width,
            height: geometry.size.height,
            alignment: nudgedRight ? .bottomTrailing : .bottom
          )
          // Down 8% of the tile so the feet crop: the reference's arrangement, where the
          // mascot's feet are never drawn, and a crop is free in both CSS and SwiftUI.
          //
          // **The crop is why this lives in the container background and why the widget turns
          // content margins off.** Drawn inside the content box it would sit on the padding edge
          // instead of the tile's, which is a cat standing on a shelf; see `StreakWidget`.
          .offset(
            x: nudgedRight ? geometry.size.width * trailingOverhang : 0,
            y: geometry.size.height * 0.08
          )
      }
    }
  }
}

// MARK: - The flame and the figure

/// The app's flame, from the geometry `rive/streak_flame/icon.py` generates.
///
/// Two shapes and nothing else — the artboard's glow, sparks and gradients are mud at this
/// size, and the body plus the core are what make this read as *our* flame rather than as any
/// flame. Same reasoning, and the same tables, as `StreakFlameMark` in Dart.
struct StreakFlame: View {
  let size: CGFloat
  let color: Color
  var coreColor: Color?

  var body: some View {
    ZStack {
      shape(StreakFlameGeometry.body).fill(color)
      shape(StreakFlameGeometry.core).fill(coreColor ?? color.opacity(0.55))
    }
    // Boxed square with the flame centred, exactly as the Dart mark boxes itself, so `size`
    // means the same thing in both and a layout tuned against one holds for the other.
    .frame(width: size, height: size)
  }

  private func shape(_ table: [CGFloat]) -> Path {
    var path = Path()
    guard table.count >= 2 else { return path }
    let scale = size
    func point(_ i: Int) -> CGPoint {
      CGPoint(x: table[i] * scale, y: table[i + 1] * scale)
    }
    path.move(to: point(0))
    var i = 2
    while i + 5 < table.count {
      path.addCurve(to: point(i + 4), control1: point(i), control2: point(i + 2))
      i += 6
    }
    path.closeSubpath()
    return path
  }
}

/// The figure's face.
///
/// **Nunito**, which is `AppTextStyles.streak` subset to digits, with the shipped System SF
/// rounded as the fallback. `Font.custom` falls back silently, so the availability check goes
/// through `UIFont` — otherwise a missing font would look like a deliberately plainer tile.
///
/// **Tabular figures are not optional.** Without them the figure's width changes with the run and
/// the tile twitches on the night it goes from 9 to 10.
private func streakFigureFont(_ size: CGFloat) -> Font {
  // **The name is the PostScript name, and "Nunito" is not it.** `build_fonts.py` subsets this
  // face, and the file it writes carries the family name *Nunito ExtraBold* with the PostScript
  // name `Nunito-ExtraBold`; `UIFont(name: "Nunito")` therefore returns nil. Flutter is no guide
  // here — `pubspec.yaml` declares `family: Nunito` and Dart resolves against that declaration
  // rather than against anything inside the file, so the app draws the right face with a name
  // this side cannot use. Getting it wrong is silent: the figure falls through to SF Rounded and
  // the only symptom is that the widget's numeral stops matching the streak page's.
  for name in ["Nunito-ExtraBold", "Nunito ExtraBold"] where UIFont(name: name, size: size) != nil {
    return Font.custom(name, size: size).weight(.heavy).monospacedDigit()
  }
  return Font.system(size: size, weight: .heavy, design: .rounded).monospacedDigit()
}

/// The recorded tile's figure: white, with the flame's amber ringed behind it.
///
/// **All of the contrast is on the outline, and that is the trade.** White on the cream ground is
/// 1.96:1, so the numeral is legible because of the amber ring around it rather than in spite of
/// the fill. If that does not survive a device check, the fallback is a plain `#212529` figure —
/// `StreakGround.recorded.ink` is already exactly that, so it is a one-line change.
private struct StickerFigure: View {
  let text: String
  let size: CGFloat

  /// CSS sets `-webkit-text-stroke: 6px` with `paint-order: stroke fill`, i.e. a 6pt stroke
  /// centred on the glyph outline — so 3pt of it shows outside the white fill.
  private let reach: CGFloat = 3

  /// SwiftUI cannot stroke a `Text`, and a widget cannot host a UIKit label to do it properly
  /// (WidgetKit archives the view hierarchy; `UIViewRepresentable` does not survive that). So the
  /// outline is copies of the glyph in a ring behind the fill. Twelve is where the ring stops
  /// showing its own corners at this size. Static so the `ForEach` range is constant — a range
  /// SwiftUI cannot prove is fixed is what its "should only be used for constant data" complaint
  /// is about.
  private static let copies = 12

  var body: some View {
    ZStack {
      ForEach(0..<Self.copies, id: \.self) { index in
        let angle = Double(index) / Double(Self.copies) * 2 * .pi
        Text(text)
          .foregroundStyle(Palette.flame)
          .offset(x: reach * CGFloat(cos(angle)), y: reach * CGFloat(sin(angle)))
      }
      Text(text).foregroundStyle(.white)
    }
    .font(streakFigureFont(size))
  }
}

/// What every tile draws: a ground, a pose, a line, and whether the flame is lit.
struct StreakTileStyle {
  let ground: StreakGround
  let pose: String
  let line: String?
  /// Lit on the recorded tile and nowhere else. **This supersedes the "two tints, never three"
  /// note that used to be here**, which said the late state must not be a warmer version of the
  /// recorded one. The rule survives — there is still exactly one lit flame and one unlit one —
  /// but the unlit flame is no longer a fixed grey: it takes the hour's own `dim`, so what
  /// escalates is the ground it is washed over rather than the flame itself.
  let lit: Bool

  static func make(_ snapshot: StreakSnapshot, at date: Date) -> StreakTileStyle {
    let phase = snapshot.phase(at: date)
    let line = snapshot.line(at: date)

    if phase == .recorded {
      return StreakTileStyle(
        ground: .recorded,
        pose: StreakCatPose.recorded,
        line: line,
        lit: true
      )
    }

    // Pinned to dawn at every hour. The other half of `line(at:)`'s rule, and the reason is the
    // same: a reader with no run is not late for anything.
    if phase == .broken || snapshot.run(at: date) == 0 {
      return StreakTileStyle(
        ground: .dawn,
        pose: StreakCatPose.noRun,
        line: line,
        lit: false
      )
    }

    return StreakTileStyle(
      ground: .ramp(atHour: snapshot.readingHourFraction(at: date)),
      pose: StreakCatPose.forTier(snapshot.tier(at: date)),
      line: line,
      lit: false
    )
  }

  /// No snapshot at all: signed out, or a fresh install. Dawn's ground and the sleeping cat, for
  /// the same reason as `none` — this is the *common* first impression rather than an edge case,
  /// and a widget the reader deliberately placed must never look broken.
  static let invitation = StreakTileStyle(
    ground: .dawn,
    pose: StreakCatPose.noRun,
    line: nil,
    lit: false
  )
}

// MARK: - Timeline

struct StreakEntry: TimelineEntry {
  let date: Date
  let snapshot: StreakSnapshot?
}

struct StreakTimelineProvider: TimelineProvider {
  func placeholder(in context: Context) -> StreakEntry {
    StreakEntry(date: Date(), snapshot: nil)
  }

  func getSnapshot(in context: Context, completion: @escaping (StreakEntry) -> Void) {
    completion(StreakEntry(date: Date(), snapshot: StreakSnapshot.load()))
  }

  /// One entry per remaining hour of the reading day, plus the rollover, plus `.after` it.
  ///
  /// **This file used to emit three entries and say that per-hour entries "burn the refresh
  /// budget iOS grants and then visibly stall". That reasoning was wrong and the ladder overturns
  /// it.** Entries inside one timeline are free: the system renders them at their own dates
  /// without waking the extension. What iOS meters is **reloads** — calls to this function — and
  /// that count has not changed, because the policy has not changed. A minute-resolution countdown
  /// really would be expensive, and for that reason rather than for its entry count.
  ///
  /// So this costs nothing and makes the offline case *better*: a phone that never gets a refresh
  /// window now walks ~17 pre-rendered grounds and six tier boundaries rather than stalling on
  /// one. The warning hour no longer needs singling out either — it is one of the hours below.
  func getTimeline(in context: Context, completion: @escaping (Timeline<StreakEntry>) -> Void) {
    let now = Date()
    let calendar = Calendar.current
    let snapshot = StreakSnapshot.load()

    var dates = [now]
    if let snapshot {
      let rollover = snapshot.nextRollover(after: now, calendar: calendar)
      var cursor = calendar.dateInterval(of: .hour, for: now)?.end ?? rollover
      // Bounded rather than trusted: a calendar that fails to advance an hour (or a rollover that
      // somehow lands in the past) must not spin here, since this runs inside a system callback.
      var emitted = 0
      while cursor < rollover, emitted < 26 {
        dates.append(cursor)
        guard let next = calendar.date(byAdding: .hour, value: 1, to: cursor) else { break }
        cursor = next
        emitted += 1
      }
      dates.append(rollover)
    }

    let entries = dates.map { StreakEntry(date: $0, snapshot: snapshot) }
    completion(Timeline(entries: entries, policy: .after(dates.last ?? now)))
  }
}

// MARK: - The tiles

// MARK: - The bookmark

/// The library's own ribbon, as a `Shape`.
///
/// **Ported from `assets/icons/bookmarkIcon.svg`, and held in that asset's own units** so the two
/// can be compared without arithmetic — `test/streak_widget_palette_test.dart` reads these five
/// numbers back out of this file and asserts they still match the SVG and the Dart constants. That
/// is the same mechanism the palette uses, for the same reason: this is a second copy of a shape,
/// and a second copy drifts.
///
/// **Parametric rather than a point dump**, unlike `StreakFlameGeometry`. The flame is an organic
/// curve with no description shorter than its control points, so it is generated. This is a
/// rectangle with a notch cut out of the bottom and two rounded corners — the shape *is* its
/// parameters, and five named numbers say what sixty coordinates would obscure.
struct BookmarkRibbon: Shape {
  /// The visible ribbon, x4 to x17.5 of the asset's 22-wide box. Matches
  /// `_kBookmarkRibbonWidth` in `lib/ui/widgets/book/reading_bookmark.dart`.
  static let unitWidth: CGFloat = 13.5
  /// y0 to y30 of the asset's 38-tall box. The remainder is bleed its drop-shadow filter needed.
  static let unitHeight: CGFloat = 30
  /// The apex of the bottom notch: the SVG's `L10.75 24.2099`, dead centre horizontally.
  static let unitApexY: CGFloat = 24.2099
  /// The bottom corners' round. The SVG's bottom-left runs from (4, 28.7999) to (4.75, 30).
  static let unitCornerX: CGFloat = 0.75
  static let unitCornerY: CGFloat = 1.2

  func path(in rect: CGRect) -> Path {
    let w = rect.width
    let h = rect.height
    let cx = w * Self.unitCornerX / Self.unitWidth
    let cy = h * Self.unitCornerY / Self.unitHeight
    let apex = h * Self.unitApexY / Self.unitHeight

    var path = Path()
    path.move(to: CGPoint(x: 0, y: 0))
    path.addLine(to: CGPoint(x: w, y: 0))
    path.addLine(to: CGPoint(x: w, y: h - cy))
    // The corners are a single quadratic each, where the SVG spends three cubics. At the size
    // this is ever drawn — about 14pt tall — the difference is well under a pixel, and the notch
    // and the flat top are what make the silhouette recognisable.
    path.addQuadCurve(to: CGPoint(x: w - cx, y: h), control: CGPoint(x: w, y: h))
    path.addLine(to: CGPoint(x: w / 2, y: apex))
    path.addLine(to: CGPoint(x: cx, y: h))
    path.addQuadCurve(to: CGPoint(x: 0, y: h - cy), control: CGPoint(x: 0, y: h))
    path.closeSubpath()
    return path
  }
}

/// Where the ribbon hangs, and how big it is.
///
/// **A port of `readingBookmarkInsetFor` and `ReadingBookmark.scale`** in
/// `lib/ui/widgets/book/reading_bookmark.dart`. Read that file for the reasoning — all of it
/// applies here and none of it is repeated. The two facts that matter to this side:
///
/// **The mark slides across the cover's top edge, gutter to fore-edge**, which is what a bookmark
/// in a closed book does and the one encoding of position that never leaves the cover. It is read,
/// never dragged: the widget is not an input device and neither is the shelf.
///
/// **A null progress pins it at the fore-edge rather than sending it to the gutter.** Every book
/// has a null position until someone answers, and a mark at the gutter would claim the reader had
/// barely started. So the ribbon only ever moves *in* from where readers already know it — and
/// that is why this draws for a book with no recorded position, where `ProgressBar` draws nothing.
enum ReadingBookmarkTrack {
  /// `kReadingBookmarkInset` — the shipped pin, as a `right:` inset on the asset's box.
  static let pin: CGFloat = 8
  /// `_kBookmarkRightBleed` — empty box down the asset's right-hand side.
  static let rightBleed: CGFloat = 4.5
  /// `_kBindingFraction` — the near end of the track. A bookmark cannot sit in the gutter.
  static let bindingFraction: CGFloat = 0.082
  /// `kReadingBookmarkBook` — the shelf's book, which `scale: 1` is sized against.
  static let referenceBook: CGFloat = 124

  /// Taken off the height, exactly as the Library Card does, because that is the dimension
  /// `referenceBook` is. The ribbon therefore arrives at the tile's scale rather than being
  /// given a size of its own.
  static func scale(coverHeight: CGFloat) -> CGFloat { coverHeight / referenceBook }

  /// The trailing inset of the **visible ribbon's** right edge.
  ///
  /// The Dart function returns an inset to the *asset box's* edge, because Flutter positions the
  /// whole 22-wide box; this side draws only the ribbon, so the bleed is added back in here. Both
  /// ends are still measured to the ribbon's left edge, so the bleed cancels out of the travel
  /// rather than shifting one end of it — which is the property that makes the two agree.
  static func trailingInset(
    progress: Double?,
    coverWidth: CGFloat,
    scale: CGFloat
  ) -> CGFloat {
    let pinned = (pin + rightBleed) * scale
    guard let progress else { return pinned }
    let travel =
      coverWidth - pinned - BookmarkRibbon.unitWidth * scale - coverWidth * bindingFraction
    guard travel > 0 else { return pinned }
    return pinned + (1 - min(max(progress, 0), 1)) * travel
  }
}

/// The jacket: the real cover when the app has managed to store one, and the sampled colour when
/// it has not.
///
/// **The colour is still here and is not dead code.** It is what the tile draws on the first render
/// after a book change (the thumbnail is fetched *after* the snapshot is written), for a reader who
/// was offline when that happened, and for any book whose cover URL 404s. Keeping it is what let
/// thumbnails ship without a `v` bump or a coordinated release — see `StreakSnapshotBook.coverFile`.
///
/// **Only the medium tile draws one.** Small dropped it, and losing it is what bought the line.
private struct Jacket: View {
  let book: StreakSnapshotBook
  let ground: StreakGround
  let width: CGFloat
  let height: CGFloat

  private var thumbnail: UIImage? {
    guard let name = book.coverFile, let url = StreakWidgetCovers.url(for: name) else {
      return nil
    }
    // `contentsOfFile:` rather than `Image(contentsOfFile:)` so a file that is missing or not a
    // PNG degrades to the colour rather than to an empty box — the same reason `StreakCat` uses
    // `UIImage(named:)`.
    return UIImage(contentsOfFile: url.path)
  }

  var body: some View {
    let colour = Color(coverHex: book.coverColor) ?? ground.div.color
    Group {
      if let image = thumbnail {
        Image(uiImage: image)
          .resizable()
          // **`fill` and a crop, not `fit`.** Jackets are not one ratio — a trade paperback is
          // near 2:3 and this frame is 40×58 — and `fit` would letterbox the difference with the
          // ground showing through, which reads as a badly placed image rather than as a book.
          // The thumbnail is written at 120px wide with its height left proportional for exactly
          // this: the aspect is decided here, where the frame is known.
          .aspectRatio(contentMode: .fill)
      } else {
        colour
      }
    }
    .frame(width: width, height: height)
    .overlay(alignment: .leading) {
      // The spine, which is what makes a *rectangle* read as a book at this size. Kept over the
      // real cover too, at half strength: a photographed jacket already has its own edge, so the
      // full 18% reads as a black stripe painted across the artwork.
      Rectangle()
        .fill(.black.opacity(thumbnail == nil ? 0.18 : 0.09))
        .frame(width: 3)
    }
    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
    // **The edge, without which a pale cover is a hole in the tile.** `cover_color` is sampled
    // from the jacket, so for the very many books whose cover is white paper it comes back
    // near-white — `#FDFDFB` on the device this was found on — and a near-white rectangle on
    // the recorded tile's cream ground is invisible. It read as a cover that had failed to
    // load, which is the worst way for it to be wrong: the reader cannot tell a working
    // placeholder from a broken image.
    //
    // This is the trap `AGENTS.md` records for `kStatTileCool` and `stampMark`, one level out:
    // a colour chosen for one role promises nothing about its lightness, and `cover_color` was
    // sampled to *tint* a generated cover rather than to be the whole of one. The same applies
    // to the `ground.div` fallback above, which is a divider token and fainter still.
    //
    // **Kept for real covers as well**, because a white-jacketed book photographs white: the
    // defect is about the cover's lightness against cream, not about it being a placeholder.
    //
    // Drawn in the ground's own ink so it works on all seven grounds rather than on the cream
    // one: a fixed dark hairline would vanish on the 23:00 tile. `strokeBorder` insets by half
    // the line width, so it stays inside the shape and needs no clipping of its own — and it is
    // applied *after* `clipShape` so the spine is clipped to the corners but the edge is not.
    .overlay {
      RoundedRectangle(cornerRadius: 3, style: .continuous)
        .strokeBorder(ground.ink.color.opacity(0.28), lineWidth: 1)
    }
    // **Outside the clip, because a bookmark a clip swallows is not a bookmark** — the app's own
    // words, in `card_cover_row.dart`. It also sits above the edge hairline, since a bookmark is
    // on top of the book rather than under its outline.
    .overlay(alignment: .topTrailing) {
      bookmark
    }
  }

  /// The ribbon, at the tile's scale, slid in from the fore-edge by how far through the book the
  /// reader is.
  ///
  /// **Drawn for every book the tile shows, including one with no recorded position.** That is
  /// `ReadingBookmarkTrack`'s rule and not an oversight here: the mark says *this is the book you
  /// have open*, which is true before anyone answers the percent wheel, and a null position pins it
  /// at the fore-edge rather than claiming the reader has barely started. `ProgressBar` makes the
  /// opposite call — it draws nothing without a position — because a bar at zero is a claim about
  /// how far in the reader is, where the ribbon at its pin is the absence of one.
  private var bookmark: some View {
    let scale = ReadingBookmarkTrack.scale(coverHeight: height)
    return BookmarkRibbon()
      .fill(.white)
      .frame(
        width: BookmarkRibbon.unitWidth * scale,
        height: BookmarkRibbon.unitHeight * scale
      )
      // **The shadow is what makes a white ribbon visible on a white cover**, which is the same
      // problem the edge hairline above solves for the jacket itself — and this book is artwork on
      // a white field, so it is not hypothetical. `shadow` follows the shape's alpha, so the notch
      // is respected; the app has to blur a copy by hand only because `flutter_svg` will not
      // render the SVG's own filter. Same drop, blur and strength, scaled.
      .shadow(color: .black.opacity(0.5), radius: 4 * scale, y: 4 * scale)
      .offset(
        x: -ReadingBookmarkTrack.trailingInset(
          progress: book.progress,
          coverWidth: width,
          scale: scale
        )
      )
  }
}

/// The flame and the run on one row.
private struct RunAndFlame: View {
  let run: Int
  let style: StreakTileStyle
  /// The localized "day streak", which the tile no longer prints. See `body`.
  let label: String
  let flameSize: CGFloat
  let figureSize: CGFloat
  /// A run of zero prints no figure. See `nothingYet`.
  var showsFigure: Bool = true

  var body: some View {
    HStack(spacing: 8) {
      StreakFlame(
        size: flameSize,
        color: style.lit ? Palette.flame : style.ground.dim.color,
        // **The unlit core is knocked out to the tile, not drawn in grey.** Shipped, it was
        // `secondaryText` over the same grey at 55%, which has no internal contrast — so the
        // notch and the low fat core that make this *our* flame disappear and it reads as a
        // teardrop. Cutting through to the ground behind is the app's own vocabulary:
        // `docs/mockups/empty-states/PROMPTS.md` records that details inside a shape are knocked
        // out rather than drawn on top. `top` and not `mid`, because the flame is at the top.
        coreColor: style.lit ? Color(hex: 0xFFD479) : style.ground.top.color
      )
      if showsFigure {
        Group {
          if style.lit {
            StickerFigure(text: "\(run)", size: figureSize)
          } else {
            Text("\(run)")
              .font(streakFigureFont(figureSize))
              .foregroundStyle(style.ground.ink.color)
          }
        }
        // **The figure's layout height is its font size, which is what CSS's `line-height: 1`
        // means — and without this line the tile is visibly not the design.**
        //
        // Nunito ExtraBold's own metrics are ascent 1011 and descent -353 on a 1000 em, so
        // SwiftUI lays a 40pt `Text` out in a **54.6pt** line box and puts the digit's cap
        // 12.2pt below its top. The review page sets `line-height: 1`, i.e. a 40pt box, which
        // applies -7.3pt of half-leading and lifts the same glyph to 4.9pt. Measured off a
        // simulator screenshot against the page, that was the whole difference between them:
        // the amber sat **23.0pt** from the tile's top edge where the page draws it at 15.5pt
        // (both predicted to within half a point by the arithmetic above). The symptom is a 9pt
        // dead band across the top of the tile with the run row pushed down toward the cat — a
        // tile that reads as a smaller, more timid version of itself rather than as broken,
        // which is why it survived a build, a typecheck and a review page.
        //
        // `.frame(height:)` centres the glyph without clipping it: the ink is 28.2pt tall in a
        // 40pt box, so nothing overflows, and only the *layout* height changes. Re-measure with
        // `scripts/measure_widget_shot.py` after touching this.
        .frame(height: figureSize)
      }
    }
    // Washed back over a coloured ground so the character is the brightest thing on an
    // unrecorded tile; at full strength on the recorded one, where there is nothing competing
    // and nothing left to ask for.
    .opacity(style.lit ? 1 : 0.5)
    // The label is the one string the tile stopped printing — the room went to the line, and a
    // figure beside a flame is not ambiguous. It is still read aloud, so the localized copy is
    // still doing work and cannot rot. With no figure there is nothing to read: the flame alone
    // says nothing, and the line below it is carrying the meaning.
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(run) \(label)")
    .accessibilityHidden(!showsFigure)
  }
}

/// The tier's line.
private struct TileLine: View {
  let text: String
  let ground: StreakGround
  /// 52% of the content width on a tile that has a cat, which is what keeps the copy clear of
  /// the fur. Without it `m05-puddle` is unusable: at 145pt wide it overlaps the copy column by
  /// 59.5pt where every other cut-out stays under 10pt.
  ///
  /// The medium tile passes 43% instead, of a content box more than twice as wide — see
  /// `medium(_:_:)`, where the cap is against the cat's corner rather than against its body.
  let maxWidth: CGFloat?
  /// Leading everywhere but the medium tile, where the copy hugs the trailing edge and ragging
  /// it left would leave a wedge of empty ground between the text and the corner it is anchored
  /// to. Flipping medium back is this one argument.
  var alignment: TextAlignment = .leading

  var body: some View {
    Text(text)
      .font(.system(size: 11))
      .italic()
      .foregroundStyle(ground.dim.color)
      // **Three lines, not two, and the Korean copy is why.** "곧 자정인데, 책은 언제 플려나.."
      // is 14 full-width syllables and a 52%-wide column fits about six of them.
      .lineLimit(3)
      .minimumScaleFactor(0.85)
      .multilineTextAlignment(alignment)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: maxWidth, alignment: alignment == .trailing ? .trailing : .leading)
  }
}

struct StreakWidgetView: View {
  var entry: StreakEntry
  @Environment(\.widgetFamily) private var family

  var body: some View {
    let style = self.style
    content(style)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .padding(14)
      // The ground and the cat go in the *container background* rather than into the content,
      // for two reasons. They have to bleed past the widget's content margins — a cat cropped
      // at the padding edge instead of the tile edge is a cat standing on a shelf — and the
      // mockup draws them behind the runrow and the line at `z-index: 0` anyway.
      .widgetContainerBackground {
        ZStack {
          GroundView(ground: style.ground)
          StreakCat(
            pose: style.pose,
            // The medium tile anchors the cat right in every state, not only when there is a
            // line: the four-corner layout gives it a corner of its own, and the recorded tile
            // — which has no line — keeps it there rather than sliding to the middle of a
            // 338pt tile and sitting on top of the book.
            nudgedRight: style.line != nil || family == .systemMedium,
            heightFraction: family == .systemMedium ? 0.62 : 0.70,
            trailingOverhang: family == .systemMedium ? -0.02 : 0.06
          )
        }
      }
  }

  private var style: StreakTileStyle {
    guard let snapshot = entry.snapshot else { return .invitation }
    return StreakTileStyle.make(snapshot, at: entry.date)
  }

  @ViewBuilder private func content(_ style: StreakTileStyle) -> some View {
    if let snapshot = entry.snapshot {
      // **A run of zero is drawn as an invitation, never as a figure.** A signed-in reader with
      // nothing recorded would otherwise get "0" and a label, which is the announcement that they
      // have nothing rather than the encouragement to start — and of 137 profiles in production
      // exactly one has a reading day, so this is the common state and not an edge. The streak
      // page makes the same call with `streakNothingYet`.
      //
      // The chosen-ladder sheet *does* render its `none` tile with a 0. That is the sheet showing
      // eight cards in a row rather than a decision about the state, and the argument above is
      // older and better than the render.
      //
      // This also currently swallows the *broken* run, which the design record wants drawn as the
      // record surviving (`sc-broken`) rather than as a fresh start. That needs a localized "your
      // longest run" string the app does not have yet; `longestStreak` is already in the snapshot
      // waiting for it.
      if snapshot.run(at: entry.date) == 0 {
        nothingYet(snapshot, style)
      } else {
        switch family {
        case .systemMedium: medium(snapshot, style)
        default: small(snapshot, style)
        }
      }
    } else {
      invitation(style)
    }
  }

  /// Signed in, nothing recorded — or a run that has ended. Dawn's ground, a sleeping cat, and
  /// the one line that never escalates.
  private func nothingYet(_ snapshot: StreakSnapshot, _ style: StreakTileStyle) -> some View {
    GeometryReader { geometry in
      VStack(alignment: .leading, spacing: 0) {
        RunAndFlame(
          run: 0,
          style: style,
          label: snapshot.copy?.dayStreak ?? "day streak",
          flameSize: 28,
          figureSize: 40,
          showsFigure: false
        )
        if let line = style.line {
          TileLine(text: line, ground: style.ground, maxWidth: geometry.size.width * 0.52)
            .padding(.top, 3)
        }
        Spacer(minLength: 0)
      }
    }
  }

  /// Fresh install, or signed out. An invitation rather than a zero or a blank.
  ///
  /// This inverts the Library Card's omit-rather-than-zero-fill rule, for the reason the streak
  /// chip already inverted it: a widget the reader deliberately placed must never look broken,
  /// and of 137 profiles in production exactly one has a reading day at all — so this state is
  /// the common first impression rather than an edge case.
  ///
  /// The two strings here are English only and knowingly so: there is no snapshot, so there is no
  /// translated copy to read. That is the one place in the tile where Swift holds a sentence.
  private func invitation(_ style: StreakTileStyle) -> some View {
    GeometryReader { geometry in
      VStack(alignment: .leading, spacing: 4) {
        StreakFlame(
          size: 28,
          color: style.ground.dim.color,
          coreColor: style.ground.top.color
        )
        .opacity(0.5)
        Text("Start a streak")
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(style.ground.ink.color)
        TileLine(
          text: "Open Libstack and record a night.",
          ground: style.ground,
          maxWidth: geometry.size.width * 0.52
        )
        Spacer(minLength: 0)
      }
    }
  }

  /// **No jacket, and dropping it is what pays for everything else here.** The shipped small drew
  /// a 30×44 jacket, the flame, the run, the label and the title, and had no room left for a line
  /// — so `open` and `late` were the same drawing, which is the one thing phase 1 existed to fix.
  /// Small now answers *where is my run*; medium answers *what am I reading*.
  ///
  /// The tap still opens the book with nothing here depicting one, which is the cost to record.
  /// If that is wrong the symptom will be taps landing in a book the reader did not expect, and
  /// the fix is the jacket returning as a corner detail rather than the line going away.
  /// (Nothing is wired yet; the deep links are tracked separately.)
  private func small(_ snapshot: StreakSnapshot, _ style: StreakTileStyle) -> some View {
    GeometryReader { geometry in
      VStack(alignment: .leading, spacing: 0) {
        RunAndFlame(
          run: snapshot.run(at: entry.date),
          style: style,
          label: snapshot.copy?.dayStreak ?? "day streak",
          flameSize: 28,
          figureSize: 40
        )
        if let line = style.line {
          TileLine(text: line, ground: style.ground, maxWidth: geometry.size.width * 0.52)
            .padding(.top, 3)
        }
        Spacer(minLength: 0)
      }
    }
  }

  /// **Four corners, not two columns: the run top-left, the copy top-right, the book along the
  /// floor, and the cat in the corner opposite the run.**
  ///
  /// The two-column version this replaces put the jacket in a column of its own at the far left
  /// with the run, title, author, progress and line stacked beside it, and it cost twice over.
  /// The line inherited small's *52% of the column* cap — but the column now started a jacket and
  /// a gap in from the left, so the copy came out **76pt** wide, narrower on the wide tile than on
  /// the narrow one it was supposed to have more room than. And a jacket at the left margin with
  /// everything else to its right reads as a sidebar rather than as part of the tile. Anchored to
  /// the corners the copy gets **133pt, 1.74x**, and the jacket, title, author and progress sit on
  /// the floor as one object.
  ///
  /// **What it costs is the cat**, which comes down from 70% of the tile to **62%**: at 70% its
  /// head reaches the copy's own corner, and the copy is the one thing on this tile that cannot be
  /// sat behind. So the character is smaller here than on any other tile. 62% puts its crown at
  /// 72.7pt from the top against three lines of copy ending near 57pt.
  ///
  /// The run row is small's, at 28 and 40 rather than the two-column version's 24 and 34 — there
  /// is no jacket beside it any more, so there is nothing for a shrunken figure to make room for,
  /// and the review page has always drawn both families' figures at 40.
  ///
  /// The recorded tile leaves the top-right corner empty, because `recorded` has no line in any
  /// locale. That is the one state where the eye has nothing to travel to, and it is correct: the
  /// day is in and the tile has nothing left to ask for.
  private func medium(_ snapshot: StreakSnapshot, _ style: StreakTileStyle) -> some View {
    GeometryReader { geometry in
      // Corner-anchored rather than a grid, because three of the four are on an edge and the
      // fourth — the cat — is in the container background and out of this layout entirely. Each
      // child takes the whole content box and aligns itself inside it, which is what puts them
      // 14pt from the tile's edges: the padding is applied once, around `content`, in `body`.
      ZStack {
        RunAndFlame(
          run: snapshot.run(at: entry.date),
          style: style,
          label: snapshot.copy?.dayStreak ?? "day streak",
          flameSize: 28,
          figureSize: 40
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

        if let line = style.line {
          // **43% of the content box, which is 133pt — not 43% of the 338pt tile.** The review
          // page spells the same cap as an absolute 133px for exactly this reason: a CSS
          // percentage on a corner-anchored box resolves against the tile, so the two sides
          // measure from different origins and only a pinned value can be read as agreeing.
          //
          // The cap is against the cat's **corner** rather than its body: what matters here is
          // keeping three lines of Korean clear of the crown at 72.7pt, not keeping them off
          // `m05-puddle`'s flank, which is what small's 52% is for.
          TileLine(
            text: line,
            ground: style.ground,
            maxWidth: geometry.size.width * 0.43,
            alignment: .trailing
          )
          // Down 2pt, toward the numeral's cap rather than its box. The figure is boxed to its
          // own font size (see `RunAndFlame`), so its ink starts 4.9pt below the content top;
          // the copy's first line, set at 11pt, starts far higher than that. 2pt closes part of
          // the gap by eye. The honest fix is a baseline alignment, which two opposite corners
          // of a `ZStack` cannot share.
          .padding(.top, 2)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }

        if let book = snapshot.book {
          HStack(alignment: .bottom, spacing: 9) {
            Jacket(book: book, ground: style.ground, width: 40, height: 58)
            VStack(alignment: .leading, spacing: 0) {
              Text(book.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(style.ground.ink.color)
                .lineLimit(1)
              if let author = book.author, !author.isEmpty {
                Text(author)
                  .font(.system(size: 11))
                  .foregroundStyle(style.ground.dim.color)
                  .lineLimit(1)
                  .padding(.top, 1)
              }
              if let progress = book.progress {
                // Pinned rather than filling the column, so the bar's length says nothing about
                // how long the title happens to be.
                ProgressBar(value: progress, ground: style.ground)
                  .frame(width: 88)
                  .padding(.top, 5)
              }
            }
            // **47% of the content box, and this is the guard the two-column layout did not
            // need.** A `lineLimit(1)` title takes whatever width it is offered, so an unbounded
            // column runs a long title straight under the cat. 47% of 310pt is 146pt, and with
            // the jacket and the gap that puts the floor's right edge at 195pt — clear of
            // `m05-puddle`, the widest cut-out, whose flank reaches 202pt.
            .frame(maxWidth: geometry.size.width * 0.47, alignment: .leading)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
      }
    }
  }
}

private struct ProgressBar: View {
  let value: Double
  let ground: StreakGround

  var body: some View {
    GeometryReader { geometry in
      ZStack(alignment: .leading) {
        // The ground's own divider rather than `Palette.divider`, which is a light grey in the
        // light theme and would be the brightest thing on a dark tile.
        Capsule().fill(ground.div.color)
        Capsule()
          .fill(Palette.flame)
          .frame(width: max(2, geometry.size.width * min(max(value, 0), 1)))
      }
    }
    .frame(height: 3)
  }
}

extension View {
  /// `containerBackground` is iOS 17, and omitting it there leaves the widget unpadded and
  /// wrong in StandBy; it does not exist at all on 15 and 16, where the background has to be
  /// drawn as an ordinary layer. Both spellings, rather than raising the floor to 17 and
  /// dropping every reader the app still supports.
  ///
  /// Takes a view rather than a colour since the ladder: the ground is a six-layer mesh with a
  /// cat sitting on it.
  @ViewBuilder func widgetContainerBackground<Background: View>(
    @ViewBuilder _ background: () -> Background
  ) -> some View {
    if #available(iOS 17.0, *) {
      self.containerBackground(for: .widget) { background() }
    } else {
      ZStack {
        background()
        self
      }
    }
  }
}

struct StreakWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "StreakWidget", provider: StreakTimelineProvider()) { entry in
      StreakWidgetView(entry: entry)
    }
    // English only, and knowingly: WidgetKit reads these from the extension's own bundle
    // before any snapshot exists, so they cannot come from the snapshot's copy the way every
    // string inside the widget does. Localizing them means an InfoPlist.strings per locale.
    .configurationDisplayName("Reading streak")
    .description("Your run, and the book you are in.")
    .supportedFamilies([.systemSmall, .systemMedium])
    // **The tile owns its own inset, and from iOS 17 it does not by default.** The system adds
    // content margins of its own — about 16pt — *around* whatever the view does, so
    // `StreakWidgetView`'s `.padding(14)` would stack on top of them and the content box would
    // come out near 98pt wide inside a 164pt tile instead of 136pt. The symptom would not be an
    // error but a tile that looks like a smaller, more timid version of the design, and it is
    // invisible in the review page, which draws the 14pt inset directly.
    //
    // **Correct, but not isolated on device.** A simulator screenshot measured the content inset
    // at 14.0pt with this line present (`scripts/measure_widget_shot.py`: amber 16.7pt from the
    // edge, which is 14pt plus the flame's own 2.7pt inside its box) — so the shipped behaviour
    // is right. What that run cannot say is whether the margins were ever being applied, because
    // SpringBoard may have been showing a cached snapshot from before the install. Removing this
    // to find out would need the widget re-added to a home screen by hand.
    //
    // **No `#available` guard, and that is not an oversight.** Unlike `containerBackground`, this
    // is declared `@available(iOS 15.0, *)` and `@_alwaysEmitIntoClient` — Apple's own body does
    // the `if #available(iOS 17.0, *)` and returns `self` below it, which is why it can be called
    // from our 15.0 floor at all. Wrapping it in a guard here is impossible rather than merely
    // redundant: the two branches of an `if #available` would have different opaque types, which
    // is what makes the obvious `widgetContainerBackground`-style helper fail to compile.
    .contentMarginsDisabled()
  }
}

@main
struct StreakWidgetBundle: WidgetBundle {
  var body: some Widget {
    StreakWidget()
  }
}
