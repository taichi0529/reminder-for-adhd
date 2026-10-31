/// 音声出力の監視とミュートの解除。status は変わったら観測できるようにする (@Observable)
@MainActor
protocol AudioOutput: AnyObject {
    var status: AudioStatus { get }

    func start()
    /// ミュートを外す。音量は変えない
    func unmute()
}
