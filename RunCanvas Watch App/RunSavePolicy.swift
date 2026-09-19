import Foundation

enum RunSavePolicy {
    /// 50m 이하(무이동 포함)는 저장하지 않는다.
    ///
    /// 시간은 여기서 보지 않는다. 0초짜리도 저장한다 — 거리가 워치에서 한 번에 들어와
    /// "거리는 있는데 시간이 0"이 될 수 있는데, 그걸 버리면 실제로 뛴 기록이 사라진다.
    /// 0초에서 페이스가 00'00" 으로 찍히던 문제는 RunMath.paceSecondsPerKm 이 nil 을 내서 막는다.
    ///
    /// 폰(RunCanvas/Models)과 워치("RunCanvas Watch App") 사본은 **글자까지 같아야 한다** —
    /// 두 타깃이 파일을 공유하지 않아 중복이고, RunSavePolicyTests 가 두 파일을 통째로 비교한다.
    static func shouldSave(distanceMeters: Double) -> Bool {
        distanceMeters.isFinite && distanceMeters > 50
    }
}
