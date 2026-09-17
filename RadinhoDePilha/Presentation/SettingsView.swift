import SwiftUI

/// Settings, built so that every choice can be made without seeing the screen.
///
/// Two principles shape it. Each option carries a spoken description rather than only a label, so
/// a listener knows what a persona or a voice tier means before selecting it. And every choice can
/// be heard on request, because reading "Aprimorada" tells you nothing about whether you want to
/// listen to it for ninety minutes.
///
/// Nothing here speaks on its own. This screen stays mounted while another tab is on top, so its
/// change handlers also fire for adjustments made on the narration screen: a setting that
/// demonstrated itself would talk over a match in progress. Sound comes only from a control whose
/// purpose is to produce it.
struct SettingsView: View {
    @Bindable var settings: AppSettings

    /// Speaks the previews. The same service the match narration uses, so a preview sounds exactly
    /// like the real thing rather than approximating it.
    let speech: any SpeechService

    @State private var voices: [InstalledVoice] = []

    /// Whether a voice better than compact exists, read once rather than per render.
    @State private var hasHighQualityVoice = false

    /// Identifier of the voice in use, recomputed only when the list or the choice changes.
    private var selectedVoiceID: String? {
        settings.resolvedVoice(among: voices)?.id
    }

    /// Real match used to preview the personas, loaded once.
    @State private var showcase: PersonaShowcase?

    var body: some View {
        NavigationStack {
            Form {
                personaSection
                voiceSection
                rateSection
                textSizeSection
            }
            .navigationTitle("Ajustes")
            .task {
                // Read once. Querying the system voice list is expensive, and doing it while the
                // list renders is what made this screen stutter.
                voices = VoiceCatalog.available()
                hasHighQualityVoice = voices.contains { $0.quality > .compact }
                showcase = PersonaShowcase.bundled() ?? .sample()
            }
        }
    }

    // MARK: - Persona

