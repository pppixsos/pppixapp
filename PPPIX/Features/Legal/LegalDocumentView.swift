import SwiftUI

struct LegalDocumentView: View {
    let title: String
    let content: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#0A0A12").ignoresSafeArea()

                ScrollView {
                    Text(content)
                        .font(.system(size: 14))
                        .foregroundColor(Color(white: 0.7))
                        .lineSpacing(5)
                        .padding(20)
                        .frame(maxWidth: 680)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fechar") { dismiss() }
                        .foregroundColor(Color(hex: "#3366FF"))
                }
            }
        }
    }
}
