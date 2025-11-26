public protocol HapticProvider {
    func prepare()
    func play(_ emotion: SenseEmotion)
    func startHeartbeat()
    func stopHeartbeat()
}
