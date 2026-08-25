import SwiftUI

struct PrimaryButton: View {
    let title: String
    var systemImage: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(.headline).foregroundStyle(.white)
            .frame(maxWidth: .infinity).padding()
            .background(.black).clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }
}
