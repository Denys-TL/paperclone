import Foundation

/// The paper-texture preset the overlay uses. The grain itself is generated in
/// `PaperTextureRenderer` from these parameters: `baseFrequency` (grain
/// fineness — higher = finer), `numOctaves` (fractal detail), `seed` (which
/// noise field), `tint` (paper colour the grain is multiplied over), and
/// `defaultOpacity` (the intensity the app starts at). Paper is modelled as
/// three layers: tooth (the fine grain above), formation (cloudy blotches
/// `formationScale` pixels across) and fibres (strands `fibreLength` pixels long).
struct PaperTexture {
    let name: String
    let baseFrequency: Double
    let numOctaves: Int
    let seed: Int
    let tintR: Int
    let tintG: Int
    let tintB: Int
    let defaultOpacity: Double   // 0...1
    let formationScale: Double   // pixels
    let defaultFormation: Double // 0...1
    let fibreLength: Double      // pixels
    let defaultFibre: Double     // 0...1
    let defaultTextureSize = 1.0 // tile edge multiplier

    /// Fine-speck size in pixels the preset starts at.
    var defaultGrainSize: Double { 1.0 / baseFrequency }

    /// The single texture the app ships: a semi-translucent haze for long
    /// reading sessions.
    static let vellumMist = PaperTexture(
        name: "Vellum Mist",
        baseFrequency: 1.10, numOctaves: 2, seed: 8,
        tintR: 247, tintG: 247, tintB: 249,
        defaultOpacity: 0.12,
        formationScale: 64, defaultFormation: 0.35,
        fibreLength: 18, defaultFibre: 0.30)
}
