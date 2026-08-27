import Foundation

/// 페이스·칼로리·표시 포맷. 플랜 Task 1.2와 동일 — Phase 1에서 다시 만들지 말 것.
enum RunMath {
    static func paceSecondsPerKm(distanceMeters: Double, seconds: Int) -> Double? {
        guard distanceMeters >= 10 else { return nil }
        return Double(seconds) / (distanceMeters / 1000)
    }

    /// 체중(kg) × 거리(km) × 1.036 — 달리기 표준 근사.
    static func calories(distanceMeters: Double, weightKg: Double) -> Double {
        weightKg * (distanceMeters / 1000) * 1.036
    }

    static func formatPace(_ secondsPerKm: Double?) -> String {
        guard let s = secondsPerKm, s.isFinite else { return "--'--\"" }
        let total = Int(s.rounded())
        return String(format: "%02d'%02d\"", total / 60, total % 60)
    }

    static func formatDuration(_ seconds: Int) -> String {
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    static func formatKm(_ meters: Double) -> String {
        String(format: "%.2f", meters / 1000)
    }
}
