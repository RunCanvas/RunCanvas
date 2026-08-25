import Foundation
import Supabase

// publishable 키는 클라이언트에 넣도록 설계된 공개 키. 데이터 접근은 서버의 RLS가 제한한다.
// 프로젝트: runcanvas (kqakxyzssscoyppargws, ap-northeast-2)
let supabase = SupabaseClient(
    supabaseURL: URL(string: "https://kqakxyzssscoyppargws.supabase.co")!,
    supabaseKey: "sb_publishable_XKjYaEnfzSW-ulsWbL64CA_vTleT2zG"
)
