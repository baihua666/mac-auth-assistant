import Foundation
import Combine
import AuthCore

@MainActor
final class UpdateController: ObservableObject {
    enum Phase: String { case idle, checking, downloading, verifying, ready, installing }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var releases: [AppRelease] = []
    @Published private(set) var message = "尚未检查更新"
    @Published private(set) var errorMessage: String?
    @Published private(set) var progress = 0.0
    @Published private(set) var latest: AppRelease?
    @Published private(set) var lastCheckedAt: Date?
    @Published private(set) var automatic: Bool
    @Published private(set) var channel: UpdateChannel
    @Published private(set) var skipped: String?
    @Published var selection: String?
    let current: BuildIdentity
    let installResult: String?
    private let service: any UpdateServing
    private let preferences: UserDefaults
    private var operation: Task<Void, Never>?
    private var timer: Timer?
    private var generation = 0
    private var prepared: (releaseID: String, candidate: URL, root: URL)?
    var busy: Bool { [.checking, .downloading, .verifying, .installing].contains(phase) }
    var selected: AppRelease? { releases.first { $0.id == selection } ?? latest ?? releases.first }
    var visibleReleases: [AppRelease] { releases.filter { channel == .preview || !$0.prerelease } }
    var canDownload: Bool {
        guard !busy, let release = selected else { return false }
        return release.asset != nil && release.version.isNewer(than: current.version, build: release.build, currentBuild: current.build)
    }
    var canInstall: Bool { phase == .ready && prepared?.releaseID == selected?.id }

    init(preferences: UserDefaults = .standard, service: any UpdateServing = GitHubUpdateService(),
         current: BuildIdentity = .read(), readResult: Bool = true) {
        self.preferences = preferences; self.service = service; self.current = current
        automatic = preferences.object(forKey: "updatesAutomatic") as? Bool ?? true
        channel = UpdateChannel(rawValue: preferences.string(forKey: "updatesChannel") ?? "") ?? .stable
        skipped = preferences.string(forKey: "updatesSkipped")
        lastCheckedAt = preferences.object(forKey: "updatesLastSuccess") as? Date
        if readResult, let result = try? String(contentsOf: UpdateInstaller.resultURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines) {
            installResult = result == "installed" ? "上次更新已安装；当前版本为 \(current.label)" : "上次更新未完成（\(result)），请重新检查；原设置仍保留"
        } else { installResult = nil }
    }
    func start() {
        checkAutomatically()
        let timer = Timer(timeInterval: 1800, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkAutomatically() }
        }
        RunLoop.main.add(timer, forMode: .common); self.timer = timer
    }
    func setAutomatic(_ value: Bool) { automatic = value; preferences.set(value, forKey: "updatesAutomatic") }
    func setChannel(_ value: UpdateChannel) {
        guard !busy else { return }
        channel = value; preferences.set(value.rawValue, forKey: "updatesChannel")
        latest = AppRelease.newest(in: releases, current: current.version, build: current.build, channel: channel, skipped: skipped)
        selection = latest?.id ?? visibleReleases.first?.id
    }
    func skipSelected() {
        guard !busy, let selected, selected.version.isNewer(than: current.version, build: selected.build, currentBuild: current.build) else { return }
        skipped = selected.id; preferences.set(selected.id, forKey: "updatesSkipped")
        latest = AppRelease.newest(in: releases, current: current.version, build: current.build, channel: channel, skipped: skipped)
        message = "已跳过 \(selected.version)；手动检查仍可查看此版本"
    }
    func restoreSkipped() { skipped = nil; preferences.removeObject(forKey: "updatesSkipped"); check() }
    func checkAutomatically(now: Date = Date()) {
        let attempt = preferences.object(forKey: "updatesLastAttempt") as? Date ?? .distantPast
        guard automatic, !busy, now.timeIntervalSince(attempt) >= 86_400 else { return }
        check(manual: false, now: now)
    }
    func check(manual: Bool = true, now: Date = Date()) {
        guard !busy else { return }
        phase = .checking; message = "正在检查 GitHub 发行版本…"; errorMessage = nil
        preferences.set(now, forKey: "updatesLastAttempt")
        generation += 1; let ticket = generation
        operation = Task {
            do {
                let found = try await service.releases(architecture: BuildIdentity.architecture)
                try Task.checkCancellation(); guard ticket == generation else { return }
                releases = found; lastCheckedAt = now; preferences.set(now, forKey: "updatesLastSuccess")
                latest = AppRelease.newest(in: found, current: current.version, build: current.build, channel: channel, skipped: manual ? nil : skipped)
                selection = latest?.id ?? visibleReleases.first?.id
                if let latest { message = "发现新版本 \(latest.version)" + (latest.asset == nil ? "，尚无适用于本机的可验证安装包" : "") }
                else if visibleReleases.isEmpty { message = "尚无已发布的发行版本" }
                else { message = !manual && skipped != nil ? "没有需要提醒的新版本，已跳过的版本仍可手动查看" : "当前已是此通道的最新版本" }
                phase = prepared?.releaseID == selection ? .ready : .idle
            } catch { finish(error, ticket: ticket) }
        }
    }
    func download() {
        guard canDownload, let release = selected, let asset = release.asset else { return }
        clearPrepared(); phase = .downloading; progress = 0; errorMessage = nil; message = "正在下载安装包…"
        generation += 1; let ticket = generation
        operation = Task {
            var root: URL?
            do {
                let archive = try await service.download(asset) { [weak self] value in
                    Task { @MainActor [weak self] in if self?.generation == ticket { self?.progress = value } }
                }
                root = archive.deletingLastPathComponent()
                try Task.checkCancellation(); guard ticket == generation else { if let root { try? FileManager.default.removeItem(at: root) }; return }
                phase = .verifying; message = "正在校验版本、系统要求和应用签名…"
                let currentURL = Bundle.main.bundleURL
                let candidate = try await Task.detached { try UpdatePackage.unpack(archive: archive, release: release, current: currentURL) }.value
                try Task.checkCancellation(); guard ticket == generation else { if let root { try? FileManager.default.removeItem(at: root) }; return }
                prepared = (release.id, candidate, archive.deletingLastPathComponent())
                phase = .ready; message = "安装包校验通过，可以安装并重启"
            } catch {
                if let root { try? FileManager.default.removeItem(at: root) }
                finish(error, ticket: ticket)
            }
        }
    }
    func install(permitted: Bool, launch: (URL) throws -> Void = { try UpdateInstaller.launch(candidate: $0) }, quit: () -> Void) {
        guard canInstall, let prepared else { return }
        guard permitted else { errorMessage = "正在处理系统授权，请等本次处理结束后再安装"; return }
        do {
            try launch(prepared.candidate); phase = .installing; message = "正在退出并安装更新…"; quit()
        } catch { errorMessage = error.localizedDescription; message = "未能开始安装，当前应用未改动" }
    }
    func cancel() {
        guard phase != .installing else { return }
        generation += 1; operation?.cancel(); operation = nil; phase = .idle; message = "本次更新操作已取消"; errorMessage = nil
        clearPrepared()
    }
    private func finish(_ error: Error, ticket: Int) {
        guard ticket == generation else { return }
        phase = .idle
        if error is CancellationError || (error as NSError).code == NSURLErrorCancelled { message = "本次更新操作已取消" }
        else { errorMessage = error.localizedDescription; message = "更新操作失败，请重试" }
    }
    private func clearPrepared() {
        if let prepared { try? FileManager.default.removeItem(at: prepared.root) }
        prepared = nil
    }
}
