import Foundation
import Supabase

// publishable 키는 클라이언트에 넣도록 설계된 공개 키. 데이터 접근은 서버의 RLS가 제한한다.
// 프로젝트: runcanvas (kqakxyzssscoyppargws, ap-northeast-2)
let supabase = SupabaseClient(
    supabaseURL: URL(string: "https://kqakxyzssscoyppargws.supabase.co")!,
    supabaseKey: "sb_publishable_XKjYaEnfzSW-ulsWbL64CA_vTleT2zG",
    options: SupabaseClientOptions(
        // 저장된 세션을 만료 여부와 상관없이 바로 initialSession으로 내보낸다 (다음 메이저의 기본 동작, 콘솔 경고 제거).
        // 만료된 세션은 첫 API 호출 때 SDK가 자동 갱신한다.
        auth: .init(emitLocalSessionAsInitialSession: true)
    )
)
