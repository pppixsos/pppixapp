import SwiftUI
import WebKit

/// Tela do tutorial de instalação com vídeo YouTube embutido.
/// Para adicionar o vídeo: troque o valor de `videoID` pelo ID do vídeo
/// do YouTube (ex: em https://youtube.com/watch?v=ABC123 o ID é "ABC123").
struct InstallTutorialView: View {
    @Environment(\.dismiss) private var dismiss

    /// TODO: substituir pelo ID do vídeo do YouTube quando disponível.
    private let videoID = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#0A0A12").ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        if videoID.isEmpty {
                            VStack(spacing: 14) {
                                Image(systemName: "play.rectangle.fill")
                                    .font(.system(size: 44))
                                    .foregroundColor(Color(white: 0.25))
                                Text("Vídeo em breve")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                Text("O tutorial em vídeo será adicionado aqui em breve.")
                                    .font(.subheadline)
                                    .foregroundColor(Color(white: 0.45))
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 220)
                            .background(Color(hex: "#141422"))
                            .cornerRadius(16)
                        } else {
                            YouTubePlayerView(videoID: videoID)
                                .frame(height: 220)
                                .cornerRadius(16)
                                .clipped()
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("O que você vai aprender")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.white)
                            Text("Como verificar se as permissões, senhas, contatos de emergência e bloqueio de apps estão corretamente configurados para garantir o funcionamento do PPPIX.")
                                .font(.footnote)
                                .foregroundColor(Color(white: 0.55))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(Color(hex: "#141422"))
                        .cornerRadius(12)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                }
            }
            .navigationTitle("Tutorial de Instalação")
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

private struct YouTubePlayerView: UIViewRepresentable {
    let videoID: String

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.scrollView.isScrollEnabled = false
        webView.backgroundColor = .black
        webView.isOpaque = false
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        guard !videoID.isEmpty else { return }
        let html = """
        <html><body style="margin:0;background:#000;">
        <iframe width="100%" height="100%"
            src="https://www.youtube.com/embed/\(videoID)?playsinline=1"
            frameborder="0" allowfullscreen></iframe>
        </body></html>
        """
        uiView.loadHTMLString(html, baseURL: URL(string: "https://www.youtube.com"))
    }
}
