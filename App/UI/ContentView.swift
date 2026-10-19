import CoroKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var engine: LyricsEngine
    @ObservedObject var auth: SpotifyAuth
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                LyricsScroller(lyrics: engine.lyrics, frame: engine.frame,
                               isLoading: engine.isLoadingLyrics, isRunning: engine.isRunning)
                controls
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Coro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "slider.horizontal.3") }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(engine: engine, auth: auth)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Picker("Fuente", selection: $engine.sourceKind) {
                ForEach(SourceKind.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .onChange(of: engine.sourceKind) {
                if engine.isRunning { Task { await engine.restart() } }
            }

            if let track = engine.snapshot?.track {
                Text(track.title).font(.headline).lineLimit(1)
                Text(track.artist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                ProgressView(value: track.duration > 0 ? min(1, engine.position / track.duration) : 0)
                    .tint(.white)
            }
            if let message = engine.setupMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote).foregroundStyle(.yellow)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let message = engine.transientMessage {
                Label(message, systemImage: "wifi.exclamationmark")
                    .font(.footnote).foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
    }

    private var controls: some View {
        VStack(spacing: 12) {
            if engine.sourceKind == .spotify && !auth.isLoggedIn {
                Button {
                    Task {
                        do { try await auth.logIn() } catch { engine.report(error) }
                    }
                } label: {
                    Label("Conectar Spotify", systemImage: "link")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .controlSize(.large)
            }

            Button {
                if engine.isRunning { engine.stop() } else { Task { await engine.start() } }
            } label: {
                Label(engine.isRunning ? "Parar" : "Empezar",
                      systemImage: engine.isRunning ? "stop.fill" : "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(engine.isRunning ? .red : .white)
            .foregroundStyle(engine.isRunning ? .white : .black)
            .controlSize(.large)
            .disabled(engine.sourceKind == .spotify && !auth.isLoggedIn)

            Text("Pulsa Empezar con el coche parado. La letra aparecerá en CarPlay como actividad en directo.")
                .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding()
    }
}

/// Karaoke-style list that keeps the active line centered.
struct LyricsScroller: View {
    let lyrics: Lyrics
    let frame: LyricsFrame?
    let isLoading: Bool
    let isRunning: Bool

    var body: some View {
        Group {
            switch lyrics {
            case .synced(let lines) where !isLoading:
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 18) {
                            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                                Text(line.text.isEmpty ? LyricsFrame.musicNote : line.text)
                                    .font(.system(size: index == frame?.index ? 30 : 24, weight: .bold))
                                    .foregroundStyle(lineColor(index))
                                    .id(index)
                                    .animation(.easeOut(duration: 0.25), value: frame?.index)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 200)
                    }
                    .onChange(of: frame?.index) { _, newIndex in
                        guard let newIndex else { return }
                        withAnimation(.easeInOut(duration: 0.4)) { proxy.scrollTo(newIndex, anchor: .center) }
                    }
                }
            case .plain(let lines) where !isLoading:
                ScrollView {
                    Text(lines.joined(separator: "\n"))
                        .font(.title3.weight(.semibold))
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            default:
                VStack(spacing: 12) {
                    Image(systemName: isRunning ? "music.note" : "car.fill")
                        .font(.system(size: 48))
                    Text(isRunning ? (frame?.current ?? "Esperando música…") : "Elige la fuente y pulsa Empezar")
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func lineColor(_ index: Int) -> Color {
        guard let active = frame?.index else { return .white.opacity(0.35) }
        if index == active { return .white }
        return index < active ? .white.opacity(0.3) : .white.opacity(0.5)
    }
}

struct SettingsView: View {
    @ObservedObject var engine: LyricsEngine
    @ObservedObject var auth: SpotifyAuth

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading) {
                        Text("Desfase: \(engine.syncOffset, specifier: "%+.2f") s")
                        Slider(value: $engine.syncOffset, in: -2...2, step: 0.05)
                    }
                } header: {
                    Text("Sincronía")
                } footer: {
                    Text("Sube el valor si la letra llega tarde; bájalo si se adelanta. Con Bluetooth suele ir bien +0,3 s.")
                }

                Section {
                    Picker("Tamaño de la letra", selection: $engine.carPlayStyle) {
                        ForEach(CarPlayStyle.allCases, id: \.self) { style in
                            Text(style.title).tag(style)
                        }
                    }
                } header: {
                    Text("CarPlay")
                } footer: {
                    Text("Se aplica al momento: cámbialo con la letra en pantalla y mira el coche. El tamaño del recuadro lo decide CarPlay.")
                }

                Section {
                    Toggle("Mantener activo con el móvil bloqueado", isOn: $engine.keepAliveInBackground)
                } footer: {
                    Text("Usa la ubicación en baja precisión para que iOS no suspenda la app mientras conduces. Solo en el prototipo.")
                }

                Section("Spotify") {
                    if !AppConfig.isSpotifyConfigured {
                        Text("Falta SPOTIFY_CLIENT_ID en Config.xcconfig").foregroundStyle(.yellow)
                    } else if auth.isLoggedIn {
                        Button("Cerrar sesión", role: .destructive) { auth.logOut() }
                    } else {
                        Text("No conectado").foregroundStyle(.secondary)
                    }
                }

                Section {
                    Text("Letras de LRCLIB, descargadas en tu dispositivo. No leas mientras conduces.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Ajustes")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
