import SwiftUI

struct HomeView: View {
    let onAddStatement: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Copy a statement to your clipboard and paste it here.")
                        .font(.title2.weight(.semibold))

                    Text("Cashew turns the text into transactions you can review, categorize, and share.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                Text("Cashew handles most formats from any bank, including online activity, text copied from PDFs, and CSV or spreadsheet rows. No reformatting is required.")
                    .font(.body)
                    .foregroundStyle(.secondary)

                Button(action: onAddStatement) {
                    Text("Add Statement")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: 600, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(24)
        }
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.inline)
    }
}
