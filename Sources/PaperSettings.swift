import Foundation

/// Everything the user can tune, persisted in `UserDefaults`: which paper, two
/// everyday modifiers on top of it, and the papers they have saved.
struct PaperSettings {
    var enabled = true
    var paper = PaperTexture.vellum   // working copy; Advanced edits change it in place
    var strength = 1.0                // multiplies the paper's wash and grain
    var coarseness = 1.0              // multiplies grain size, fibre length and formation scale
    var savedPapers: [PaperTexture] = []

    static let strengthRange = 0.0...2.0
    static let coarsenessRange = 0.5...2.0
    static let minGrainSize = 1.5

    var allPapers: [PaperTexture] { PaperTexture.builtIn + savedPapers }

    /// The stored paper the working copy started from.
    var original: PaperTexture? { allPapers.first { $0.name == paper.name } }

    var isEdited: Bool { original != paper }

    /// The paper as drawn: the working copy with strength and coarseness applied.
    var effectivePaper: PaperTexture {
        var drawn = paper
        drawn.wash = min(1, paper.wash * strength)
        drawn.grain = min(1, paper.grain * strength)
        drawn.grainSize = max(Self.minGrainSize, paper.grainSize * coarseness)
        drawn.fibreLength = paper.fibreLength * coarseness
        drawn.formationScale = paper.formationScale * coarseness
        return drawn
    }

    /// Stores the working copy under `name`, replacing a saved paper of that name.
    mutating func savePaper(as name: String) {
        let taken = PaperTexture.builtIn.contains { $0.name == name }
        paper.name = taken ? name + " (custom)" : name
        savedPapers.removeAll { $0.name == paper.name }
        savedPapers.append(paper)
    }

    var isSavedPaper: Bool { savedPapers.contains { $0.name == paper.name } }

    /// Removes the current paper from the saved list and falls back to a built-in.
    mutating func deleteSavedPaper() {
        savedPapers.removeAll { $0.name == paper.name }
        paper = .vellum
    }

    static func load(from defaults: UserDefaults = .standard) -> PaperSettings {
        var settings = PaperSettings()
        if defaults.object(forKey: "enabled") != nil { settings.enabled = defaults.bool(forKey: "enabled") }

        func stored(_ key: String, fallback: Double, in range: ClosedRange<Double>) -> Double {
            let value = defaults.object(forKey: key) != nil ? defaults.double(forKey: key) : fallback
            return min(max(value, range.lowerBound), range.upperBound)
        }
        settings.strength = stored("strength", fallback: settings.strength, in: strengthRange)
        settings.coarseness = stored("coarseness", fallback: settings.coarseness, in: coarsenessRange)

        let decoder = JSONDecoder()
        if let data = defaults.data(forKey: "paper"), let paper = try? decoder.decode(PaperTexture.self, from: data) {
            settings.paper = paper
        }
        if let data = defaults.data(forKey: "savedPapers"), let papers = try? decoder.decode([PaperTexture].self, from: data) {
            settings.savedPapers = papers
        }
        return settings
    }

    func save(to defaults: UserDefaults = .standard) {
        let encoder = JSONEncoder()
        defaults.set(enabled, forKey: "enabled")
        defaults.set(strength, forKey: "strength")
        defaults.set(coarseness, forKey: "coarseness")
        defaults.set(try? encoder.encode(paper), forKey: "paper")
        defaults.set(try? encoder.encode(savedPapers), forKey: "savedPapers")
    }
}