    private var personaSection: some View {
        Section {
            ForEach(NarratorPersona.allCases, id: \.self) { persona in
                HStack(spacing: 12) {
                    Button {
                        settings.persona = persona
                    } label: {
                        row(
                            title: persona.displayName,
                            subtitle: persona.summary,
                            isSelected: settings.persona == persona
                        )
                        // Takes the space left over, so every play button lands on the trailing
                        // edge instead of tracking the width of the text beside it.
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(persona.displayName)
                    .accessibilityValue(settings.persona == persona ? "Selecionado" : "")
                    .accessibilityHint("Toque duas vezes para narrar com esta voz")

                    // Separate from selecting, so hearing a persona does not mean adopting it:
                    // someone comparing three should be able to listen to all of them first.
                    Button {
                        Task { await speech.speakNow(excerpt(for: persona), priority: .high) }
                    } label: {
                        Image(systemName: "play.circle.fill")
                            .font(.title)
                            .symbolRenderingMode(.hierarchical)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Ouvir exemplo do narrador \(persona.displayName)")
                    .accessibilityHint("Narra um gol de verdade com este estilo")
                }
            }
        } header: {
            Text("Narrador")
        } footer: {
            Text(
                """
                Muda as palavras da narração, não a voz do aparelho. Toque no botão de play para \
                ouvir o mesmo gol narrado em cada estilo.
                """
            )
        }
    }

    // MARK: - Voice

    private var voiceSection: some View {
        Section {
            if voices.isEmpty {
                Text("Nenhuma voz em português encontrada neste aparelho.")
                    .foregroundStyle(.secondary)
            }

            ForEach(voices) { voice in
                Button {
                    settings.voiceIdentifier = voice.id
                    Task { await speech.setVoice(identifier: voice.id) }
                } label: {
                    row(
                        title: voice.name,
                        subtitle: "Qualidade \(voice.quality.displayName.lowercased())",
                        isSelected: selectedVoiceID == voice.id
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(voice.displayName)
                .accessibilityValue(selectedVoiceID == voice.id ? "Selecionada" : "")
                .accessibilityHint("Toque duas vezes para narrar com esta voz")
            }

            if !voices.isEmpty {
                sampleButton(label: "Ouvir esta voz")
            }
        } header: {
            Text("Voz")
        } footer: {
            // Surfaced only when it applies. Telling someone to download a better voice when they
            // already have one would be noise; withholding it when they do not would leave them
            // assuming the compact voice is the best the app can do.
            if hasHighQualityVoice {
                Text("As vozes aprimoradas e premium são mais confortáveis em narrações longas.")
            } else {
                Text(
                    """
                    Só há vozes compactas instaladas. Para uma narração mais confortável, \
                    baixe uma voz aprimorada em Ajustes, Acessibilidade, Conteúdo Falado, Vozes, \
                    Português (Brasil).
                    """
                )
            }
        }
    }

    // MARK: - Rate

    private var rateSection: some View {
        Section {
            Picker("Velocidade", selection: $settings.rate) {
                ForEach(SpeechRate.allCases, id: \.self) { rate in
                    Text(rate.displayName).tag(rate)
                }
            }
            .pickerStyle(.inline)

            sampleButton(label: "Ouvir nesta velocidade")
        } header: {
            Text("Velocidade da fala")
        } footer: {
            Text(
                """
                Ouvintes experientes de leitor de tela costumam preferir velocidades altas. \
                Durante uma narração, a mudança vale já na frase que está sendo falada.
                """
            )
        }
    }

    // MARK: - Text size

    private var textSizeSection: some View {
        Section {
            Picker("Tamanho do texto", selection: $settings.textSize) {
                ForEach(TextSizePreference.allCases, id: \.self) { size in
                    Text(size.displayName).tag(size)
                }
            }
            .pickerStyle(.inline)

            sampleLayout
        } header: {
            Text("Tamanho do texto")
        } footer: {
            Text("O exemplo acima muda junto, para você ver o resultado antes de sair daqui.")
        }
    }

    /// Live preview of the chosen size, laid out like the narration screen.
    ///
    /// Shows a scoreboard and a commentary line rather than abstract sample text, because the
    /// question a listener is actually asking is whether *the match screen* will be readable.
    private var sampleLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Exemplo")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline) {
                Text("Náutico")
                Spacer(minLength: 8)
                Text("2").fontWeight(.bold).monospacedDigit()
            }
            .font(.title2)

            Text("Aos 52 do segundo tempo. Gol do Náutico! Marquinhos empata o jogo.")
                .font(.body)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 12))
        .dynamicTypeSize(settings.textSize.dynamicTypeSize ?? .large)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Exemplo de como a tela de narração vai aparecer")
    }

    // MARK: - Shared row

    private func row(title: String, subtitle: String, isSelected: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Checkmark plus bold title: selection is never signalled by colour alone.
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(isSelected ? .semibold : .regular))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Plays a sample on request.
    ///
    /// Explicit rather than automatic. A setting that speaks on its own would talk over a match in
    /// progress, and this screen stays mounted while other tabs are on top, so its change handlers
    /// also fire for adjustments made elsewhere. Asking to hear something is unambiguous.
    private func sampleButton(label: String) -> some View {
        Button {
            Task { await speech.speakNow(excerpt(for: settings.persona), priority: .high) }
        } label: {
            Label(label, systemImage: "play.circle.fill")
        }
        .accessibilityHint("Narra um gol de verdade com os ajustes atuais")
    }

    // MARK: - Previews spoken aloud

    /// Excerpt for a persona, narrated by the engine rather than stored as text.
    private func excerpt(for persona: NarratorPersona) -> String {
        showcase?.narration(persona: persona) ?? persona.sample
    }
}

#Preview("Ajustes") {
    SettingsView(settings: AppSettings(), speech: AVSpeechService())
}
