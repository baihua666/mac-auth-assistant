import AppKit
import ApplicationServices
import AuthCore

extension AppState {
    func performSubmission(_ original: DetectedDialog) {
        remaining = nil
        hideCountdown?()
        pending = nil
        let token = generation
        let ticket = SubmissionTicket(generation: token, now: ProcessInfo.processInfo.systemUptime)
        guard automationConditions.isReady,
              let fresh = scanner.scan().first(where: { $0.id == original.id }),
              original.isSameForm(as: fresh), rejection(for: fresh) == nil, scanner.isFocused(fresh),
              let passwordField = fresh.password else {
            recordSubmission(.submissionStopped, dialog: original, code: 1)
            status = "目标窗口已变化，本次未提交"
            return
        }
        do {
            guard let credentials = try store.load() else {
                setEnabled(false); status = "未找到管理员凭据，请重新设置"; return
            }
            if let accountField = fresh.account, fresh.accountValue != credentials.account {
                guard AX.settable(accountField, kAXValueAttribute),
                      AXUIElementSetAttributeValue(accountField, kAXValueAttribute as CFString,
                                                   credentials.account as CFString) == .success else {
                    recordSubmission(.submissionStopped, dialog: original, code: 2)
                    status = "无法填写管理员账号，本次未提交"; return
                }
            }
            let staged = scanner.inspect(fresh.window, pid: fresh.pid, id: fresh.id)
            guard staged.context == fresh.context, rejection(for: staged) == nil,
                  staged.account == nil || staged.accountValue == credentials.account,
                  let stagedPassword = staged.password, CFEqual(passwordField, stagedPassword),
                  scanner.isFocused(staged), ticket.isValid(now: ProcessInfo.processInfo.systemUptime, generation: generation),
                  let events = PasswordKeyboardEvents.make(for: credentials.password) else {
                recordSubmission(.submissionStopped, dialog: original, code: 3)
                status = "系统拒绝填写或窗口已变化，本次未提交"; return
            }
            guard passwordIsFocused(in: staged) ||
                    AXUIElementSetAttributeValue(passwordField, kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success,
                  passwordIsFocused(in: staged) else {
                recordSubmission(.submissionStopped, dialog: original, code: 8)
                status = "系统未允许密码框获得输入焦点，本次未填写"; return
            }
            processing = true
            for index in stride(from: 0, to: events.count, by: 2) {
                guard automationConditions.isReady, ticket.isValid(now: ProcessInfo.processInfo.systemUptime, generation: generation),
                      scanner.isFocused(staged), passwordIsFocused(in: staged) else {
                    recordSubmission(.submissionStopped, dialog: original, code: 9)
                    processing = false
                    status = "输入前目标已变化，本次未确认"; return
                }
                // Never use the session/global event stream or the clipboard for credentials.
                events[index].postToPid(staged.pid)
                events[index + 1].postToPid(staged.pid)
            }
            recordSubmission(.passwordWritten, dialog: staged)
            status = "已填写，正在重新核对确认目标"
            // Let the target process consume the directed input before pressing its real button.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.confirm(staged, generation: token, ticket: ticket)
            }
        } catch {
            setEnabled(false)
            status = error.localizedDescription
        }
    }

    private func confirm(_ original: DetectedDialog, generation token: Int, ticket: SubmissionTicket) {
        guard automationConditions.isReady, token == generation,
              ticket.isValid(now: ProcessInfo.processInfo.systemUptime, generation: generation),
              let fresh = scanner.scan().first(where: { $0.id == original.id }),
              original.isSameForm(as: fresh), !administratorBlocked(fresh), scanner.isFocused(fresh), passwordIsFocused(in: fresh),
              fresh.password != nil,
              let submit = fresh.submitElement, AX.bool(submit, kAXEnabledAttribute),
              AX.actions(submit).contains(fresh.submitAction),
              ticket.isValid(now: ProcessInfo.processInfo.systemUptime, generation: generation) else {
            recordSubmission(.submissionStopped, dialog: original, code: 4)
            processing = false
            status = "确认前目标已变化或系统不支持直接填写，本次未提交"
            return
        }
        guard AXUIElementPerformAction(submit, fresh.submitAction as CFString) == .success else {
            recordSubmission(.submissionStopped, dialog: original, code: 5)
            processing = false
            status = "系统拒绝自动确认，请手动处理；本次不会重试"
            return
        }
        awaitingResult = true
        recordSubmission(.confirmationSent, dialog: fresh)
        status = "已提交一次，等待系统结果"
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self else { return }
            self.processing = false
            self.awaitingResult = false
            guard token == self.generation else { return }
            if self.scanner.scan().contains(where: { $0.id == original.id }) {
                self.recordSubmission(.submissionStopped, dialog: original, code: 6)
                self.setEnabled(false)
                self.status = "提交后窗口仍存在，自动处理已暂停；请检查密码或手动完成"
            } else {
                self.activity.finish(token: original.activityToken, outcome: .success,
                                     reason: "自动确认后弹窗已关闭；原任务的业务结果需另行核对")
                self.status = "已提交，授权窗口已关闭；请以原操作结果为准"
            }
        }
    }

    private func passwordIsFocused(in dialog: DetectedDialog) -> Bool {
        guard let password = dialog.password,
              let focused = AX.element(AXUIElementCreateApplication(dialog.pid), kAXFocusedUIElementAttribute) else { return false }
        return CFEqual(password, focused)
    }
}
