import Foundation

enum RunSavePolicy {
    /// 50m 이하(무이동 포함)는 저장하지 않는다. 0초짜리도 저장하지 않는다 —
    /// 거리는 워치에서 한 번에 들어올 수 있어 "거리는 있는데 시간이 0"인 조합이 실제로 만들어지고,
    /// 그러면 페이스가 00'00"으로 찍힌다.
    ///
    /// 폰(RunCanvas/Models)과 워치("RunCanvas Watch App") 사본은 **글자까지 같아야 한다** —
    /// 두 타깃이 파일을 공유하지 않아 중복이고, RunSavePolicyTests 가 두 파일을 통째로 비교한다.
    static func shouldSave(distanceMeters: Double, seconds: Int = 1) -> Bool {
        distanceMeters.isFinite && distanceMeters > 50 && seconds > 0
    }
}
