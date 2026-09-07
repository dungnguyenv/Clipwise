import SwiftUI

struct ImageEditorPane: View {
    @Bindable var session: EditorSession

    var body: some View {
        if let document = session.document {
            Image(nsImage: document.baseImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(12)
                .background(Color(nsColor: .underPageBackgroundColor))
        } else {
            Text("This image could not be loaded.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
