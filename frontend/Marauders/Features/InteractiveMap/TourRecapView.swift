import SwiftUI

struct TourRecapView: View {
    let completedChapters: [TajMapCheckpoint]
    let monumentName: String

    @StateObject private var store = TourRecapStore()
    @State private var picked: [UUID: Int] = [:]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch store.state {
                    case .idle, .generating:
                        HStack { ProgressView(); Text("Writing your recap…") }
                            .foregroundStyle(Theme.mutedInk)
                            .frame(maxWidth: .infinity).padding(.vertical, 40)
                    case .failed(let message):
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.primary)
                    case .ready(let recap):
                        recapContent(recap)
                    }
                }
                .padding(20)
            }
            .background(Theme.surfaceLow)
            .navigationTitle("Tour Recap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
        .task { store.generate(completedChapters: completedChapters, monumentName: monumentName) }
    }

    @ViewBuilder
    private func recapContent(_ recap: TourRecap) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Your journal", systemImage: "book.pages.fill")
                    .font(.headline).foregroundStyle(Theme.primary)
                Spacer()
                if recap.generatedOnDevice {
                    Label("On-device", systemImage: "cpu.fill")
                        .font(.caption2.bold()).foregroundStyle(Theme.teal)
                }
            }
            Text(recap.journal).foregroundStyle(Theme.ink).lineSpacing(4)
        }
        .padding(18)
        .heritageCard()

        Text("How closely were you listening?")
            .font(.headline).foregroundStyle(Theme.primary)
            .padding(.top, 4)

        ForEach(recap.questions) { question in
            questionCard(question)
        }

        if picked.count == recap.questions.count {
            let score = recap.questions.filter { picked[$0.id] == $0.answerIndex }.count
            Label("\(score) of \(recap.questions.count) correct — \(score == recap.questions.count ? "a true Marauder!" : "the stories are ready to replay in Audio Exp.")", systemImage: score == recap.questions.count ? "trophy.fill" : "arrow.counterclockwise.circle.fill")
                .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.gold)
                .frame(maxWidth: .infinity)
                .padding(16)
                .heritageCard()
        }
    }

    private func questionCard(_ question: TourRecap.Question) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(question.prompt).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
            ForEach(Array(question.choices.enumerated()), id: \.offset) { index, choice in
                Button {
                    guard picked[question.id] == nil else { return }
                    withAnimation(.snappy) { picked[question.id] = index }
                } label: {
                    HStack {
                        Text(choice).multilineTextAlignment(.leading)
                        Spacer()
                        if let selection = picked[question.id] {
                            if index == question.answerIndex {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.teal)
                            } else if index == selection {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.primary)
                            }
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(choiceColor(question: question, index: index))
                    .padding(.horizontal, 14).padding(.vertical, 11)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 14).stroke(Theme.outline.opacity(0.65)) }
                }
                .disabled(picked[question.id] != nil)
            }
        }
        .padding(16)
        .heritageCard()
    }

    private func choiceColor(question: TourRecap.Question, index: Int) -> Color {
        guard let selection = picked[question.id] else { return Theme.ink }
        if index == question.answerIndex { return Theme.teal }
        if index == selection { return Theme.primary }
        return Theme.mutedInk
    }
}
