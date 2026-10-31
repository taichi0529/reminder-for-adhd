/// 音声出力の状態。通知の音が聞こえるか
enum AudioStatus: Equatable, Sendable {
    case audible
    case muted
    case volumeZero
    /// 出力先によってはミュートも音量も取れない
    case unknown

    /// 通知の音が聞こえない状態か
    var isSilent: Bool { self == .muted || self == .volumeZero }
}
