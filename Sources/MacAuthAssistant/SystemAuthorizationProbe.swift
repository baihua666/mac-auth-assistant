import Foundation
import Security

enum SystemAuthorizationProbe {
    /// Checks an administrator right without executing a command or retaining a usable authorization reference.
    static func run(prompt: String, completion: @escaping @MainActor (OSStatus) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let status = "system.privilege.admin".withCString { rightName in
                kAuthorizationEnvironmentPrompt.withCString { promptKey in
                    prompt.withCString { promptValue in
                        var right = AuthorizationItem(name: rightName, valueLength: 0, value: nil, flags: 0)
                        var environmentItem = AuthorizationItem(name: promptKey, valueLength: prompt.utf8.count + 1,
                            value: UnsafeMutableRawPointer(mutating: promptValue), flags: 0)
                        return withUnsafeMutablePointer(to: &right) { rightPointer in
                            withUnsafeMutablePointer(to: &environmentItem) { environmentPointer in
                                var rights = AuthorizationRights(count: 1, items: rightPointer)
                                var environment = AuthorizationEnvironment(count: 1, items: environmentPointer)
                                return AuthorizationCreate(&rights, &environment,
                                    [.interactionAllowed, .extendRights, .destroyRights], nil)
                            }
                        }
                    }
                }
            }
            DispatchQueue.main.async { completion(status) }
        }
    }
}
