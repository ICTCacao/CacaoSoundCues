import AppKit
import CacaoSoundCuesCore
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let cacaoSoundCuesShow = UTType(exportedAs: "com.ictcacao.ccsc")
}

enum Selection: Equatable {
    case none
    case key(UInt16)
    case step(sequence: UUID, step: UUID)
}

enum LoadState: Equatable {
    case loading
    case ready
    case failed(String)
}

/// 再生中のリスト（同時に鳴らすリストは1つだけ）
struct SequenceRun {
    var sequenceID: UUID
    /// 鳴っている曲（Return 待ちの間は nil）
    var currentToken: UInt64?
    var currentIndex: Int?
    /// 前の曲の終わりを待っている次の曲（ミキサー側で待機中）
    var armedToken: UInt64?
    var armedIndex: Int?
    /// Return で鳴らす次の曲（タイミングが「Return キーを押したとき」のとき）
    var pendingIndex: Int?
    var changedAt = Date()

    /// 前の曲が終わり、Return を待っている
    var isWaiting: Bool { currentToken == nil }
}

@MainActor @Observable
final class AppModel {
    static let shared = AppModel()
    /// インスペクタの試聴ボタン用の持ち主
    static let previewOwner = UUID()
    /// 表示用のバージョン（3.0.1 から正式版。β は付けない）
    static let versionText = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    static let colors: [Color] = [.gray, .red, .orange, .yellow, .green, .teal, .blue, .purple]

    var show = Show(name: L("新しいキューシート")) {
        didSet { if show != oldValue { dirty = true } }
    }
    private(set) var showURL: URL?
    private(set) var dirty = false
    var selection: Selection = .none
    var selectedSequenceID: UUID?
    /// リストの開始／停止キーを割り当て待ち
    var capturingSequenceKey: UUID?
    /// キー一覧に落とした音ファイル。次に押したキーに割り当てる
    var pendingAssign: (urls: [URL], group: UUID?)?
    private(set) var buffers: [UUID: SampleBuffer] = [:]
    private(set) var loadStates: [UUID: LoadState] = [:]
    private(set) var status: [VoiceStatus] = []
    /// 再生中のリスト。リストは同時に1つしか鳴らさない
    private(set) var run: SequenceRun?
    /// ダブルクリックで決めた「次に始める曲」（鳴っていないリスト用）。Return か開始キーでここから始まる
    private(set) var cuedStart: (sequence: UUID, index: Int)?
    var message: String?
    /// 本番モード: 編集を止め、キー操作と再生だけにする（この Mac に保存。起動し直しても続く）
    private(set) var showMode = UserDefaults.standard.bool(forKey: "showMode") {
        didSet { UserDefaults.standard.set(showMode, forKey: "showMode") }
    }

    @ObservationIgnored let output = AudioOutput()
    /// delete キーで消すもの（音量ラインで選んでいるマーク）。設定画面が選んだときに入れる
    @ObservationIgnored var deleteKeyAction: (() -> Void)?
    @ObservationIgnored private var pendingFiles: [UUID: URL] = [:]
    @ObservationIgnored private var nextToken: UInt64 = 0
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var keyMonitor: Any?
    @ObservationIgnored private var activity: NSObjectProtocol?
    @ObservationIgnored private var started = false

    private init() {}

    var sampleRate: Double { output.sampleRate }

    var memoryBytes: Int { buffers.values.reduce(0) { $0 + $1.byteSize } }

    var isPlaying: Bool { status.contains { !$0.armed } }

    // MARK: - 起動

