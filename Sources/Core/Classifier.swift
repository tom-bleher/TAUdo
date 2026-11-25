import Foundation

/// Hebrew/English heuristics for Moodle event titles (ported from the web app's classifier).
/// Note: תרגיל = exercise/homework, תרגול = recitation.
enum Classifier {
    private static func rx(_ p: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: p, options: [.caseInsensitive])
    }

    private static let problemSet = [
        rx(#"(?:^|[\s\-–—:(\[])(תרגיל(?:\s+בית|\s+תכנות|\s+רשות|\s+חובה)?|תרגילי\s+בית|מטל[הת]|בוחן|עבוד[הת](?:\s+בית)?|פרויקט|גי?ליון|יש\s+להגיש|להגשה|תאריך\s+הגשה|מועד\s+אחרון\s+להגשה)"#),
        rx(#"\b(problem\s*set|pset|p\.?s\.?\s*\d+|hw\s*#?\d*|homework|assignment|exercise|ex\.?\s*#?\d+|quiz|worksheet|sheet\s*#?\d+|submission|is\s+due|closes)\b"#),
    ]
    private static let notProblemSet = [
        rx(#"(?:^|[\s\-–—:])(תרגול|הרצאה|שיעור|שעת קבלה|שעות קבלה|זום)(?:$|[\s\-–—:0-9])"#),
        rx(#"\b(lecture|recitation|tutorial|office\s+hours?|zoom|webinar)\b"#),
    ]
    /// Captures the assignment number, e.g. "תרגיל בית 3", "HW #4", "Problem Set 05", "גיליון 2".
    private static let number = [
        rx(#"(?:תרגילי?\s+בית|שיעורי\s+בית|תרגיל|מטלה|גי?ליון)\s*(?:מס['׳"]?\s*|מספר\s*|#\s*)?(\d{1,2})(?!\d)"#),
        rx(#"\b(?:problem\s*set|pset|p\.?s\.?|hw|homework|assignment|exercise|ex\.?|sheet)\s*#?\s*(\d{1,2})(?!\d)"#),
    ]

    private static let exam = [
        // "מועד א/ב" (exam sittings) but not "מועד אחרון" (deadline).
        rx(#"(?:^|[\s\-–—:(\[])(מבחן|בחינה|מועד\s+[אב](?=['׳"״]|\s|$))"#),
        rx(#"\b(exam|midterm|final\s+exam)\b"#),
    ]

    private static func matches(_ r: NSRegularExpression, _ s: String) -> Bool {
        r.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    static func isExam(_ summary: String) -> Bool { exam.contains { matches($0, summary) } }

    /// Moodle's title for an assignment's due date: "יש להגיש את '…'" in Hebrew, "… is due" in English.
    /// (Quizzes close with "תאריך הגשה …" / "… closes"; those aren't assignments.)
    private static let assignmentDue = rx(#"^\s*יש\s+להגיש\s+את\s|\sis\s+due\s*$"#)
    static func isAssignmentDue(_ summary: String) -> Bool { matches(assignmentDue, summary) }

    /// Anything with a due date you act on: problem sets, quizzes, exams.
    /// "Quiz 3 opens" / "נפתח ב בוחן 3" (Hebrew Moodle): an opening, not a deadline.
    private static let opening = rx(#"(\bopens|נפתח[ת]?)\s*$|^\s*נפתח[ת]?\s"#)

    static func isProblemSet(summary: String, description: String = "") -> Bool {
        if matches(opening, summary) { return false }
        if isExam(summary) { return true }
        if problemSet.contains(where: { matches($0, summary) }) { return true }
        if notProblemSet.contains(where: { matches($0, summary) }) { return false }
        if description.range(of: #"/mod/(assign|quiz)/view\.php"#, options: .regularExpression) != nil { return true }
        return false
    }

    static func assignmentNumber(_ summary: String) -> Int? {
        for r in number {
            if let m = r.firstMatch(in: summary, range: NSRange(summary.startIndex..., in: summary)),
               let g = Range(m.range(at: 1), in: summary), let n = Int(summary[g]), n > 0 { return n }
        }
        return nil
    }

    /// Strips Moodle's wrappers: "X is due", "יש להגיש את 'X'", "תאריך הגשה X", "X - יש להגיש".
    static func cleanTitle(_ s: String) -> String {
        let t = s.replacingOccurrences(of: #"^\s*(יש\s+להגיש\s+את|תאריך\s+הגשה|נפתח[ת]?\s+ב?)\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+(is\s+due|closes|opens)\s*$"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\s*[-–—]?\s*(יש\s+להגיש|מועד\s+אחרון\s+להגשה)\s*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "'\"׳״‘’“”")))
        return t.isEmpty ? s : t
    }
}
