import CacaoSoundCuesCore
import Foundation

/// 音を追加したときの最初の設定（設定画面 ⌘, で変更、この Mac に保存）
enum NewSoundDefaults {
    static let keyFadeIn = "default.key.fadeIn"
    static let keyFadeOut = "default.key.fadeOut"
    static let keyRetrigger = "default.key.retrigger"
    static let stepFadeIn = "default.step.fadeIn"
    static let stepFadeOut = "default.step.fadeOut"
    static let stepFadeOutAtEnd = "default.step.fadeOutAtEnd"
    static let stepStart = "default.step.start"
    static let stepStartSeconds = "default.step.startSeconds"
    static let curve = "default.curve"

    static func register() {
        UserDefaults.standard.register(defaults: [
            keyFadeIn: 0.0,
            keyFadeOut: 0.0,
            keyRetrigger: RetriggerMode.fadeOut.rawValue,
            stepFadeIn: 0.0,
            stepFadeOut: 0.0,
            stepFadeOutAtEnd: false,
            stepStart: StepStart.returnKey.rawValue,
            stepStartSeconds: 0.0,
            curve: FadeCurve.equalPower.rawValue,
        ])
    }

    private static var d: UserDefaults { .standard }

    private static var fadeCurve: FadeCurve {
        FadeCurve(rawValue: d.string(forKey: curve) ?? "") ?? .equalPower
    }

    static func keyCue(keyCode: UInt16, name: String, soundID: UUID) -> KeyCue {
        var p = PlaySettings(soundID: soundID)
        p.fadeIn = d.double(forKey: keyFadeIn)
        p.fadeOut = d.double(forKey: keyFadeOut)
        p.curve = fadeCurve
        var cue = KeyCue(keyCode: keyCode, name: name, play: p)
        cue.retrigger = RetriggerMode(rawValue: d.string(forKey: keyRetrigger) ?? "") ?? .fadeOut
        return cue
    }

    static func step(name: String, soundID: UUID) -> SequenceStep {
        var p = PlaySettings(soundID: soundID)
        p.fadeIn = d.double(forKey: stepFadeIn)
        p.fadeOut = d.double(forKey: stepFadeOut)
        p.fadeOutAtEnd = d.bool(forKey: stepFadeOutAtEnd)
        p.curve = fadeCurve
        var step = SequenceStep(name: name, play: p)
        step.start = StepStart(rawValue: d.string(forKey: stepStart) ?? "") ?? .returnKey
        step.startSeconds = d.double(forKey: stepStartSeconds)
        return step
    }
}
