// swift-tools-version: 6.1

import PackageDescription

/*
 * AetherEngine, for the app to link, pinned to one commit: the engine ships
 * its FFmpeg build with it, and the app is tested against one.
 *
 * The commit is on the app's fork (mickey2266/AetherEngine, branch
 * `aiostreams-7.73.0`): upstream 7.73.0 plus the fork's own commits, replayed
 * from `aiostreams-7.72.0` (their hashes there in brackets). All five went on
 * unchanged.
 * - 6b9bdb3f (277f8cec): the engine's software player (interlaced H.264 and the like)
 *   labelled 7.1 MPEG_7_1_C, which put the side and rear surrounds in each
 *   other's speakers; it now labels it WAVE_7_1 (Dolby's TrueHD 7.1 channel
 *   check on a Samsung HW-Q990F). The AVPlayer route's FLAC bridge was right
 *   as upstream has it.
 * - d75f23ac (da591c84): for remuxes, a 64 MB read-ahead window and 128 MB ranges (were
 *   16 MB and 32 MB); a connection the reader waits on for 8 s below the
 *   video's mean rate is replaced (3 in a row, then the check rests 2
 *   minutes); `confirmsAtmosOnHeldSourceConnection`, so the Atmos
 *   confirmation runs on the held connection the app uses by default.
 * - d3a0e94b (97e6591e): the silent Atmos stream the engine plays beside a rendered
 *   TrueHD Atmos or DTS:X bed stops while the picture-in-picture window
 *   shows, as the bed played nothing in the window beside it.
 * - 846eb4e8 (cca335d1): a forward seek past the read-ahead is read through the live
 *   connection up to what the link delivers in a new request's first-byte time
 *   (8 to 32 MB, was a fixed 8 MB); `prefetchLandings(atSeconds:)`, which holds
 *   the bytes a skip lands on ahead of the skip, from the page's skip segments.
 * - a3f3b9e8 (1d1d8835): a VOD `.m3u8` / `.m3u` whose loopback open fails, for any
 *   reason but the origin's refusal, takes the AE#154 reroute onto AVPlayer. Apple's trailer CDN
 *   (play-edge.itunes.apple.com) answers its playlist differently each time, so the reader caught it
 *   "answering byte ranges with other bytes" (or FFmpeg read invalid data) before it saw `#EXTM3U`.
 * Back to an upstream version once those are released there.
 *
 * TrueHD Atmos and DTS:X object rendering (`TrueHDObjectAudio`,
 * `DTSXObjectAudio`) are built in, for the page's Object audio switch (off by
 * default, `AetherPlayer.options`); TrueHD brings LibTrueHD with it. Without
 * the switch the app plays TrueHD and DTS-HD as 7.1 PCM, as Infuse does.
 * `DolbyVisionFelCurves` is built in too, for the page's Dolby Vision profile 7
 * FEL switch (off by default, `AetherPlayer.options`): the engine's fold of a
 * FEL enhancement layer into the profile 8.1 curves is on by default with that
 * trait, so the app turns it off unless the switch is on. The other optional
 * components (Dolby Vision dual layer, still reshaping) stay off. XcodeGen can't set a package's traits, which is why this package exists.
 */
let package = Package(
    name: "AetherHost",
    platforms: [.tvOS(.v18)],
    products: [
        .library(name: "AetherHost", targets: ["AetherHost"]),
    ],
    dependencies: [
        .package(url: "https://github.com/mickey2266/AetherEngine", revision: "a3f3b9e80c49cf4792e8d164dcae35affec81aae",
                 traits: ["TrueHDObjectAudio", "DTSXObjectAudio", "DolbyVisionFelCurves"]),
    ],
    targets: [
        .target(
            name: "AetherHost",
            dependencies: [.product(name: "AetherEngine", package: "AetherEngine")]
        ),
    ]
)
