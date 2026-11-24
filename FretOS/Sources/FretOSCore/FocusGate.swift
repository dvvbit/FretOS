/// Decides whether keystrokes may be sent, based on which app is in front.
public enum FocusGate {
    public static func allows(frontmostAppName: String?, bundleID: String?, onlyWhenCloneHeroFront: Bool) -> Bool {
        guard onlyWhenCloneHeroFront else { return true }
        return [frontmostAppName, bundleID].contains { isCloneHero($0) }
    }

    public static func isCloneHero(_ s: String?) -> Bool {
        guard let s = s?.lowercased() else { return false }
        return s.contains("clone hero") || s.contains("clonehero")
    }
}
