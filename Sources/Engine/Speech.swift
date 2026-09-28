import AVFoundation

@MainActor
final class Speech: NSObject, ObservableObject {
    @Published var isSpeaking = false
    @Published var rate: Float = 0.5 {
        didSet { UserDefaults.standard.set(rate, forKey: "cortex.speech.rate") }
    }
    @Published var voiceID: String? {
        didSet { UserDefaults.standard.set(voiceID, forKey: "cortex.speech.voice") }
    }

    let availableVoices: [AVSpeechSynthesisVoice]
    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        availableVoices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .sorted { $0.name < $1.name }
        super.init()
        synthesizer.delegate = self
        if let stored = UserDefaults.standard.object(forKey: "cortex.speech.rate") as? Float {
            rate = stored
        }
        voiceID = UserDefaults.standard.string(forKey: "cortex.speech.voice")
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
    }

    func speak(_ text: String) {
        guard !text.isEmpty else { return }
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        let utterance = AVSpeechUtterance(string: text)
        if let voiceID, let voice = AVSpeechSynthesisVoice(identifier: voiceID) {
            utterance.voice = voice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        }
        utterance.rate = rate
        try? AVAudioSession.sharedInstance().setActive(true)
        synthesizer.speak(utterance)
        isSpeaking = true
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }
}

extension Speech: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }
}
