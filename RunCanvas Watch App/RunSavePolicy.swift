import Foundation

enum RunSavePolicy {
    /// 50m 이하(무이동 포함)는 시간과 관계없이 저장하지 않는다.
    static func shouldSave(distanceMeters: Double) -> Bool {
        distanceMeters.isFinite && distanceMeters > 50
    }
}
