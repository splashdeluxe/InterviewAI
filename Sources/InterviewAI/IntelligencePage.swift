import AppKit
import SwiftData
import SwiftUI
import InterviewAIKit

/// The Profile page. One structured profile for the role being chased,
/// in the shape Interview Pilot uses: sources first (a resume and a job
/// description, picked from files of the right kind), standing
/// instructions the copilot applies to every answer, extra background
/// the resume misses, and the generated sections under it. Profile and
/// talking points come from the user's own documents through their
/// provider; company intel adds a web search when a Tavily key is set.
/// The newest instructions, extra background, and talking points are
/// fed into live answers (see AppModel.profileContext).
struct IntelligencePage: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var store
    @Query(sort: \IntelligenceDoc.createdAt, order: .reverse) private var docs: [IntelligenceDoc]
    @Query(sort: \ContextFile.createdAt) private var files: [ContextFile]

    @State private var resumeID: PersistentIdentifier?
    @State private var jobID: PersistentIdentifier?
    @State private var companyName = ""
    @State private var busy: String?
    @State private var errorText: String?
    @State private var editingKind: String?
    @State private var instructionsDraft = ""
    @State private var extraDraft = ""
    @State private var draftsLoaded = false

    private var resumes: [ContextFile] { files.filter { $0.kind == "resume" } }
    private var jobs: [ContextFile] { files.filter { $0.kind == "job" } }
    private var resume: ContextFile? { resumes.first(where: { $0.id == resumeID }) ?? resumes.first }
    private var job: ContextFile? { jobs.first(where: { $0.id == jobID }) ?? jobs.first }

    private func doc(_ kind: String) -> IntelligenceDoc? { docs.first { $0.kind == kind } }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HSplitView {
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.lg) {
                        sourcesPanel
                        instructionsPanel
                        extraPanel
                        documentsPanel
                    }
                    .padding(Space.lg)
                }
                .frame(minWidth: 300, idealWidth: 340, maxWidth: 430) // grid: ok reading column cap

                ScrollView {
                    VStack(alignment: .leading, spacing: Space.lg) {
                        section(kind: "profile", title: "About You",
                                emptyText: "Nothing here yet. Build Profile reads your resume and writes the short version your answers should use.",
                                canGenerate: resume != nil) { await generateProfile() }
                        section(kind: "talkingPoints", title: "Talking Points",
                                emptyText: "Nothing here yet. Pick a job description, then build. These points also feed your live answers.",
                                canGenerate: resume != nil && job != nil) { await generateTalkingPoints() }
                        section(kind: "companyIntel", title: "Company Intel",
                                emptyText: "Nothing here yet. Name the company in Sources, then build.",
                                canGenerate: !companyName.trimmingCharacters(in: .whitespaces).isEmpty) { await generateCompanyIntel() }
                        section(kind: "coverLetter", title: "Cover Letter",
                                emptyText: "Nothing here yet. Pick a job description, then generate.",
                                canGenerate: resume != nil && job != nil) { await generateCoverLetter() }
                    }
                    .padding(Space.lg)
                }
                .frame(minWidth: 380)
            }
        }
        .background(Surface.canvas)
        .navigationTitle("Profile")
        .onAppear {
            guard !draftsLoaded else { return }
            instructionsDraft = doc("instructions")?.text ?? ""
            extraDraft = doc("extraInfo")?.text ?? ""
            draftsLoaded = true
        }
        .onChange(of: instructionsDraft) { _, newValue in
            guard draftsLoaded else { return }
            persist(kind: "instructions", label: "Standing instructions", text: newValue)
        }
        .onChange(of: extraDraft) { _, newValue in
            guard draftsLoaded else { return }
            persist(kind: "extraInfo", label: "Extra background", text: newValue)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: Space.lg) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("Profile")
                    .font(.title3.weight(.semibold))
                Text("One profile for the role you are chasing. It grounds every live answer.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if let errorText {
                    Text(errorText)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            Spacer()
            if let busy {
                HStack(spacing: Space.sm) {
                    ProgressView().controlSize(.small)
                    Text(busy).font(.callout).foregroundStyle(.secondary)
                }
            }
            Button("Build Profile") { buildProfile() }
                .buttonStyle(InkButtonStyle())
                .disabled(resume == nil || busy != nil)
                .help(resume == nil ? "Add a resume on the Context page first" : "Write About You, Talking Points, and Company Intel in one run")
        }
        .padding(Space.lg)
    }

    // MARK: Left column

    private var sourcesPanel: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Text("Sources").font(.headline)
            if resumes.isEmpty {
                Text("No resume in Context yet.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Open Context") { model.sidebar = .context }
                    .buttonStyle(QuietButtonStyle())
            } else {
                Picker("Resume", selection: $resumeID) {
                    ForEach(resumes) { file in
                        Text(file.name).tag(Optional(file.id))
                    }
                }
                .labelsHidden()
            }
            if jobs.isEmpty {
                Text("No job description in Context yet. Talking points and the cover letter need one.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                Picker("Job description", selection: $jobID) {
                    ForEach(jobs) { file in
                        Text(file.name).tag(Optional(file.id))
                    }
                }
                .labelsHidden()
            }
            TextField("Company (for Company Intel)", text: $companyName)
                .textFieldStyle(.roundedBorder)
            Text("The pickers only offer files of the right kind, so a job description can never land in the resume slot.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.lg)
        .panelSurface()
    }

    private var instructionsPanel: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text("Instructions for every answer").font(.headline)
            TextEditor(text: $instructionsDraft)
                .font(.callout)
                .frame(minHeight: 76)
                .scrollContentBackground(.hidden)
                .padding(Space.sm)
                .background(Surface.inset, in: RoundedRectangle(cornerRadius: Radius.control))
            Text("Applied to every response in this profile. For example: first person, under a minute of speech, name a metric when you have one.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.lg)
        .panelSurface()
    }

    private var extraPanel: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text("More about you").font(.headline)
            TextEditor(text: $extraDraft)
                .font(.callout)
                .frame(minHeight: 76)
                .scrollContentBackground(.hidden)
                .padding(Space.sm)
                .background(Surface.inset, in: RoundedRectangle(cornerRadius: Radius.control))
            Text("Achievements, interests, career goals, anything the resume misses.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.lg)
        .panelSurface()
    }

    private var documentsPanel: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text("Documents").font(.headline)
            if files.isEmpty {
                Text("Nothing attached yet. Files you add on the Context page land here.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(files) { file in
                    HStack(spacing: Space.sm) {
                        Image(systemName: "doc.text")
                            .foregroundStyle(.secondary)
                        Text(file.name)
                            .font(.callout)
                            .lineLimit(1)
                        Spacer()
                        Text("\(kindTitle(file.kind)) · \(wordCount(file.text)) words")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.lg)
        .panelSurface()
    }

    // MARK: Generated sections

    @ViewBuilder
    private func section(kind: String, title: String, emptyText: String, canGenerate: Bool, generate: @escaping () async -> Void) -> some View {
        let current = doc(kind)
        VStack(alignment: .leading, spacing: Space.md) {
            HStack(spacing: Space.sm) {
                Text(title).font(.headline)
                if let current {
                    Text(current.createdAt, format: .dateTime.month().day().hour().minute())
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(current == nil ? "Generate" : "Regenerate") {
                    Task { await generate() }
                }
                .buttonStyle(QuietButtonStyle())
                .disabled(!canGenerate || busy != nil)
            }
            if let current {
                if editingKind == kind {
                    TextEditor(text: textBinding(for: current))
                        .font(.callout)
                        .frame(minHeight: 150) // grid: ok editor minimum height
                        .scrollContentBackground(.hidden)
                        .padding(Space.sm)
                        .background(Surface.inset, in: RoundedRectangle(cornerRadius: Radius.control))
                } else {
                    ScrollView {
                        DocTextView(text: current.text)
                    }
                    .frame(maxHeight: 240)
                }
                HStack(spacing: Space.sm) {
                    Button(editingKind == kind ? "Done" : "Edit") {
                        editingKind = editingKind == kind ? nil : kind
                    }
                    .buttonStyle(QuietButtonStyle())
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(current.text, forType: .string)
                    }
                    .buttonStyle(QuietButtonStyle())
                    Spacer()
                    Button("Delete") {
                        if editingKind == kind { editingKind = nil }
                        store.delete(current)
                        try? store.save()
                    }
                    .buttonStyle(QuietButtonStyle())
                }
            } else {
                Text(emptyText)
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.lg)
        .panelSurface()
    }

    // MARK: Generation

    private func buildProfile() {
        guard resume != nil else { return }
        Task {
            await generateProfile()
            guard errorText == nil else { return }
            if job != nil { await generateTalkingPoints() }
            guard errorText == nil else { return }
            if !companyName.trimmingCharacters(in: .whitespaces).isEmpty { await generateCompanyIntel() }
        }
    }

    private func generateProfile() async {
        guard let resume else { return }
        await run(kind: "profile", label: resume.name, busyLabel: "Reading your resume…",
                  prompt: IntelligencePrompts.profile(resume: resume.text))
    }

    private func generateTalkingPoints() async {
        guard let resume, let job else { return }
        await run(kind: "talkingPoints", label: job.name, busyLabel: "Writing talking points…",
                  prompt: IntelligencePrompts.talkingPoints(resume: resume.text, jobDescription: job.text))
    }

    private func generateCoverLetter() async {
        guard let resume, let job else { return }
        await run(kind: "coverLetter", label: job.name, busyLabel: "Drafting the cover letter…",
                  prompt: IntelligencePrompts.coverLetter(resume: resume.text, jobDescription: job.text))
    }

    private func generateCompanyIntel() async {
        let company = companyName.trimmingCharacters(in: .whitespaces)
        guard !company.isEmpty else { return }
        busy = "Researching \(company)…"
        errorText = nil
        let key = KeychainStore.get(account: "tavily-key")
        let results = (try? await WebSearch.tavily(query: "\(company) company culture engineering blog news 2026", apiKey: key)) ?? []
        let prompt = IntelligencePrompts.companyIntel(company: company, jobDescription: job?.text ?? "", webResults: results)
        await run(kind: "companyIntel", label: company, busyLabel: "Researching \(company)…", prompt: prompt)
    }

    private func run(kind: String, label: String, busyLabel: String, prompt: (system: String, user: String)) async {
        busy = busyLabel
        errorText = nil
        do {
            let text = try await Brain.complete(config: ProviderSettings.config(), apiKey: ProviderSettings.apiKey,
                                                system: prompt.system, user: prompt.user)
            store.insert(IntelligenceDoc(kind: kind, label: label, text: text))
            try? store.save()
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        busy = nil
    }

    // MARK: Small pieces

    private func persist(kind: String, label: String, text: String) {
        if let existing = doc(kind) {
            existing.text = text
        } else if !text.isEmpty {
            store.insert(IntelligenceDoc(kind: kind, label: label, text: text))
        }
        try? store.save()
    }

    private func textBinding(for doc: IntelligenceDoc) -> Binding<String> {
        Binding(get: { doc.text }, set: { doc.text = $0; try? store.save() })
    }

    private func kindTitle(_ kind: String) -> String {
        switch kind {
        case "resume": return "Resume"
        case "job": return "Job description"
        case "notes": return "Notes"
        default: return "File"
        }
    }

    private func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }
}