    func start() {
        guard !started else { return }
        started = true
        NewSoundDefaults.register()
        do {
            try output.start(preferredBufferFrames: 128)
        } catch {
            message = L("音声出力を開始できません: %@", error.localizedDescription)
        }
        output.onRestart = { [weak self] rateChanged in
            guard let self else { return }
            self.run = nil
            self.applyMasterVolume()
            if rateChanged { self.reloadAllSounds() }
        }
        applyMasterVolume()

        // 本番中にスリープ・App Nap で音が途切れないようにする
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled, .latencyCritical],
            reason: L("舞台の音出し"))

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKeyDown(event) ? nil : event
        }

        let t = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t

        #if DEBUG
        if openForScreenshots() { return }
        #endif
        if let path = UserDefaults.standard.string(forKey: "lastShowPath"),
           FileManager.default.fileExists(atPath: path) {
            open(URL(fileURLWithPath: path), evenInShowMode: true)
        }
    }

    #if DEBUG
    /// 開発版だけ: マニュアルの画面写真用に、起動引数でキューシートを開いて選ぶ
    /// （-debugOpen パス -debugSelectKey キーコード -debugSelectStep 番号 -debugSettings YES）。
    /// 最近使ったキューシートの記録は変えない
    static var isScreenshotRun: Bool { UserDefaults.standard.string(forKey: "debugOpen") != nil }

    private func openForScreenshots() -> Bool {
        let d = UserDefaults.standard
        guard let path = d.string(forKey: "debugOpen") else { return false }
        open(URL(fileURLWithPath: path), evenInShowMode: true, remember: false)
        if let k = Int(d.string(forKey: "debugSelectKey") ?? "") { selection = .key(UInt16(k)) }
        if let i = Int(d.string(forKey: "debugSelectStep") ?? ""), let seq = show.sequences.first, seq.steps.indices.contains(i) {
            selectedSequenceID = seq.id
            selection = .step(sequence: seq.id, step: seq.steps[i].id)
        }
        return true
    }
    #endif

    private func tick() {
        let s = output.mixer.snapshot()
        if s != status { status = s }
        advanceSequences()
    }

    // MARK: - キー入力

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        // ⌘ などの組み合わせはメニューへ、文字入力中はテキスト欄へ渡す
        if !event.modifierFlags.intersection([.command, .control, .option]).isEmpty { return false }
        let code = event.keyCode
        // Esc（全停止）は文字入力中でも必ず効かせる
        if code == KeyboardLayout.escape && capturingSequenceKey == nil && pendingAssign == nil {
            Self.endEditing()
            if !event.isARepeat { panic() }
            return true
        }
        if NSApp.keyWindow?.firstResponder is NSText { return false }

        if let pending = pendingAssign {
            if !event.isARepeat {
                pendingAssign = nil
                if code == KeyboardLayout.escape { return true }
                if let reason = KeyboardLayout.reservedReason(code) {
                    message = reason
                } else if !KeyboardLayout.allKeys.contains(code) {
                    message = L("このキーには割り当てられません（数字・英字・記号・スペースのキーを使ってください）")
                } else {
                    assign(pending.urls, toKey: code, group: pending.group)
                }
            }
            return true
        }
        if let seqID = capturingSequenceKey {
            if code != KeyboardLayout.escape { assignSequenceKey(code, to: seqID) }
            capturingSequenceKey = nil
            return true
        }
        if code == KeyboardLayout.space {
            if !event.isARepeat { endCurrentSequenceSong() }
            return true
        }
        if let cue = cue(forKey: code) {
            if !event.isARepeat { trigger(cue) }
            return true
        }
        if let seq = sequence(forKey: code) {
            if !event.isARepeat { toggleSequence(seq.id) }
            return true
        }
        if code == KeyboardLayout.returnKey || code == KeyboardLayout.enterKey {
            if !event.isARepeat { advanceActiveSequence() }
            return true
        }
        // delete キー: 音量ラインで選んでいるマークを消す
        if code == 51 || code == 117, let action = deleteKeyAction, !showMode {
            action()
            return true
        }
        if code == KeyboardLayout.upArrow || code == KeyboardLayout.downArrow {
            moveCue(by: code == KeyboardLayout.upArrow ? -1 : 1)
            return true
        }
        return false
    }

    // MARK: - 本番モード

    func toggleShowMode() {
        if showMode {
            let alert = NSAlert()
            alert.messageText = L("本番モードを終了しますか？")
            alert.informativeText = L("終了すると、キューシートを編集できるようになります。")
            alert.addButton(withTitle: L("キャンセル"))
            alert.addButton(withTitle: L("本番モードを終了"))
            guard alert.runModal() == .alertSecondButtonReturn else { return }
            showMode = false
        } else {
            Self.endEditing()
            capturingSequenceKey = nil
            pendingAssign = nil
            showMode = true
        }
    }

    /// 本番モード中なら知らせて true（編集の操作の頭で使う）
    private func lockedForShow() -> Bool {
        guard showMode else { return false }
        message = L("本番モード中は編集できません。上の「本番モード」を押して終了してください。")
        return true
    }

    /// 文字入力を終えてキーを音出しに戻す
    static func endEditing() {
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    // MARK: - 再生

    private func makeSpec(_ p: PlaySettings, owner: UUID, tag: UUID, follow: UInt64 = 0, gap: Double = 0,
                          crossfade: Bool = false) -> CueVoiceSpec? {
        guard let b = buffers[p.soundID], b.sampleRate == output.mixer.sampleRate else { return nil }
        let sr = b.sampleRate
        let start = min(max(0, Int(p.inPoint * sr)), b.frames)
        let end = min(b.frames, p.outPoint.map { Int($0 * sr) } ?? b.frames)
        guard end > start else { return nil }
        // 重ねる（クロスフェード）とき、フェードインが 0 なら重なりの長さでフェードインする
        let fadeIn = crossfade && p.fadeIn == 0 ? -gap : p.fadeIn
        nextToken += 1
        var spec = CueVoiceSpec(token: nextToken, owner: owner, tag: tag,
                            left: UnsafePointer(b.left), right: UnsafePointer(b.right),
                            startFrame: start, endFrame: end, loop: p.loop, loopCount: p.loopCount,
                            gain: Float(pow(10, p.volumeDB / 20)),
                            fadeInFrames: Int(fadeIn * sr), fadeOutFrames: Int(p.fadeOut * sr),
                            fadeOutAtEnd: p.fadeOutAtEnd, curve: p.curve,
                            follow: follow, gapFrames: Int(gap * sr), crossfade: crossfade)
        spec.fadeInBezier = p.bezier(rising: true).simd
        spec.fadeOutBezier = p.bezier(rising: false).simd
        spec.envelope = VolumeEnvelope(points: p.volumePoints, sampleRate: sr)
        spec.pan = Float(p.pan)
        spec.panEnvelope = VolumeEnvelope(points: p.panPoints, sampleRate: sr)
        return spec
    }

    func trigger(_ cue: KeyCue) {
        guard let spec = makeSpec(cue.play, owner: cue.id, tag: cue.id) else { return }
        switch cue.retrigger {
        case .fadeOut: output.mixer.send(.toggle(spec))
        case .restart: output.mixer.send(.restart(spec))
        case .layer: output.mixer.send(.play(spec))
        case .ignore: output.mixer.send(.playIfIdle(spec))
        }
    }

    /// 再生中の音の音量を、設定を変えたその場で反映する（キーの音・リストの曲・試聴）
    /// 再生中の音の音量ラインを、編集したその場で反映する
    func liveVolumeLine(_ id: UUID, points: [VolumePoint]) {
        let env = VolumeEnvelope(points: points, sampleRate: sampleRate)
        output.mixer.send(.setEnvelope(id, env))
        output.mixer.send(.setEnvelope(Self.previewOwner, env))
    }

    /// 再生中の音の PANライン を、編集したその場で反映する
    func livePanLine(_ id: UUID, points: [VolumePoint]) {
        let env = VolumeEnvelope(points: points, sampleRate: sampleRate)
        output.mixer.send(.setPanEnvelope(id, env))
        output.mixer.send(.setPanEnvelope(Self.previewOwner, env))
    }

    /// 再生中の音の左右を、その場で反映する
    func livePan(_ id: UUID, pan: Double) {
        output.mixer.send(.setPan(id, Float(pan)))
        output.mixer.send(.setPan(Self.previewOwner, Float(pan)))
    }

    func liveVolume(_ id: UUID, db: Double) {
        let gain = Float(pow(10, db / 20))
        output.mixer.send(.setGain(id, gain))
        output.mixer.send(.setGain(Self.previewOwner, gain))
    }

    /// 鳴っている音の再生位置を秒で移す
    func seek(token: UInt64, to seconds: Double) {
        if showMode { return }
        output.mixer.send(.seek(token, frame: Int(seconds * sampleRate)))
    }

    func preview(_ p: PlaySettings) {
        if lockedForShow() { return }
        guard let spec = makeSpec(p, owner: Self.previewOwner, tag: Self.previewOwner) else { return }
        output.mixer.send(.toggle(spec))
    }

    /// Esc: 全部の音をすぐ止める（フェードなし。プツッと鳴らないよう、ミキサーが数ミリ秒だけ絞る）
    func panic() {
        output.mixer.send(.stopAll(fadeFrames: 0))
        run = nil
    }

    func applyMasterVolume() {
        output.mixer.send(.setMasterGain(Float(pow(10, show.masterVolumeDB / 20))))
    }

    func playing(owner: UUID) -> VoiceStatus? {
        status.last { $0.owner == owner && !$0.armed }
    }

    func playing(tag: UUID) -> VoiceStatus? {
        status.last { $0.tag == tag && !$0.armed }
    }

    // MARK: - リスト（シーケンシャル再生）

    func isRunning(_ id: UUID) -> Bool { run?.sequenceID == id }

    /// Return の対象になるリスト（再生中のもの、無ければ画面で選んでいるもの）
    var activeSequenceID: UUID? { run?.sequenceID ?? selectedSequenceID ?? show.sequences.first?.id }

    func toggleSequence(_ id: UUID) {
        if isRunning(id) { stopSequence(id) } else { startSequence(id, from: cuedIndex(id) ?? 0) }
    }

    private func cuedIndex(_ id: UUID) -> Int? {
        cuedStart.flatMap { $0.sequence == id ? $0.index : nil }
    }

    /// ↑↓: リストの「次に鳴らす曲」を1つ上下に動かす（ダブルクリックと同じ扱い）
    func moveCue(by delta: Int) {
        guard let id = activeSequenceID, let seq = show.sequences.first(where: { $0.id == id }),
              !seq.steps.isEmpty else { return }
        var base = upcomingIndex(id)
        if base == nil, case let .step(s, stepID) = selection, s == id {
            base = seq.steps.firstIndex { $0.id == stepID }
        }
        if base == nil, let r = run, r.sequenceID == id { base = r.currentIndex }
        let index = base.map { min(max($0 + delta, 0), seq.steps.count - 1) } ?? 0
        cueStep(id, index: index)
    }

    /// ダブルクリック: 次に鳴らす曲をこの曲にする（鳴らさない）。Return で鳴る。
    /// リストが鳴っていれば、今の曲の後はこの曲へ（この曲のタイミング設定どおりに）続く
    func cueStep(_ id: UUID, index: Int) {
        Self.endEditing()
        guard let seq = show.sequences.first(where: { $0.id == id }), seq.steps.indices.contains(index) else { return }
        selectedSequenceID = id
        selection = .step(sequence: id, step: seq.steps[index].id)
        if var r = run, r.sequenceID == id {
            if let armed = r.armedToken { output.mixer.send(.stopToken(armed, fadeFrames: 0)) }
            r.armedToken = nil
            r.armedIndex = nil
            r.pendingIndex = nil
            run = r
            if r.isWaiting {
                run?.pendingIndex = index
            } else {
                scheduleNext(to: index)
            }
            cuedStart = nil
        } else {
            cuedStart = (id, index)
        }
    }

    func startSequence(_ id: UUID, from index: Int = 0) {
        guard let seq = show.sequences.first(where: { $0.id == id }) else { return }
        // 別のリストが鳴っていたら停止フェードで止める。
        // 同じリストの中で曲を移るとき（ダブルクリック）は、今の曲をその曲のフェードアウトで止める
        if let r = run, let old = show.sequences.first(where: { $0.id == r.sequenceID }) {
            output.mixer.send(.stopOwner(old.id, fadeFrames: old.id == id ? -1 : Int(old.stopFade * sampleRate)))
            run = nil
        }
        cuedStart = nil
        guard let i = playableIndex(in: seq, from: index) else {
            message = L("再生できる曲がありません")
            return
        }
        playStep(seq, i)
    }

    func stopSequence(_ id: UUID) {
        guard isRunning(id), let seq = show.sequences.first(where: { $0.id == id }) else { return }
        output.mixer.send(.stopOwner(id, fadeFrames: Int(seq.stopFade * sampleRate)))
        run = nil
    }

    /// Return: 再生中のリストの次の曲をすぐ鳴らす。今の曲はその曲のフェードアウト設定で止める。
    /// どのリストも鳴っていなければ、選んでいるリストを開始する
    func advanceActiveSequence() {
        // 鳴っていないリストでダブルクリックして位置を決めてあれば、そのリストをそこから始める
        if let cued = cuedStart, run?.sequenceID != cued.sequence {
            startSequence(cued.sequence, from: cued.index)
            return
        }
        guard let r = run, let seq = show.sequences.first(where: { $0.id == r.sequenceID }) else {
            if let id = activeSequenceID { startSequence(id) }
            return
        }
        // 「Return を押してから n 秒」を待っている間にもう一度 Return を押したら、待たずにすぐ鳴らす
        if let current = r.currentToken, status.contains(where: { $0.token == current && $0.armed }) {
            output.mixer.send(.startNow(current))
            return
        }
        let target = r.pendingIndex ?? r.armedIndex
            ?? r.currentIndex.flatMap { playableIndex(in: seq, from: $0 + 1) }
        if let armed = r.armedToken { output.mixer.send(.stopToken(armed, fadeFrames: 0)) }
        if let current = r.currentToken { output.mixer.send(.stopToken(current, fadeFrames: -1)) }
        guard let target else {
            run = nil
            return
        }
        playStep(seq, target)
    }

    /// スペース: リストの今の曲を途中で終える（その曲のフェードアウトで）。
    /// 次の曲は、その曲のタイミング設定どおりに続く（「Return キーを押したとき」なら待機）
    func endCurrentSequenceSong() {
        guard let current = run?.currentToken else { return }
        output.mixer.send(.stopToken(current, fadeFrames: -1))
    }

    /// 次に Return を押したときに鳴る曲（表示用）
    func upcomingIndex(_ id: UUID) -> Int? {
        if let r = run, r.sequenceID == id { return r.pendingIndex ?? r.armedIndex }
        return cuedIndex(id)
    }

    /// タイミングが「Return キーを押したとき」で秒数があれば、その秒数だけ待ってから鳴らす
    private func playStep(_ seq: CueSequence, _ i: Int) {
        guard var spec = makeSpec(seq.steps[i].play, owner: seq.id, tag: seq.steps[i].id) else { return }
        let step = seq.steps[i]
        if step.start == .returnKey, step.startSeconds > 0 {
            spec.delayFrames = Int(step.startSeconds * sampleRate)
        }
        output.mixer.send(.play(spec))
        run = SequenceRun(sequenceID: seq.id, currentToken: spec.token, currentIndex: i)
        followPlaying(seq.id, i)
        scheduleNext()
    }

    /// 鳴り始めた曲の行を選択状態にする（キーの設定を開いている最中は奪わない）
    private func followPlaying(_ seqID: UUID, _ index: Int) {
        guard let seq = show.sequences.first(where: { $0.id == seqID }), seq.steps.indices.contains(index) else { return }
        switch selection {
        case .key: return
        case .step, .none: break
        }
        selectedSequenceID = seqID
        selection = .step(sequence: seqID, step: seq.steps[index].id)
    }

    private func playableIndex(in seq: CueSequence, from index: Int) -> Int? {
        guard !seq.steps.isEmpty else { return nil }
        for k in 0..<seq.steps.count {
            let j = index + k
            if j >= seq.steps.count && !seq.loop { return nil }
            let i = j % seq.steps.count
            if buffers[seq.steps[i].play.soundID] != nil { return i }
        }
        return nil
    }

    /// 次の曲のタイミングに合わせて、ミキサーに待機させるか Return 待ちにする
    /// next を指定しなければ、今の曲の次の曲
    private func scheduleNext(to forced: Int? = nil) {
        guard var r = run, let seq = show.sequences.first(where: { $0.id == r.sequenceID }),
              let current = r.currentIndex, let token = r.currentToken,
              let next = forced.flatMap({ playableIndex(in: seq, from: $0) }) ?? playableIndex(in: seq, from: current + 1)
        else { return }
        let step = seq.steps[next]
        switch step.start {
        case .afterPrevious, .overlap:
            let gap = step.start == .overlap ? -step.startSeconds : step.startSeconds
            guard let spec = makeSpec(step.play, owner: seq.id, tag: step.id, follow: token, gap: gap,
                                      crossfade: step.start == .overlap) else { return }
            output.mixer.send(.play(spec))
            r.armedToken = spec.token
            r.armedIndex = next
        case .returnKey:
            r.pendingIndex = next
        }
        run = r
    }

    private func advanceSequences() {
        guard let r = run else { return }
        if let armed = r.armedToken, let idx = r.armedIndex,
           status.contains(where: { $0.token == armed && !$0.armed }) {
            run = SequenceRun(sequenceID: r.sequenceID, currentToken: armed, currentIndex: idx)
            followPlaying(r.sequenceID, idx)
            scheduleNext()
            return
        }
        // コマンドがまだ音声スレッドに届いていない間は判定しない
        guard let current = r.currentToken, Date().timeIntervalSince(r.changedAt) > 0.25 else { return }
        let alive = status.contains { $0.token == current || $0.token == r.armedToken }
        guard !alive else { return }

        // 前の曲が終わった。次が Return 待ちならリストは待機、無ければ終わり
        if r.pendingIndex != nil {
            var waiting = r
            waiting.currentToken = nil
            waiting.currentIndex = nil
            run = waiting
        } else {
            run = nil
        }
    }

    // MARK: - 音ファイル

    func fileURL(for sound: SoundRef) -> URL? {
        if let url = pendingFiles[sound.id] { return url }
        guard let showURL else { return nil }
        return ShowPackage.audioURL(for: sound, in: showURL)
    }

    func sound(_ id: UUID) -> SoundRef? { show.sounds.first { $0.id == id } }

    private func addSound(_ url: URL) -> SoundRef? {
        guard let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .audio) else {
            message = L("音ファイルではありません: %@", url.lastPathComponent)
            return nil
        }
        guard let duration = AudioDecoder.duration(of: url) else {
            message = L("読み込めません: %@", url.lastPathComponent)
            return nil
        }
        let s = SoundRef(fileName: url.lastPathComponent,
                         displayName: url.deletingPathExtension().lastPathComponent, duration: duration)
        pendingFiles[s.id] = url
        show.sounds.append(s)
        load(s)
        return s
    }

    private func load(_ sound: SoundRef) {
        guard let url = fileURL(for: sound), FileManager.default.fileExists(atPath: url.path) else {
            loadStates[sound.id] = .failed(L("ファイルが見つかりません"))
            return
        }
        loadStates[sound.id] = .loading
        let sr = output.sampleRate
        let id = sound.id
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result { try AudioDecoder.decode(url: url, sampleRate: sr) }
            }.value
            finishLoad(id, result)
        }
    }

    private func finishLoad(_ id: UUID, _ result: Result<SampleBuffer, Error>) {
        guard show.sounds.contains(where: { $0.id == id }) else { return }
        switch result {
        case .success(let b):
            if b.sampleRate != output.sampleRate, let s = sound(id) {
                load(s)
                return
            }
            retire(buffers[id])
            buffers[id] = b
            loadStates[id] = .ready
        case .failure(let e):
            loadStates[id] = .failed(e.localizedDescription)
        }
    }

    /// 鳴っている最中かもしれない音データは、すぐに解放せず少し待ってから手放す
    private func retire(_ buffer: SampleBuffer?) {
        guard let buffer else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { _ = buffer }
    }

    private func reloadAllSounds() {
        for b in buffers.values { retire(b) }
        buffers = [:]
        show.sounds.forEach(load)
    }

    // MARK: - キーの割り当て

    func cue(forKey code: UInt16) -> KeyCue? { show.keyCues.first { $0.keyCode == code } }

    func sequence(forKey code: UInt16) -> CueSequence? { show.sequences.first { $0.toggleKey == code } }

    func assign(_ urls: [URL], toKey code: UInt16, group: UUID? = nil) {
        if lockedForShow() { return }
        guard let url = urls.first else { return }
        if let reason = KeyboardLayout.reservedReason(code) {
            message = reason
            return
        }
        if let seq = sequence(forKey: code) {
            message = L("このキーはリスト「%@」の開始／停止キーです", seq.name)
            return
        }
        guard let s = addSound(url) else { return }
        if let i = show.keyCues.firstIndex(where: { $0.keyCode == code }) {
            show.keyCues[i].play.soundID = s.id
            show.keyCues[i].play.inPoint = 0
            show.keyCues[i].play.outPoint = nil
            show.keyCues[i].name = s.displayName
        } else {
            var cue = NewSoundDefaults.keyCue(keyCode: code, name: s.displayName, soundID: s.id)
            cue.colorIndex = show.keyCues.count % Self.colors.count
            cue.groupID = group
            show.keyCues.append(cue)
        }
        selection = .key(code)
    }

    /// 古いキューシートで操作用のキー（スペースなど）に割り当てていたものを外して知らせる
    @discardableResult
    private func releaseReservedKeys() -> Bool {
        var released: [String] = []
        for cue in show.keyCues where KeyboardLayout.reservedReason(cue.keyCode) != nil {
            released.append(L("「%@」（%@）", cue.name, KeyboardLayout.label(cue.keyCode)))
        }
        show.keyCues.removeAll { KeyboardLayout.reservedReason($0.keyCode) != nil }
        for i in show.sequences.indices {
            if let k = show.sequences[i].toggleKey, KeyboardLayout.reservedReason(k) != nil {
                released.append(L("リスト「%@」の開始／停止キー（%@）", show.sequences[i].name, KeyboardLayout.label(k)))
                show.sequences[i].toggleKey = nil
            }
        }
        if !released.isEmpty {
            message = L("次の割り当てを外しました。スペース・Return・Esc は操作用のキーです。\n") + released.joined(separator: "\n")
        }
        return !released.isEmpty
    }

    /// キーの割り当てを別のキーへ移す。移り先も割り当て済みなら入れ替える（音・リストの開始／停止キーとも）
    func moveKey(from: UInt16, to: UInt16) {
        if lockedForShow() { return }
        guard from != to else { return }
        if let reason = KeyboardLayout.reservedReason(to) {
            message = reason
            return
        }
        let srcCue = show.keyCues.firstIndex { $0.keyCode == from }
        let dstCue = show.keyCues.firstIndex { $0.keyCode == to }
        let srcSeq = show.sequences.firstIndex { $0.toggleKey == from }
        let dstSeq = show.sequences.firstIndex { $0.toggleKey == to }
        guard srcCue != nil || srcSeq != nil else { return }
        if let i = srcCue { show.keyCues[i].keyCode = to }
        if let i = srcSeq { show.sequences[i].toggleKey = to }
        if let i = dstCue { show.keyCues[i].keyCode = from }
        if let i = dstSeq { show.sequences[i].toggleKey = from }
        selection = .key(to)
    }

    func removeCue(atKey code: UInt16) {
        if lockedForShow() { return }
        if let cue = cue(forKey: code) { output.mixer.send(.stopOwner(cue.id, fadeFrames: 0)) }
        show.keyCues.removeAll { $0.keyCode == code }
    }

    func cueBinding(_ code: UInt16) -> Binding<KeyCue>? {
        guard let cue = cue(forKey: code) else { return nil }
        let id = cue.id
        return Binding(
            get: { self.show.keyCues.first { $0.id == id } ?? cue },
            set: { new in
                if let i = self.show.keyCues.firstIndex(where: { $0.id == id }) { self.show.keyCues[i] = new }
            })
    }

    private func assignSequenceKey(_ code: UInt16, to id: UUID) {
        if let reason = KeyboardLayout.reservedReason(code) {
            message = reason
            return
        }
        if let cue = cue(forKey: code) {
            message = L("このキーには「%@」が割り当て済みです", cue.name)
            return
        }
        for i in show.sequences.indices where show.sequences[i].toggleKey == code {
            show.sequences[i].toggleKey = nil
        }
        if let i = show.sequences.firstIndex(where: { $0.id == id }) { show.sequences[i].toggleKey = code }
    }

    /// 音ファイルを選んでから、割り当てるキーを押してもらう（キーボードを隠しているとき）
    func chooseFileThenKey(group: UUID?) {
        if lockedForShow() { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        pendingAssign = ([url], group)
    }

    // MARK: - キー一覧のグループ

    /// グループごとのキー（未分類 = nil を先頭に）。並びは show.keyCues の順
    func cues(in group: UUID?) -> [KeyCue] {
        let known = Set(show.keyGroups.map(\.id))
        return show.keyCues.filter { cue in
            group == nil ? (cue.groupID == nil || !known.contains(cue.groupID!)) : cue.groupID == group
        }
    }

    func addKeyGroup() {
        show.keyGroups.append(KeyGroup(name: L("グループ%d", show.keyGroups.count + 1)))
    }

    func removeKeyGroup(_ id: UUID) {
        for i in show.keyCues.indices where show.keyCues[i].groupID == id { show.keyCues[i].groupID = nil }
        show.keyGroups.removeAll { $0.id == id }
    }

    func moveKeyGroup(_ id: UUID, by delta: Int) {
        guard let i = show.keyGroups.firstIndex(where: { $0.id == id }) else { return }
        let j = i + delta
        guard show.keyGroups.indices.contains(j) else { return }
        show.keyGroups.swapAt(i, j)
    }

    func renameKeyGroup(_ id: UUID, to name: String) {
        if let i = show.keyGroups.firstIndex(where: { $0.id == id }) { show.keyGroups[i].name = name }
    }

    func setGroup(_ group: UUID?, forCue id: UUID) {
        guard let i = show.keyCues.firstIndex(where: { $0.id == id }) else { return }
        var cue = show.keyCues.remove(at: i)
        cue.groupID = group
        show.keyCues.append(cue)   // 移動先のグループの末尾へ
    }

    /// グループの中で並べ替える
    func moveCues(in group: UUID?, from offsets: IndexSet, to destination: Int) {
        var ordered: [[KeyCue]] = [cues(in: nil)] + show.keyGroups.map { cues(in: $0.id) }
        let k = group.flatMap { g in show.keyGroups.firstIndex { $0.id == g }.map { $0 + 1 } } ?? 0
        ordered[k].move(fromOffsets: offsets, toOffset: destination)
        show.keyCues = ordered.flatMap { $0 }
    }

    // MARK: - リストの編集

    func addSequence() {
        if lockedForShow() { return }
        var seq = CueSequence(name: L("リスト%d", show.sequences.count + 1))
        seq.loop = true
        show.sequences.append(seq)
        selectedSequenceID = seq.id
    }

    func removeSequence(_ id: UUID) {
        if lockedForShow() { return }
        stopSequence(id)
        show.sequences.removeAll { $0.id == id }
        selectedSequenceID = show.sequences.first?.id
    }

    func appendSteps(_ urls: [URL], to id: UUID) {
        if lockedForShow() { return }
        guard let i = show.sequences.firstIndex(where: { $0.id == id }) else { return }
        for url in urls {
            guard let s = addSound(url) else { continue }
            show.sequences[i].steps.append(NewSoundDefaults.step(name: s.displayName, soundID: s.id))
        }
    }

    func removeStep(_ stepID: UUID, from id: UUID) {
        if lockedForShow() { return }
        guard let i = show.sequences.firstIndex(where: { $0.id == id }) else { return }
        show.sequences[i].steps.removeAll { $0.id == stepID }
        if selection == .step(sequence: id, step: stepID) { selection = .none }
    }

    func sequenceBinding(_ id: UUID) -> Binding<CueSequence>? {
        guard let seq = show.sequences.first(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { self.show.sequences.first { $0.id == id } ?? seq },
            set: { new in
                if let i = self.show.sequences.firstIndex(where: { $0.id == id }) { self.show.sequences[i] = new }
            })
    }

    func stepBinding(sequence id: UUID, step stepID: UUID) -> Binding<SequenceStep>? {
        guard let seqBinding = sequenceBinding(id),
              let step = seqBinding.wrappedValue.steps.first(where: { $0.id == stepID }) else { return nil }
        return Binding(
            get: { seqBinding.wrappedValue.steps.first { $0.id == stepID } ?? step },
            set: { new in
                if let i = seqBinding.wrappedValue.steps.firstIndex(where: { $0.id == stepID }) {
                    seqBinding.wrappedValue.steps[i] = new
                }
            })
    }

    // MARK: - ファイル

    func newShow() {
        if lockedForShow() { return }
        guard confirmDiscard() else { return }
        output.mixer.send(.stopAll(fadeFrames: 0))
        run = nil
        cuedStart = nil
        for b in buffers.values { retire(b) }
        buffers = [:]
        loadStates = [:]
        pendingFiles = [:]
        showURL = nil
        selection = .none
        show = Show(name: L("新しいキューシート"))
        selectedSequenceID = nil
        dirty = false
        applyMasterVolume()
    }

    func openPanel() {
        if lockedForShow() { return }
        guard confirmDiscard() else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.cacaoSoundCuesShow]
        panel.treatsFilePackagesAsDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        open(url)
    }

    /// 起動時に前回のキューシートを開くときは、本番モード中でも開く
    func open(_ url: URL, evenInShowMode: Bool = false, remember: Bool = true) {
        if !evenInShowMode, lockedForShow() { return }
        do {
            let loaded = try ShowPackage.load(from: url)
            output.mixer.send(.stopAll(fadeFrames: 0))
            run = nil
            cuedStart = nil
            for b in buffers.values { retire(b) }
            buffers = [:]
            loadStates = [:]
            pendingFiles = [:]
            showURL = url
            selection = .none
            show = loaded
            let released = releaseReservedKeys()
            selectedSequenceID = loaded.sequences.first?.id
            dirty = released
            applyMasterVolume()
            show.sounds.forEach(load)
            if remember {
                UserDefaults.standard.set(url.path, forKey: "lastShowPath")
                NSDocumentController.shared.noteNewRecentDocumentURL(url)
            }
        } catch {
            message = L("開けません: %@", error.localizedDescription)
        }
    }

    @discardableResult
    func save() -> Bool {
        guard let showURL else { return saveAs() }
        return write(to: showURL)
    }

    @discardableResult
    func saveAs() -> Bool {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.cacaoSoundCuesShow]
        panel.nameFieldStringValue = show.name
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        return write(to: url)
    }

    private func write(to url: URL) -> Bool {
        // どこからも使われていない音は保存しない
        var used = Set(show.keyCues.map(\.play.soundID))
        show.sequences.forEach { used.formUnion($0.steps.map(\.play.soundID)) }
        let sounds = show.sounds.filter { used.contains($0.id) }
        if sounds.count != show.sounds.count { show.sounds = sounds }
        do {
            let saved = try ShowPackage.save(show, to: url, source: { self.fileURL(for: $0) })
            show = saved
            showURL = url
            pendingFiles = [:]
            dirty = false
            UserDefaults.standard.set(url.path, forKey: "lastShowPath")
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
            return true
        } catch {
            message = L("保存できません: %@", error.localizedDescription)
            return false
        }
    }

    /// 未保存の変更があれば確認する。続けてよければ true
    func confirmDiscard() -> Bool {
        guard dirty else { return true }
        let alert = NSAlert()
        alert.messageText = L("「%@」の変更を保存しますか？", show.name)
        alert.addButton(withTitle: L("保存"))
        alert.addButton(withTitle: L("キャンセル"))
        alert.addButton(withTitle: L("保存しない"))
        switch alert.runModal() {
        case .alertFirstButtonReturn: return save()
        case .alertThirdButtonReturn: return true
        default: return false
        }
    }

    func confirmQuit() -> Bool {
        if showMode {
            let alert = NSAlert()
            alert.messageText = L("本番モード中です。終了しますか？")
            alert.addButton(withTitle: L("キャンセル"))
            alert.addButton(withTitle: L("終了する"))
            if alert.runModal() != .alertSecondButtonReturn { return false }
        } else if isPlaying {
            let alert = NSAlert()
            alert.messageText = L("再生中です。終了しますか？")
            alert.addButton(withTitle: L("キャンセル"))
            alert.addButton(withTitle: L("終了する"))
            if alert.runModal() != .alertSecondButtonReturn { return false }
        }
        return confirmDiscard()
    }
}
